import 'dart:async';

import 'package:diana/diana.dart';
import 'package:test/test.dart';

class BaseEvent {
  final String tag;
  const BaseEvent(this.tag);
}

class ChildEvent extends BaseEvent {
  const ChildEvent(super.tag);
}

class OtherEvent {
  const OtherEvent();
}

void main() {
  test('a listener registering another listener mid-dispatch is safe',
      () async {
    final bus = DianaEventBus();
    final seen = <String>[];
    bus.on<String>((e) {
      seen.add('first:$e');
      // Must not throw ConcurrentModificationError; the new listener joins
      // from the next publish.
      bus.on<String>((e2) => seen.add('second:$e2'));
    });
    await bus.publish('a');
    expect(seen, ['first:a']);
    seen.clear();
    await bus.publish('b');
    expect(seen, ['first:b', 'second:b']);
  });

  test('dispatches by subtype and skips unrelated listeners', () async {
    final bus = DianaEventBus();
    final base = <String>[];
    final child = <String>[];
    var others = 0;
    bus.on<BaseEvent>((e) => base.add(e.tag));
    bus.on<ChildEvent>((e) => child.add(e.tag));
    bus.on<OtherEvent>((e) => others++);

    await bus.publish(const ChildEvent('a'));
    expect(base, ['a'], reason: 'base-type listener receives subtypes');
    expect(child, ['a']);
    expect(others, 0);

    await bus.publish(const BaseEvent('b'));
    expect(base, ['a', 'b']);
    expect(child, ['a'], reason: 'child listener ignores the base type');
  });

  test('dispatches in registration order', () async {
    final bus = DianaEventBus();
    final order = <int>[];
    bus.on<BaseEvent>((e) => order.add(1));
    bus.on<BaseEvent>((e) => order.add(2));
    bus.on<BaseEvent>((e) => order.add(3));
    await bus.publish(const BaseEvent('x'));
    expect(order, [1, 2, 3]);
  });

  test('awaits async listeners before publish returns', () async {
    final bus = DianaEventBus();
    var done = false;
    bus.on<BaseEvent>((e) async {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      done = true;
    });
    await bus.publish(const BaseEvent('x'));
    expect(done, isTrue);
  });

  test('a listener error propagates and skips later listeners', () async {
    final bus = DianaEventBus();
    var reached = false;
    bus.on<BaseEvent>((e) => throw StateError('boom'));
    bus.on<BaseEvent>((e) => reached = true);
    await expectLater(
      bus.publish(const BaseEvent('x')),
      throwsA(isA<StateError>()),
    );
    expect(reached, isFalse);
  });

  test('broadcast calls the sink exactly once, before local dispatch',
      () async {
    final bus = DianaEventBus();
    final trace = <String>[];
    bus.remoteSink = (event) => trace.add('sink');
    bus.on<BaseEvent>((e) => trace.add('local'));
    await bus.broadcast(const BaseEvent('x'));
    expect(trace, ['sink', 'local']);
  });

  test('broadcast without a sink behaves like publish', () async {
    final bus = DianaEventBus();
    var count = 0;
    bus.on<BaseEvent>((e) => count++);
    await bus.broadcast(const BaseEvent('x'));
    expect(count, 1);
  });

  test('an unsendable broadcast fails fast with a clear message', () async {
    final bus = DianaEventBus();
    var delivered = false;
    bus.remoteSink = (event) => throw ArgumentError('not sendable');
    bus.on<BaseEvent>((e) => delivered = true);
    await expectLater(
      bus.broadcast(const BaseEvent('x')),
      throwsA(isA<ArgumentError>().having(
        (e) => e.message,
        'message',
        'Diana broadcast failed: event of type BaseEvent is not sendable '
            'across isolates. Broadcast events must be plain data (no '
            'ReceivePorts or other unsendable objects). '
            'See docs/guides/events.md.',
      )),
    );
    expect(delivered, isFalse, reason: 'local dispatch must not run');
  });

  test('dispatchRemote never relays and routes errors to onError', () async {
    final errors = <Object>[];
    final bus = DianaEventBus(onError: (e, st) => errors.add(e));
    var sinkCalls = 0;
    var reached = false;
    bus.remoteSink = (event) => sinkCalls++;
    bus.on<BaseEvent>((e) => throw StateError('boom'));
    bus.on<BaseEvent>((e) => reached = true);

    await bus.dispatchRemote(const BaseEvent('x'));
    expect(sinkCalls, 0, reason: 'remote events must not be re-broadcast');
    expect(errors, hasLength(1));
    expect(reached, isTrue,
        reason: 'remote dispatch continues past a failing listener');
  });
}
