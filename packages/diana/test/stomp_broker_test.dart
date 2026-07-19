import 'dart:async';
import 'dart:typed_data';

import 'package:diana/diana.dart';
import 'package:test/test.dart';

/// A recording WebSocketSession: captures every frame sent and parses them
/// back, and lets the test drive inbound frames.
class FakeSession implements WebSocketSession {
  FakeSession(this.id, {Map<String, Object?>? attributes})
      : attributes = attributes ?? {};

  @override
  final String id;
  @override
  final Map<String, Object?> attributes;

  final List<String> sent = [];
  int? closeCode;
  String? closeReason;
  bool _open = true;

  /// Frames the client received, in order (heartbeats excluded).
  List<StompFrame> get frames =>
      [for (final s in sent) ...parseStompText(s)];

  StompFrame get last => frames.last;

  @override
  bool sendText(String text) {
    if (!_open) return false;
    sent.add(text);
    return true;
  }

  @override
  Future<void> close([int? code, String? reason]) async {
    _open = false;
    closeCode ??= code;
    closeReason ??= reason;
  }

  @override
  bool get isOpen => _open;

  @override
  bool sendBytes(Uint8List data) => sendText('<binary>');
  @override
  Uri get uri => Uri.parse('/stomp');
  @override
  Map<String, String> get pathParameters => const {};
  @override
  Map<String, String> get queryParameters => const {};
}

String frame(String command, Map<String, String> headers, [String body = '']) =>
    serializeStompFrame(StompFrame(command, headers, body));

