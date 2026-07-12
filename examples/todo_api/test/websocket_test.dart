import 'dart:async';
import 'dart:io';

import 'package:diana/diana.dart';
import 'package:test/test.dart';
import 'package:todo_api/app.diana_app.dart';

void main() {
  late DianaServer server;
  late int port;

  setUpAll(() async {
    server = await buildDianaServer(config: const DianaConfig.empty());
    await server.serve(port: 0, quiet: true);
    port = server.port!;
  });

  tearDownAll(() => server.close());

  Future<WebSocket> join(String room) => WebSocket.connect(
        'ws://127.0.0.1:$port/ws/chat/$room',
        headers: {'x-api-key': 'secret'},
      );

  test('chat broadcasts within a room but not across rooms', () async {
    final alice = await join('dart');
    final bob = await join('dart');
    final eve = await join('java');

    final aliceMsgs = StreamQueue(alice);
    final bobMsgs = StreamQueue(bob);
    final eveMsgs = StreamQueue(eve);

    expect(await aliceMsgs.next, 'joined dart as key-holder');
    expect(await bobMsgs.next, 'joined dart as key-holder');
    expect(await eveMsgs.next, 'joined java as key-holder');

    alice.add('hello!');
    expect(await aliceMsgs.next, '[dart] hello!');
    expect(await bobMsgs.next, '[dart] hello!');

    eve.add('anyone here?');
    expect(await eveMsgs.next, '[java] anyone here?');

    await alice.close();
    await bob.close();
    await eve.close();
  });

  test('handshake middleware blocks upgrades without the API key',
      () async {
    await expectLater(
      WebSocket.connect('ws://127.0.0.1:$port/ws/chat/dart'),
      throwsA(isA<WebSocketException>()),
    );
  });

  test('closed peers are removed from the room', () async {
    final a = await join('flutter');
    final aMsgs = StreamQueue(a);
    expect(await aMsgs.next, 'joined flutter as key-holder');
    await a.close();
    // Give the server a beat to process the close.
    await Future<void>.delayed(const Duration(milliseconds: 100));

    final b = await join('flutter');
    final bMsgs = StreamQueue(b);
    expect(await bMsgs.next, 'joined flutter as key-holder');
    b.add('ping');
    expect(await bMsgs.next, '[flutter] ping');
    await b.close();
  });
}

/// Tiny sequential reader over a broadcast-unfriendly stream.
class StreamQueue {
  final Stream<dynamic> _stream;
  late final StreamIterator<dynamic> _iterator =
      StreamIterator<dynamic>(_stream);

  StreamQueue(this._stream);

  Future<dynamic> get next async {
    final has = await _iterator.moveNext();
    if (!has) throw StateError('stream closed');
    return _iterator.current;
  }
}
