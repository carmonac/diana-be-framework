import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:diana/diana.dart';
import 'package:diana_native/diana_native.dart';
import 'package:test/test.dart';

class _UpperHandler extends BaseWebSocketHandler {
  @override
  void onOpen(WebSocketSession session) =>
      session.sendText('hi ${session.pathParameters['room']}');

  @override
  void onMessage(WebSocketSession session, WebSocketMessage message) {
    if (message case TextMessage(:final text)) {
      session.sendText(text.toUpperCase());
    }
  }
}

Future<DianaServer> _serve(DianaServer server) async {
  await server.serve(port: 0, quiet: true);
  addTearDown(server.close);
  return server;
}

void main() {
  late HttpClient client;
  setUp(() => client = HttpClient());
  tearDown(() => client.close(force: true));

  Future<(int, String, HttpHeaders)> send(
    String method,
    Uri uri, {
    String? body,
  }) async {
    final req = await client.openUrl(method, uri);
    if (body != null) {
      req.headers.contentType = ContentType.json;
      req.write(body);
    }
    final res = await req.close();
    return (
      res.statusCode,
      await res.transform(utf8.decoder).join(),
      res.headers,
    );
  }

  test('DianaNativeEngine is a DianaHttpEngine named native', () {
    const engine = DianaNativeEngine();
    expect(engine, isA<DianaHttpEngine>());
    expect(engine.name, 'native');
  });

  test('serves routes, path params, bodies and the 404 fallback', () async {
    final server = await _serve(
      DianaServer(engine: const DianaNativeEngine())
        ..register(
          HttpMethod.get,
          '/hello/:name',
          (req) => DianaResponse.json({'hello': req.pathParameters['name']}),
        )
        ..register(HttpMethod.post, '/echo', (req) async {
          final body = await req.readBodyAsString();
          return DianaResponse(
            statusCode: 201,
            bodyText: body,
            mimeType: 'application/json',
          );
        }),
    );
    final base = 'http://127.0.0.1:${server.port}';

    final (status, body, headers) = await send(
      'GET',
      Uri.parse('$base/hello/ana'),
    );
    expect(status, 200);
    expect(jsonDecode(body), {'hello': 'ana'});
    expect(headers.contentType?.mimeType, 'application/json');

    final posted = await send('POST', Uri.parse('$base/echo'), body: '{"n":1}');
    expect(posted.$1, 201);
    expect(posted.$2, '{"n":1}');

    final missing = await send('GET', Uri.parse('$base/nope'));
    expect(missing.$1, 404);
    expect(missing.$2, contains('not_found'));
  });

  test('streams SSE through the hijacked connection', () async {
    final events = StreamController<ServerSentEvent>();
    final server = await _serve(
      DianaServer(engine: const DianaNativeEngine())..register(
        HttpMethod.get,
        '/events',
        (req) => sseResponse(req, events.stream),
      ),
    );

    final res = await (await client.getUrl(
      Uri.parse('http://127.0.0.1:${server.port}/events'),
    )).close();
    expect(res.statusCode, 200);
    expect(res.headers.contentType?.mimeType, 'text/event-stream');
    final received = StringBuffer();
    final sub = res.transform(utf8.decoder).listen(received.write);
    events.add(const ServerSentEvent('one', id: '1'));
    await events.close();
    await sub.asFuture<void>().timeout(const Duration(seconds: 5));
    expect(received.toString(), contains('id: 1\ndata: one\n\n'));
  });

  test('upgrades WebSockets', () async {
    final server = await _serve(
      DianaServer(engine: const DianaNativeEngine())
        ..registerWebSocket('/ws/:room', () => _UpperHandler()),
    );

    final socket = await WebSocket.connect(
      'ws://127.0.0.1:${server.port}/ws/lobby',
    );
    final messages = StreamIterator(socket);
    expect(await messages.moveNext(), isTrue);
    expect(messages.current, 'hi lobby');
    socket.add('ping');
    expect(await messages.moveNext(), isTrue);
    expect(messages.current, 'PING');
    await socket.close();
  });

  test('serves HTTPS from server.ssl.*', () async {
    final server = await _serve(
      DianaServer(
        engine: const DianaNativeEngine(),
        config: DianaConfig({
          'server.ssl.certPath': 'test/fixtures/cert.pem',
          'server.ssl.keyPath': 'test/fixtures/key.pem',
        }),
      )..register(
        HttpMethod.get,
        '/ping',
        (req) => const DianaResponse.text('pong'),
      ),
    );

    client.badCertificateCallback = (cert, host, port) => true;
    final (status, body, _) = await send(
      'GET',
      Uri.parse('https://127.0.0.1:${server.port}/ping'),
    );
    expect(status, 200);
    expect(body, 'pong');
  });

  test('isolates binding with shared: true join one bind group', () {
    final binding = DianaEngineBinding(
      address: InternetAddress.loopbackIPv4,
      port: 8080,
      shared: true,
    );
    expect(
      DianaNativeEngine.bindGroup(binding),
      'diana_native/$pid/127.0.0.1:8080',
    );
  });
  test('multi-isolate serving shares one native server', () async {
    final port = 18642 + DateTime.now().millisecond % 100;
    final shutdown = Completer<void>();
    final done = DianaRuntime.run(
      () async {
        final server =
            DianaServer(
              engine: const DianaNativeEngine(),
              config: DianaConfig({'server.port': port, 'server.isolates': 3}),
            )..register(
              HttpMethod.get,
              '/whoami',
              (req) =>
                  DianaResponse.text('isolate ${Isolate.current.hashCode}'),
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

    await Future<void>.delayed(const Duration(milliseconds: 600));
    final served = <String>{};
    for (var i = 0; i < 30; i++) {
      // One client per request so keep-alive does not pin one isolate.
      final c = HttpClient();
      final res = await (await c.getUrl(
        Uri.parse('http://127.0.0.1:$port/whoami'),
      )).close();
      expect(res.statusCode, 200);
      served.add(await res.transform(utf8.decoder).join());
      c.close();
    }
    expect(served.every((s) => s.startsWith('isolate')), isTrue);

    shutdown.complete();
    await done.timeout(const Duration(seconds: 10));
    print('distinct isolates served: ${served.length}');
  }, timeout: const Timeout(Duration(minutes: 1)));
}
