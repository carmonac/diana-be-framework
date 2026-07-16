import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:diana/diana.dart';
import 'package:test/test.dart';

class FireEvent {
  const FireEvent();
}

class UnsendableEvent {
  final ReceivePort port;
  UnsendableEvent(this.port);
}

/// Captures each isolate's bus; the test (running on main) sees only the
/// main isolate's assignment.
DianaEventBus? mainIsolateBus;

Future<String> _get(String url) async {
  // One client per request: keep-alive would pin every request to a single
  // isolate, defeating the shared-socket distribution.
  final client = HttpClient();
  try {
    final res = await (await client.getUrl(Uri.parse(url))).close();
    return await res.transform(utf8.decoder).join();
  } finally {
    client.close();
  }
}

void main() {
  test('DianaRuntime.run: initialize → serve → shutdown → close → dispose',
      () async {
    final events = <String>[];
    final shutdown = Completer<void>();
    late DianaServer server;

    final done = DianaRuntime.run(
      () async {
        server = DianaServer(config: DianaConfig({'server.port': 0}))
          ..register(HttpMethod.get, '/ping',
              (req) => const DianaResponse.text('pong'));
        return DianaRunnable(
          server: server,
          initialize: () async => events.add('initialize'),
          dispose: () async => events.add('dispose'),
        );
      },
      installSignalHandlers: false,
      shutdownTrigger: shutdown.future,
    );

    // Wait until the server is up, prove it serves, then trigger shutdown.
    while (events.isEmpty || server.port == null) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    final client = HttpClient();
    final res = await (await client
            .getUrl(Uri.parse('http://127.0.0.1:${server.port}/ping')))
        .close();
    expect(await res.transform(utf8.decoder).join(), 'pong');
    client.close();

    events.add('shutdown-requested');
    shutdown.complete();
    await done;
    events.add('run-returned');

    expect(events, [
      'initialize',
      'shutdown-requested',
      'dispose',
      'run-returned',
    ]);
  });

  test('multi-isolate serving shares the port and shuts down cleanly',
      () async {
    final port = 18342 + DateTime.now().millisecond % 100;
    final shutdown = Completer<void>();

    final done = DianaRuntime.run(
      () async {
        final server = DianaServer(
          config: DianaConfig({'server.port': port, 'server.isolates': 3}),
        )..register(HttpMethod.get, '/whoami',
            (req) => DianaResponse.text('isolate ${Isolate.current.hashCode}'));
        return DianaRunnable(
          server: server,
          initialize: () async {},
          dispose: () async {},
        );
      },
      installSignalHandlers: false,
      shutdownTrigger: shutdown.future,
    );

    // Let the workers bind, then hammer the port: every request must
    // succeed regardless of which isolate serves it.
    await Future<void>.delayed(const Duration(milliseconds: 600));
    final client = HttpClient();
    for (var i = 0; i < 12; i++) {
      final res = await (await client
              .getUrl(Uri.parse('http://127.0.0.1:$port/whoami')))
          .close();
      expect(res.statusCode, 200);
      expect(await res.transform(utf8.decoder).join(), startsWith('isolate'));
    }
    client.close();

    shutdown.complete();
    await done.timeout(const Duration(seconds: 10));
  });

  test('broadcast events reach every isolate exactly once', () async {
    final port = 18452 + DateTime.now().millisecond % 100;
    final shutdown = Completer<void>();

    final done = DianaRuntime.run(
      () async {
        var count = 0;
        final bus = DianaEventBus()..on<FireEvent>((e) => count++);
        final name = Isolate.current.debugName ?? 'main';
        final server = DianaServer(
          config: DianaConfig({'server.port': port, 'server.isolates': 3}),
        )
          ..register(HttpMethod.get, '/state',
              (req) => DianaResponse.text('$count|$name'))
          ..register(HttpMethod.get, '/fire', (req) async {
            await bus.broadcast(const FireEvent());
            return DianaResponse.text(name);
          });
        return DianaRunnable(
          server: server,
          initialize: () async {},
          dispose: () async {},
          eventBus: bus,
        );
      },
      installSignalHandlers: false,
      shutdownTrigger: shutdown.future,
    );
    await Future<void>.delayed(const Duration(milliseconds: 600));

    // Fire until at least two distinct isolates have served a broadcast
    // (proves worker→main/sibling relay, not just main→worker), capped.
    final firedBy = <String>{};
    var fires = 0;
    while (fires < 30 && (fires < 6 || firedBy.length < 2)) {
      firedBy.add(await _get('http://127.0.0.1:$port/fire'));
      fires++;
    }

    // Every isolate must converge on count == fires (exactly-once each).
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    final counts = <String, int>{};
    while (DateTime.now().isBefore(deadline)) {
      final state = await _get('http://127.0.0.1:$port/state');
      final separator = state.indexOf('|');
      counts[state.substring(separator + 1)] =
          int.parse(state.substring(0, separator));
      final converged = counts.length == 3 &&
          counts.values.every((count) => count == fires);
      if (converged) break;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    expect(counts.length, 3,
        reason: 'all three isolates must serve /state; saw: $counts');
    expect(counts.values, everyElement(fires),
        reason: 'each isolate must receive every broadcast exactly once '
            '(fired $fires times by $firedBy); saw: $counts');

    shutdown.complete();
    await done.timeout(const Duration(seconds: 10));
  });

  test('broadcasting an unsendable event fails fast at the publisher',
      () async {
    final port = 18562 + DateTime.now().millisecond % 100;
    final shutdown = Completer<void>();

    final done = DianaRuntime.run(
      () async {
        final bus = DianaEventBus();
        mainIsolateBus = bus;
        final server = DianaServer(
          config: DianaConfig({'server.port': port, 'server.isolates': 2}),
        );
        return DianaRunnable(
          server: server,
          initialize: () async {},
          dispose: () async {},
          eventBus: bus,
        );
      },
      installSignalHandlers: false,
      shutdownTrigger: shutdown.future,
    );
    await Future<void>.delayed(const Duration(milliseconds: 600));

    final unsendable = UnsendableEvent(ReceivePort());
    await expectLater(
      mainIsolateBus!.broadcast(unsendable),
      throwsA(isA<ArgumentError>().having(
        (e) => e.message,
        'message',
        contains('is not sendable across isolates'),
      )),
    );
    unsendable.port.close();

    shutdown.complete();
    await done.timeout(const Duration(seconds: 10));
  });

  test('@Scheduled runs leader-only by default; perIsolate runs everywhere',
      () async {
    final port = 18672 + DateTime.now().millisecond % 100;
    final shutdown = Completer<void>();

    final done = DianaRuntime.run(
      () async {
        // Replicates what the generated DianaApp does: register tasks,
        // start on initialize, stop on dispose.
        var leaderCount = 0;
        var perIsolateCount = 0;
        final scheduler = DianaScheduler()
          ..schedule(task: () async => leaderCount++, fixedDelayMs: 25)
          ..schedule(
              task: () async => perIsolateCount++,
              fixedDelayMs: 25,
              perIsolate: true);
        final name = Isolate.current.debugName ?? 'main';
        final server = DianaServer(
          config: DianaConfig({'server.port': port, 'server.isolates': 3}),
        )..register(
            HttpMethod.get,
            '/state',
            (req) => DianaResponse.text('$leaderCount|$perIsolateCount|$name'),
          );
        return DianaRunnable(
          server: server,
          initialize: () async => scheduler.start(),
          dispose: () => scheduler.stop(),
        );
      },
      installSignalHandlers: false,
      shutdownTrigger: shutdown.future,
    );
    await Future<void>.delayed(const Duration(milliseconds: 800));

    // Poll until all three isolates have answered, then assert semantics.
    final states = <String, (int, int)>{};
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (DateTime.now().isBefore(deadline)) {
      final state = await _get('http://127.0.0.1:$port/state');
      final parts = state.split('|');
      states[parts[2]] = (int.parse(parts[0]), int.parse(parts[1]));
      final satisfied = states.length == 3 &&
          states.values.every((s) => s.$2 > 0) &&
          states.values.where((s) => s.$1 > 0).length == 1;
      if (satisfied) break;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }

    expect(states.length, 3,
        reason: 'all three isolates must serve /state; saw: $states');
    expect(states.values.where((s) => s.$1 > 0).length, 1,
        reason: 'the leader-only task must run in exactly one isolate '
            '(the main one); saw: $states');
    expect(states.values.every((s) => s.$2 > 0), isTrue,
        reason: 'the perIsolate task must run in every isolate; '
            'saw: $states');

    shutdown.complete();
    await done.timeout(const Duration(seconds: 10));
  });

  test('serves HTTPS when server.ssl.* is configured', () async {
    final server = DianaServer(
      config: DianaConfig({
        'server.ssl.certPath': 'test/fixtures/cert.pem',
        'server.ssl.keyPath': 'test/fixtures/key.pem',
      }),
    )..register(
        HttpMethod.get, '/ping', (req) => const DianaResponse.text('pong'));
    await server.serve(port: 0, quiet: true);
    addTearDown(server.close);

    final client = HttpClient()
      ..badCertificateCallback = (cert, host, port) => true;
    final res = await (await client
            .getUrl(Uri.parse('https://127.0.0.1:${server.port}/ping')))
        .close();
    expect(res.statusCode, 200);
    expect(await res.transform(utf8.decoder).join(), 'pong');
    client.close();
  });
}
