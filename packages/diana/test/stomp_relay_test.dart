import 'dart:async';
import 'dart:isolate';

import 'package:diana/diana.dart';
import 'package:test/test.dart';

import 'stomp_broker_test.dart' show frame, feed, connected;

/// Wires two event buses so each one's broadcasts reach the other's local
/// listeners — the hub-and-spoke topology `DianaRuntime` builds at runtime.
(DianaEventBus, DianaEventBus) crossWired() {
  final a = DianaEventBus(onError: (_, __) {});
  final b = DianaEventBus(onError: (_, __) {});
  a.remoteSink = (event) => b.dispatchRemote(event);
  b.remoteSink = (event) => a.dispatchRemote(event);
  return (a, b);
}

void main() {
  test('a topic publish reaches subscribers on both isolates exactly once',
      () async {
    final (busA, busB) = crossWired();
    final brokerA =
        StompBroker(busA, const DianaConfig.empty(), onError: (_, __) {});
    final brokerB =
        StompBroker(busB, const DianaConfig.empty(), onError: (_, __) {});

    final a = await connected(brokerA, id: 'ws-a');
    final b = await connected(brokerB, id: 'ws-b');
    await feed(
        brokerA, a, frame('SUBSCRIBE', {'id': '0', 'destination': '/topic/x'}));
    await feed(
        brokerB, b, frame('SUBSCRIBE', {'id': '0', 'destination': '/topic/x'}));

    // Publish from A's broker; both local (A) and remote (B) subscribers get it.
    await brokerA.publish('/topic/x', 'hello');
    await Future<void>.delayed(Duration.zero);

    final aMsgs = a.frames.where((f) => f.command == 'MESSAGE').toList();
    final bMsgs = b.frames.where((f) => f.command == 'MESSAGE').toList();
    expect(aMsgs, hasLength(1), reason: 'local delivery exactly once');
    expect(bMsgs, hasLength(1), reason: 'remote delivery exactly once');
    expect(aMsgs.single.body, 'hello');
    expect(bMsgs.single.body, 'hello');
  });

  test('single-isolate (no remoteSink) delivers exactly once', () async {
    final bus = DianaEventBus(onError: (_, __) {});
    expect(bus.remoteSink, isNull);
    final broker =
        StompBroker(bus, const DianaConfig.empty(), onError: (_, __) {});
    final s = await connected(broker);
    await feed(broker, s, frame('SUBSCRIBE', {'id': '0', 'destination': '/t'}));
    await broker.publish('/t', 'x');
    await Future<void>.delayed(Duration.zero);
    expect(s.frames.where((f) => f.command == 'MESSAGE'), hasLength(1));
  });

  test('a broker built before a remote event arrives still receives it',
      () async {
    final bus = DianaEventBus(onError: (_, __) {});
    // Broker registers its bus.on<StompRelayEvent> listener in its ctor.
    final broker =
        StompBroker(bus, const DianaConfig.empty(), onError: (_, __) {});
    final s = await connected(broker);
    await feed(broker, s, frame('SUBSCRIBE', {'id': '0', 'destination': '/t'}));

    // Simulate an inbound remote event (as DianaRuntime would deliver it).
    await bus.dispatchRemote(const StompRelayEvent('/t', 'remote', {}));
    expect(s.frames.last.command, 'MESSAGE');
    expect(s.frames.last.body, 'remote');
  });

  test('StompRelayEvent is sendable across a real isolate', () async {
    final port = ReceivePort();
    await Isolate.spawn(_echoRelay, port.sendPort);
    final send = await port.first as SendPort;
    final reply = ReceivePort();
    send.send(
        (const StompRelayEvent('/t', 'body', {'k': 'v'}), reply.sendPort));
    final echoed = await reply.first as StompRelayEvent;
    expect(echoed.destination, '/t');
    expect(echoed.body, 'body');
    expect(echoed.headers, {'k': 'v'});
    reply.close();
  });
}

void _echoRelay(SendPort main) {
  final port = ReceivePort();
  main.send(port.sendPort);
  port.listen((message) {
    final (event, reply) = message as (StompRelayEvent, SendPort);
    reply.send(event);
    port.close();
  });
}
