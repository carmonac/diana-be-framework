import 'dart:async';
import 'dart:io';

import 'package:diana/diana.dart';
import 'package:test/test.dart';

class EchoHandler extends BaseWebSocketHandler {
  final events = <String>[];
  int? lastCloseCode;
  String? lastCloseReason;
  final closed = Completer<void>();

  @override
  void onOpen(WebSocketSession session) {
    events.add('open:${session.id}');
    session.sendText('welcome');
  }

  @override
  void onMessage(WebSocketSession session, WebSocketMessage message) {
    switch (message) {
      case TextMessage(:final text):
        events.add('text:$text');
        session.sendText(text.toUpperCase());
      case BinaryMessage(:final data):
        events.add('binary:${data.length}');
        session.sendBytes(data);
    }
  }

  @override
  void onClose(WebSocketSession session, int? code, String? reason) {
    lastCloseCode = code;
    lastCloseReason = reason;
    closed.complete();
  }
}

class RoomHandler extends BaseWebSocketHandler {
  @override
  void onOpen(WebSocketSession session) {
    session.sendText('room=${session.pathParameters['room']} '
        'user=${session.queryParameters['user']}');
  }
}

void main() {
  group('DianaServer WebSockets', () {
    late DianaServer server;

    setUp(() => server = DianaServer());
    tearDown(() => server.close());

    test('echo handler: open greeting, text and binary echo, close info',
        () async {
      final handler = EchoHandler();
      server.registerWebSocket('/ws/echo', () => handler);
      await server.serve(port: 0, quiet: true);

      final client =
          await WebSocket.connect('ws://127.0.0.1:${server.port}/ws/echo');
      final received = <Object?>[];
      final done = Completer<void>();
      client.listen(received.add, onDone: done.complete);

      client.add('hola');
      client.add([1, 2, 3]);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      await client.close(4001, 'bye');
      await handler.closed.future;

      expect(received[0], 'welcome');
      expect(received[1], 'HOLA');
      expect(received[2], [1, 2, 3]);
      expect(handler.events.first, startsWith('open:ws-'));
      expect(handler.events, containsAll(['text:hola', 'binary:3']));
      expect(handler.lastCloseCode, 4001);
      expect(handler.lastCloseReason, 'bye');
    });

    test('per-connection factories run once per connection', () async {
      var created = 0;
      server.registerWebSocket('/ws/count', () {
        created++;
        return EchoHandler();
      });
      await server.serve(port: 0, quiet: true);

      final a =
          await WebSocket.connect('ws://127.0.0.1:${server.port}/ws/count');
      final b =
          await WebSocket.connect('ws://127.0.0.1:${server.port}/ws/count');
      await a.close();
      await b.close();
      expect(created, 2);
    });

    test('sessions expose path and query parameters', () async {
      server.registerWebSocket('/ws/rooms/:room', RoomHandler.new);
      await server.serve(port: 0, quiet: true);

      final client = await WebSocket.connect(
          'ws://127.0.0.1:${server.port}/ws/rooms/dart?user=ada');
      final first = await client.first;
      expect(first, 'room=dart user=ada');
      await client.close();
    });

    test('websocket and HTTP routes coexist', () async {
      server.register(
          HttpMethod.get, '/ping', (req) => const DianaResponse.text('pong'));
      server.registerWebSocket('/ws/echo', EchoHandler.new);
      await server.serve(port: 0, quiet: true);

      final http = HttpClient();
      final res = await (await http
              .getUrl(Uri.parse('http://127.0.0.1:${server.port}/ping')))
          .close();
      expect(res.statusCode, 200);
      await res.drain<void>();
      http.close();

      final client =
          await WebSocket.connect('ws://127.0.0.1:${server.port}/ws/echo');
      expect(await client.first, 'welcome');
      await client.close();
    });
  });
}