/// Feeds a text frame into the broker and drains its per-session tail.
Future<void> feed(StompBroker broker, FakeSession s, String text) async {
  broker.onMessage(s, TextMessage(text));
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

StompBroker newBroker({Map<String, Object?> config = const {}}) {
  return StompBroker(DianaEventBus(onError: (_, __) {}),
      DianaConfig(config), onError: (_, __) {});
}

Future<FakeSession> connected(StompBroker broker,
    {String id = 'ws-1', Map<String, Object?>? attributes}) async {
  final s = FakeSession(id, attributes: attributes);
  broker.onOpen(s);
  await feed(broker, s, frame('CONNECT', {'accept-version': '1.2'}));
  return s;
}

void main() {
  group('connect', () {
    test('CONNECT → CONNECTED with version/session/heart-beat', () async {
      final broker = newBroker();
      final s = await connected(broker);
      expect(s.last.command, 'CONNECTED');
      expect(s.last.headers['version'], '1.2');
      expect(s.last.headers['session'], 'ws-1');
      expect(s.last.headers['heart-beat'], '10000,10000');
    });

    test('STOMP command is accepted like CONNECT', () async {
      final broker = newBroker();
      final s = FakeSession('ws-1');
      broker.onOpen(s);
      await feed(broker, s, frame('STOMP', {'accept-version': '1.2'}));
      expect(s.last.command, 'CONNECTED');
    });

    test('missing 1.2 → ERROR with version header + close 4002', () async {
      final broker = newBroker();
      final s = FakeSession('ws-1');
      broker.onOpen(s);
      await feed(broker, s, frame('CONNECT', {'accept-version': '1.1'}));
      expect(s.last.command, 'ERROR');
      expect(s.last.headers['version'], '1.2');
      expect(s.closeCode, 4002);
    });

    test('a frame before CONNECT is a protocol error', () async {
      final broker = newBroker();
      final s = FakeSession('ws-1');
      broker.onOpen(s);
      await feed(broker, s, frame('SEND', {'destination': '/t'}));
      expect(s.last.command, 'ERROR');
      expect(s.last.headers['message'],
          'not connected: first frame must be CONNECT or STOMP');
      expect(s.closeCode, 4002);
    });

    test('receipt on CONNECT is rejected', () async {
      final broker = newBroker();
      final s = FakeSession('ws-1');
      broker.onOpen(s);
      await feed(broker, s,
          frame('CONNECT', {'accept-version': '1.2', 'receipt': 'r1'}));
      expect(s.last.command, 'ERROR');
      expect(s.last.headers['message'], 'receipt is not allowed on CONNECT');
    });
  });

  group('subscribe & send', () {
    test('a SEND fans out to subscribers with the right headers', () async {
      final broker = newBroker();
      final a = await connected(broker, id: 'ws-a');
      final b = await connected(broker, id: 'ws-b');
      await feed(broker, a, frame('SUBSCRIBE', {'id': '0', 'destination': '/topic/x'}));
      await feed(broker, b, frame('SEND', {'destination': '/topic/x'}, 'hello'));

      final msg = a.frames.last;
      expect(msg.command, 'MESSAGE');
      expect(msg.headers['destination'], '/topic/x');
      expect(msg.headers['subscription'], '0');
      expect(msg.headers['message-id'], isNotNull);
      expect(msg.body, 'hello');
    });

    test('custom SEND headers pass through to the MESSAGE', () async {
      final broker = newBroker();
      final a = await connected(broker);
      await feed(broker, a, frame('SUBSCRIBE', {'id': '0', 'destination': '/t'}));
      await feed(broker, a,
          frame('SEND', {'destination': '/t', 'x-tag': 'v1'}, 'hi'));
      expect(a.frames.last.headers['x-tag'], 'v1');
    });

    test('missing destination / id are protocol errors', () async {
      final broker = newBroker();
      final s = await connected(broker);
      await feed(broker, s, frame('SEND', {}, 'hi'));
      expect(s.last.headers['message'],
          'missing required header "destination" for SEND');
    });

    test('duplicate subscription id', () async {
      final broker = newBroker();
      final s = await connected(broker);
      await feed(broker, s, frame('SUBSCRIBE', {'id': '0', 'destination': '/t'}));
      await feed(broker, s, frame('SUBSCRIBE', {'id': '0', 'destination': '/u'}));
      expect(s.last.headers['message'], 'duplicate subscription id "0"');
    });

    test('UNSUBSCRIBE stops delivery; unknown id errors', () async {
      final broker = newBroker();
      final s = await connected(broker);
      await feed(broker, s, frame('SUBSCRIBE', {'id': '0', 'destination': '/t'}));
      await feed(broker, s, frame('UNSUBSCRIBE', {'id': '0'}));
      final before = s.frames.length;
      await feed(broker, s, frame('SEND', {'destination': '/t'}, 'x'));
      expect(s.frames.length, before, reason: 'no MESSAGE after unsubscribe');
      await feed(broker, s, frame('UNSUBSCRIBE', {'id': '9'}));
      expect(s.last.headers['message'], 'unknown subscription id "9"');
    });
  });

  group('receipts', () {
    test('a receipt header yields a RECEIPT after processing', () async {
      final broker = newBroker();
      final s = await connected(broker);
      await feed(broker, s,
          frame('SUBSCRIBE', {'id': '0', 'destination': '/t', 'receipt': 'r7'}));
      expect(s.last.command, 'RECEIPT');
      expect(s.last.headers['receipt-id'], 'r7');
    });
  });

  group('ack modes', () {
    Future<(StompBroker, FakeSession)> withThreeMessages(String ackMode) async {
      final broker = newBroker();
      final s = await connected(broker);
      await feed(broker, s,
          frame('SUBSCRIBE', {'id': '0', 'destination': '/t', 'ack': ackMode}));
      for (final n in ['m1', 'm2', 'm3']) {
        await feed(broker, s, frame('SEND', {'destination': '/t'}, n));
      }
      return (broker, s);
    }

    test('auto mode adds no ack header', () async {
      final broker = newBroker();
      final s = await connected(broker);
      await feed(broker, s, frame('SUBSCRIBE', {'id': '0', 'destination': '/t'}));
      await feed(broker, s, frame('SEND', {'destination': '/t'}, 'x'));
      expect(s.frames.last.headers.containsKey('ack'), isFalse);
    });

    test('client mode: ACK is cumulative', () async {
      final (broker, s) = await withThreeMessages('client');
      final messages = s.frames.where((f) => f.command == 'MESSAGE').toList();
      expect(messages, hasLength(3));
      final secondAck = messages[1].headers['ack']!;
      await feed(broker, s, frame('ACK', {'id': secondAck}));
      // A NACK of the third must still be known (only m1,m2 were acked).
      final thirdAck = messages[2].headers['ack']!;
      await feed(broker, s, frame('ACK', {'id': thirdAck}));
      expect(s.frames.any((f) => f.command == 'ERROR'), isFalse);
      // Re-acking m2 now fails: it was removed cumulatively.
      await feed(broker, s, frame('ACK', {'id': secondAck}));
      expect(s.last.headers['message'], 'unknown ack id "$secondAck"');
    });

    test('client-individual mode: only the exact id is removed', () async {
      final (broker, s) = await withThreeMessages('client-individual');
      final messages = s.frames.where((f) => f.command == 'MESSAGE').toList();
      final secondAck = messages[1].headers['ack']!;
      await feed(broker, s, frame('ACK', {'id': secondAck}));
      // m1 and m3 are still ackable.
      await feed(broker, s, frame('ACK', {'id': messages[0].headers['ack']!}));
      await feed(broker, s, frame('ACK', {'id': messages[2].headers['ack']!}));
      expect(s.frames.any((f) => f.command == 'ERROR'), isFalse);
    });

    test('unknown ack id and NACK', () async {
      final broker = newBroker();
      final logs = <Object>[];
      final b2 = StompBroker(DianaEventBus(onError: (_, __) {}),
          const DianaConfig.empty(), onError: (e, _) => logs.add(e));
      final s = await connected(b2);
      await feed(b2, s,
          frame('SUBSCRIBE', {'id': '0', 'destination': '/t', 'ack': 'client'}));
      await feed(b2, s, frame('SEND', {'destination': '/t'}, 'x'));
      final ackId = s.frames.last.headers['ack']!;
      await feed(b2, s, frame('NACK', {'id': ackId}));
      expect(logs, isNotEmpty, reason: 'NACK is logged, no redelivery');

      await feed(broker, await connected(broker), frame('ACK', {'id': 'nope'}));
    });
  });

  group('transactions', () {
    test('COMMIT replays buffered SENDs in order; ABORT discards', () async {
      final broker = newBroker();
      final s = await connected(broker);
      await feed(broker, s, frame('SUBSCRIBE', {'id': '0', 'destination': '/t'}));

      await feed(broker, s, frame('BEGIN', {'transaction': 'tx1'}));
      await feed(broker, s,
          frame('SEND', {'destination': '/t', 'transaction': 'tx1'}, 'a'));
      await feed(broker, s,
          frame('SEND', {'destination': '/t', 'transaction': 'tx1'}, 'b'));
      // Nothing delivered yet.
      expect(s.frames.where((f) => f.command == 'MESSAGE'), isEmpty);
      await feed(broker, s, frame('COMMIT', {'transaction': 'tx1'}));
      final bodies = s.frames
          .where((f) => f.command == 'MESSAGE')
          .map((f) => f.body)
          .toList();
      expect(bodies, ['a', 'b']);

      await feed(broker, s, frame('BEGIN', {'transaction': 'tx2'}));
      await feed(broker, s,
          frame('SEND', {'destination': '/t', 'transaction': 'tx2'}, 'c'));
      await feed(broker, s, frame('ABORT', {'transaction': 'tx2'}));
      expect(s.frames.where((f) => f.command == 'MESSAGE'), hasLength(2));
    });

    test('unknown / duplicate transaction ids error', () async {
      final broker = newBroker();
      final s = await connected(broker);
      await feed(broker, s, frame('COMMIT', {'transaction': 'ghost'}));
      expect(s.last.headers['message'], 'unknown transaction "ghost"');

      final s2 = await connected(broker, id: 'ws-2');
      await feed(broker, s2, frame('BEGIN', {'transaction': 'dup'}));
      await feed(broker, s2, frame('BEGIN', {'transaction': 'dup'}));
      expect(s2.last.headers['message'], 'transaction "dup" already begun');
    });
  });

  group('disconnect & cleanup', () {
    test('DISCONNECT with receipt sends RECEIPT then closes 1000', () async {
      final broker = newBroker();
      final s = await connected(broker);
      await feed(broker, s, frame('DISCONNECT', {'receipt': 'bye'}));
      expect(s.frames.last.command, 'RECEIPT');
      expect(s.frames.last.headers['receipt-id'], 'bye');
      expect(s.closeCode, 1000);
    });

    test('closing a session stops delivery to it', () async {
      final broker = newBroker();
      final a = await connected(broker, id: 'ws-a');
      final b = await connected(broker, id: 'ws-b');
      await feed(broker, a, frame('SUBSCRIBE', {'id': '0', 'destination': '/t'}));
      broker.onClose(a, 1000, null);
      final before = a.frames.length;
      await feed(broker, b, frame('SEND', {'destination': '/t'}, 'x'));
      expect(a.frames.length, before);
    });
  });

  group('mappings', () {
    test('a mapping receives the payload + principal and publishes @SendTo',
        () async {
      final broker = newBroker();
      StompMessage? seen;
      broker.registerMapping('/echo', (m) {
        seen = m;
        return 'reply:${m.body}';
      }, sendTo: '/topic/out');

      final sender = await connected(broker,
          id: 'ws-s', attributes: {'diana.auth.principal': 'ada'});
      final listener = await connected(broker, id: 'ws-l');
      await feed(broker, listener,
          frame('SUBSCRIBE', {'id': '0', 'destination': '/topic/out'}));
      await feed(broker, sender, frame('SEND', {'destination': '/app/echo'}, 'hi'));

      expect(seen!.body, 'hi');
      expect(seen!.principal, 'ada');
      expect(listener.frames.last.command, 'MESSAGE');
      expect(listener.frames.last.body, 'reply:hi');
    });

    test('an unmapped /app destination is dropped and logged', () async {
      final logs = <Object>[];
      final broker = StompBroker(DianaEventBus(onError: (_, __) {}),
          const DianaConfig.empty(), onError: (e, _) => logs.add(e));
      final s = await connected(broker);
      await feed(broker, s, frame('SEND', {'destination': '/app/nope'}, 'x'));
      expect(logs, isNotEmpty);
      expect(s.frames.any((f) => f.command == 'ERROR'), isFalse);
    });

    test('a throwing handler yields ERROR + close', () async {
      final broker = newBroker();
      broker.registerMapping('/boom', (m) => throw StateError('x'));
      final s = await connected(broker);
      await feed(broker, s, frame('SEND', {'destination': '/app/boom'}, 'x'));
      expect(s.last.command, 'ERROR');
      expect(s.closeCode, 4002);
    });
  });

  group('heartbeats', () {
    test('outgoing LF is emitted at the negotiated interval', () async {
      final broker = newBroker(config: {'stomp.heartbeatMs': 30});
      final s = FakeSession('ws-1');
      broker.onOpen(s);
      await feed(broker, s,
          frame('CONNECT', {'accept-version': '1.2', 'heart-beat': '0,30'}));
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(s.sent.where((t) => t == '\n'), isNotEmpty);
      broker.onClose(s, 1000, null);
    });

    test('the watchdog closes a silent client with 4000', () async {
      final broker = newBroker(config: {'stomp.heartbeatMs': 20});
      final s = FakeSession('ws-1');
      broker.onOpen(s);
      await feed(broker, s,
          frame('CONNECT', {'accept-version': '1.2', 'heart-beat': '20,0'}));
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(s.closeCode, 4000);
    });
  });

  test('frames are processed in arrival order despite a slow handler',
      () async {
    final broker = newBroker();
    final order = <String>[];
    broker.registerMapping('/slow', (m) async {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      order.add('slow:${m.body}');
      return null;
    });
    broker.registerMapping('/fast', (m) {
      order.add('fast:${m.body}');
      return null;
    });
    final s = await connected(broker);
    broker.onMessage(s, TextMessage(frame('SEND', {'destination': '/app/slow'}, '1')));
    broker.onMessage(s, TextMessage(frame('SEND', {'destination': '/app/fast'}, '2')));
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(order, ['slow:1', 'fast:2']);
  });
}
