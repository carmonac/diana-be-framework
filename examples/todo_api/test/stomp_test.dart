import 'dart:async';
import 'dart:io';

import 'package:diana/diana.dart';
import 'package:test/test.dart';
import 'package:todo_api/app.diana_app.dart';

/// Frames a STOMP message (LF EOLs, NUL terminator).
String frame(String command, Map<String, String> headers, [String body = '']) {
  final buffer = StringBuffer()..write(command)..write('\n');
  headers.forEach((k, v) => buffer.write('$k:$v\n'));
  buffer..write('\n')..write(body)..write('\x00');
  return buffer.toString();
}

void main() {
  late DianaServer server;
  late int port;

  setUpAll(() async {
    server = await buildDianaServer(config: const DianaConfig.empty());
    await server.serve(port: 0, quiet: true);
    port = server.port!;
  });
  tearDownAll(() => server.close());

  Future<WebSocket> connect() => WebSocket.connect(
        'ws://127.0.0.1:$port/stomp',
        headers: {'x-api-key': 'secret'},
      );

  /// Reads the next STOMP frame (skipping bare-EOL heartbeats).
  Future<StompFrame> nextFrame(StreamIterator<dynamic> it) async {
    while (await it.moveNext()) {
      final frames = parseStompText(it.current as String);
      if (frames.isNotEmpty) return frames.first;
    }
    throw StateError('stream closed');
  }

  test('connect, subscribe, send and receive a JSON round-trip', () async {
    final ws = await connect();
    final it = StreamIterator(ws);
    ws.add(frame('CONNECT', {'accept-version': '1.2', 'heart-beat': '0,0'}));
    expect((await nextFrame(it)).command, 'CONNECTED');

    ws.add(frame('SUBSCRIBE', {'id': '0', 'destination': '/topic/chat'}));
    ws.add(frame('SEND', {'destination': '/app/chat'}, '{"text":"hola"}'));

    final message = await nextFrame(it);
    expect(message.command, 'MESSAGE');
    expect(message.headers['destination'], '/topic/chat');
    expect(message.headers['subscription'], '0');
    // The mapping stamped the authenticated principal as `from`.
    expect(message.body, contains('"from":"key-holder"'));
    expect(message.body, contains('"text":"hola"'));

    await ws.close();
    await it.cancel();
  });

  test('a receipt header yields a RECEIPT', () async {
    final ws = await connect();
    final it = StreamIterator(ws);
    ws.add(frame('CONNECT', {'accept-version': '1.2'}));
    await nextFrame(it); // CONNECTED
    ws.add(frame('SUBSCRIBE',
        {'id': '0', 'destination': '/topic/chat', 'receipt': 'r1'}));
    final receipt = await nextFrame(it);
    expect(receipt.command, 'RECEIPT');
    expect(receipt.headers['receipt-id'], 'r1');
    await ws.close();
    await it.cancel();
  });

  test('a transaction commit delivers its buffered SEND', () async {
    final ws = await connect();
    final it = StreamIterator(ws);
    ws.add(frame('CONNECT', {'accept-version': '1.2'}));
    await nextFrame(it);
    ws.add(frame('SUBSCRIBE', {'id': '0', 'destination': '/topic/chat'}));
    ws.add(frame('BEGIN', {'transaction': 'tx1'}));
    ws.add(frame('SEND',
        {'destination': '/app/chat', 'transaction': 'tx1'}, '{"text":"tx"}'));
    ws.add(frame('COMMIT', {'transaction': 'tx1'}));
    final message = await nextFrame(it);
    expect(message.command, 'MESSAGE');
    expect(message.body, contains('"text":"tx"'));
    await ws.close();
    await it.cancel();
  });

  test('DISCONNECT with a receipt is acknowledged then the socket closes',
      () async {
    final ws = await connect();
    final it = StreamIterator(ws);
    ws.add(frame('CONNECT', {'accept-version': '1.2'}));
    await nextFrame(it);
    ws.add(frame('DISCONNECT', {'receipt': 'bye'}));
    final receipt = await nextFrame(it);
    expect(receipt.command, 'RECEIPT');
    expect(receipt.headers['receipt-id'], 'bye');
    await it.cancel();
    await ws.close();
  });

  test('an unsupported version is rejected with an ERROR frame', () async {
    final ws = await connect();
    final it = StreamIterator(ws);
    ws.add(frame('CONNECT', {'accept-version': '1.0'}));
    final error = await nextFrame(it);
    expect(error.command, 'ERROR');
    expect(error.headers['version'], '1.2');
    await it.cancel();
    await ws.close();
  });

  test('the handshake is rejected without the API key', () async {
    await expectLater(
      WebSocket.connect('ws://127.0.0.1:$port/stomp'),
      throwsA(isA<WebSocketException>()),
    );
  });
}
