// Multi-isolate tests poll for cross-isolate convergence with deadlines
// sized for a loaded machine; give them room beyond the default 30s.
@Timeout(Duration(minutes: 2))
library;

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

/// Startup-window plumbing: globals are per isolate, so only the main
/// isolate's bootstrap (and the test itself) touch these instances.
final mainInitializeStarted = Completer<void>();
final mainInitializeGate = Completer<void>();

/// Drain-on-shutdown plumbing (per-isolate: only main's instances matter).
var slowListenerFinished = false;
bool? disposeSawListenerFinished;

Future<bool> _portOpen(int port) async {
  try {
    final socket = await Socket.connect('127.0.0.1', port,
        timeout: const Duration(milliseconds: 250));
    socket.destroy();
    return true;
  } on SocketException {
    return false;
  } on TimeoutException {
    return false;
  }
}

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
    // Generous deadline: under load (e.g. the full verify run) the VM can
    // starve one listener's accepts for seconds; the loop exits early once
    // converged, so the extra headroom costs nothing when healthy.
    final deadline = DateTime.now().add(const Duration(seconds: 30));
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

    // Poll until all three isolates have answered, then assert semantics
    // (30s: accept distribution can starve one isolate for a while under
    // load; the loop exits early once satisfied).
    final states = <String, (int, int)>{};
    final deadline = DateTime.now().add(const Duration(seconds: 30));
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

  test('a worker whose dispose throws does not hang shutdown', () async {
    final port = 18782 + DateTime.now().millisecond % 100;
    final shutdown = Completer<void>();

    final done = DianaRuntime.run(
      () async {
        final isWorker = Isolate.current.debugName?.startsWith('diana-worker');
        final server = DianaServer(
          config: DianaConfig({'server.port': port, 'server.isolates': 2}),
        );
        return DianaRunnable(
          server: server,
          initialize: () async {},
          // The worker's @PreDestroy path failing must be reported (stderr),
          // never deadlock the main isolate's shutdown.
          dispose: () async {
            if (isWorker ?? false) throw StateError('predestroy boom');
          },
        );
      },
      installSignalHandlers: false,
      shutdownTrigger: shutdown.future,
    );
    await Future<void>.delayed(const Duration(milliseconds: 600));

    shutdown.complete();
    await done.timeout(const Duration(seconds: 10));
  });

  test('a worker whose dispose hangs is killed after the timeout', () async {
    final port = 18892 + DateTime.now().millisecond % 100;
    final shutdown = Completer<void>();
    final before = DianaRuntime.workerShutdownTimeout;
    DianaRuntime.workerShutdownTimeout = const Duration(milliseconds: 500);
    addTearDown(() => DianaRuntime.workerShutdownTimeout = before);

    final done = DianaRuntime.run(
      () async {
        final isWorker = Isolate.current.debugName?.startsWith('diana-worker');
        final server = DianaServer(
          config: DianaConfig({'server.port': port, 'server.isolates': 2}),
        );
        return DianaRunnable(
          server: server,
          initialize: () async {},
          dispose: () => (isWorker ?? false)
              ? Completer<void>().future // never completes
              : Future.value(),
        );
      },
      installSignalHandlers: false,
      shutdownTrigger: shutdown.future,
    );
    await Future<void>.delayed(const Duration(milliseconds: 600));

    shutdown.complete();
    await done.timeout(const Duration(seconds: 10));
  });

  test('a crashed worker is detected: shutdown completes anyway', () async {
    final port = 18992 + DateTime.now().millisecond % 100;
    final shutdown = Completer<void>();

    final done = DianaRuntime.run(
      () async {
        final isWorker = Isolate.current.debugName?.startsWith('diana-worker');
        if (isWorker ?? false) {
          // An uncaught async error kills the worker isolate shortly after
          // it starts serving (errorsAreFatal). The onExit sentinel must
          // mark it dead so shutdown skips it instead of waiting forever.
          Timer(const Duration(milliseconds: 200),
              () => throw StateError('worker crash'));
        }
        final server = DianaServer(
          config: DianaConfig({'server.port': port, 'server.isolates': 2}),
        );
        return DianaRunnable(
          server: server,
          initialize: () async {},
          dispose: () async {},
        );
      },
      installSignalHandlers: false,
      shutdownTrigger: shutdown.future,
    );
    // Let the worker start AND crash before requesting shutdown.
    await Future<void>.delayed(const Duration(milliseconds: 800));

    shutdown.complete();
    await done.timeout(const Duration(seconds: 10));
  });

  test('an erroring shutdownTrigger still shuts the app down', () async {
    final done = DianaRuntime.run(
      () async => DianaRunnable(
        server: DianaServer(config: DianaConfig({'server.port': 0})),
        initialize: () async {},
        dispose: () async {},
      ),
      installSignalHandlers: false,
      shutdownTrigger: Future<void>.delayed(const Duration(milliseconds: 100))
          .then((_) => throw StateError('trigger boom')),
    );
    await done.timeout(const Duration(seconds: 10));
  });

  test('no isolate serves until every isolate is initialized', () async {
    final port = 19102 + DateTime.now().millisecond % 100;
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
          initialize: () async {
            // Only the main isolate blocks; workers must not bind the port
            // while it is still initializing.
            if (!DianaRuntime.isWorkerIsolate) {
              mainInitializeStarted.complete();
              await mainInitializeGate.future;
            }
          },
          dispose: () async {},
          eventBus: bus,
        );
      },
      installSignalHandlers: false,
      shutdownTrigger: shutdown.future,
    );

    // Main enters initialize() only after every worker is spawned (each
    // already bootstrapped and initialized). Nothing may serve yet: a
    // request in this window would broadcast against an uninitialized main
    // and miss later-spawned siblings.
    await mainInitializeStarted.future.timeout(const Duration(seconds: 10));
    for (var i = 0; i < 5; i++) {
      expect(await _portOpen(port), isFalse,
          reason: 'no isolate may accept connections before initialize() '
              'completed on the main isolate');
      await Future<void>.delayed(const Duration(milliseconds: 40));
    }

    mainInitializeGate.complete();
    final up = DateTime.now().add(const Duration(seconds: 30));
    while (!await _portOpen(port)) {
      expect(DateTime.now().isBefore(up), isTrue,
          reason: 'the server must come up once initialize() completes');
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }

    // The very first broadcast already reaches all three isolates exactly
    // once: by serve time the relay knows every sibling.
    // 30s: accept distribution can starve one isolate for a while under
    // load; the loop exits early once all three have converged.
    await _get('http://127.0.0.1:$port/fire');
    final counts = <String, int>{};
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (DateTime.now().isBefore(deadline)) {
      final state = await _get('http://127.0.0.1:$port/state');
      final separator = state.indexOf('|');
      counts[state.substring(separator + 1)] =
          int.parse(state.substring(0, separator));
      if (counts.length == 3 && counts.values.every((count) => count == 1)) {
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    expect(counts.length, 3,
        reason: 'all three isolates must serve /state; saw: $counts');
    expect(counts.values, everyElement(1),
        reason: 'the first broadcast must reach every isolate exactly '
            'once; saw: $counts');

    shutdown.complete();
    await done.timeout(const Duration(seconds: 10));
  });

  test('a worker failing to start shuts down already-spawned workers',
      () async {
    final port = 19212 + DateTime.now().millisecond % 100;

    final done = DianaRuntime.run(
      () async {
        // Worker 1 bootstraps fine; worker 2 fails, so startup must tear
        // worker 1 down again instead of leaking it.
        if (Isolate.current.debugName == 'diana-worker-2') {
          throw StateError('boom in worker 2');
        }
        final server = DianaServer(
          config: DianaConfig({'server.port': port, 'server.isolates': 3}),
        )..register(HttpMethod.get, '/ping',
            (req) => const DianaResponse.text('pong'));
        return DianaRunnable(
          server: server,
          initialize: () async {},
          dispose: () async {},
        );
      },
      installSignalHandlers: false,
    );

    await expectLater(
      done.timeout(const Duration(seconds: 10)),
      throwsA(isA<StateError>().having((e) => e.message, 'message',
          contains('worker 2 failed to start'))),
    );
    expect(await _portOpen(port), isFalse,
        reason: 'no orphan worker may keep serving after a failed startup');
  });

  test('main initialize() failing shuts down spawned workers', () async {
    final port = 19322 + DateTime.now().millisecond % 100;

    final done = DianaRuntime.run(
      () async {
        final server = DianaServer(
          config: DianaConfig({'server.port': port, 'server.isolates': 2}),
        );
        return DianaRunnable(
          server: server,
          initialize: () async {
            if (!DianaRuntime.isWorkerIsolate) {
              throw StateError('post-construct failed on main');
            }
          },
          dispose: () async {},
        );
      },
      installSignalHandlers: false,
    );

    await expectLater(
      done.timeout(const Duration(seconds: 10)),
      throwsA(isA<StateError>().having(
          (e) => e.message, 'message', contains('post-construct failed'))),
    );
    expect(await _portOpen(port), isFalse,
        reason: 'the worker must be shut down before run() rethrows');
  });

  test('shutdown drains an in-flight remote dispatch before dispose',
      () async {
    final port = 19432 + DateTime.now().millisecond % 100;
    final shutdown = Completer<void>();

    final done = DianaRuntime.run(
      () async {
        final bus = DianaEventBus()
          ..on<FireEvent>((e) async {
            // Only main's listener is slow: the worker-served /fire relays
            // the event to main, whose dispatch is still running when the
            // test triggers shutdown right after.
            if (DianaRuntime.isWorkerIsolate) return;
            await Future<void>.delayed(const Duration(milliseconds: 300));
            slowListenerFinished = true;
          });
        final name = Isolate.current.debugName ?? 'main';
        final server = DianaServer(
          config: DianaConfig({'server.port': port, 'server.isolates': 2}),
        )..register(HttpMethod.get, '/fire', (req) async {
            await bus.broadcast(const FireEvent());
            return DianaResponse.text(name);
          });
        return DianaRunnable(
          server: server,
          initialize: () async {},
          dispose: () async {
            if (!DianaRuntime.isWorkerIsolate) {
              disposeSawListenerFinished = slowListenerFinished;
            }
          },
          eventBus: bus,
        );
      },
      installSignalHandlers: false,
      shutdownTrigger: shutdown.future,
    );
    await Future<void>.delayed(const Duration(milliseconds: 600));

    // Fire until a WORKER serves the request (main then receives the
    // dispatch as a remote event), then shut down immediately.
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (await _get('http://127.0.0.1:$port/fire') == 'main') {
      expect(DateTime.now().isBefore(deadline), isTrue,
          reason: 'a worker isolate must eventually serve /fire');
    }
    shutdown.complete();
    await done.timeout(const Duration(seconds: 10));

    expect(disposeSawListenerFinished, isTrue,
        reason: 'dispose() must not run while a remote-event listener is '
            "still mid-dispatch (it would tear the listener's dependencies "
            'down underneath it)');
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
