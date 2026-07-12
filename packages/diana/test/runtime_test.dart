import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:diana/diana.dart';
import 'package:test/test.dart';

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
