import 'dart:async';

import 'package:diana/diana.dart';
import 'package:test/test.dart';

class _Recorder extends DianaObserver {
  final List<String> timed = [];

  @override
  FutureOr<T> observeTimedMethod<T>(String name, FutureOr<T> Function() run) {
    timed.add(name);
    return run();
  }
}

void main() {
  group('MethodCache', () {
    test('hits within the TTL, expires after it', () async {
      final cache = MethodCache<int>(
          ttl: const Duration(milliseconds: 80), maxEntries: 8);
      var computed = 0;
      Future<int> miss() async => ++computed;

      expect(await cache.run([1], miss), 1);
      expect(await cache.run([1], miss), 1, reason: 'hit within TTL');
      expect(computed, 1);

      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(await cache.run([1], miss), 2, reason: 'expired → recompute');
    });

    test('keys compare element-wise', () async {
      final cache =
          MethodCache<String>(ttl: const Duration(seconds: 5), maxEntries: 8);
      expect(await cache.run([1, 'a'], () async => 'first'), 'first');
      expect(await cache.run([1, 'b'], () async => 'second'), 'second');
      expect(await cache.run([1, 'a'], () async => 'MISS'), 'first');
      expect(await cache.run([1], () async => 'shorter'), 'shorter');
    });

    test('evicts least-recently-used beyond maxEntries', () async {
      final cache =
          MethodCache<int>(ttl: const Duration(seconds: 5), maxEntries: 2);
      var computed = 0;
      Future<int> miss() async => ++computed;

      await cache.run(['a'], miss); // 1
      await cache.run(['b'], miss); // 2
      await cache.run(['a'], miss); // hit → 'a' most recent
      await cache.run(['c'], miss); // 3, evicts 'b'
      expect(await cache.run(['a'], miss), 1, reason: "'a' survived");
      expect(await cache.run(['b'], miss), 4, reason: "'b' was evicted");
    });

    test('concurrent misses share one computation (single-flight)', () async {
      final cache =
          MethodCache<int>(ttl: const Duration(seconds: 5), maxEntries: 8);
      var computed = 0;
      Future<int> slowMiss() async {
        computed++;
        await Future<void>.delayed(const Duration(milliseconds: 40));
        return computed;
      }

      final results = await Future.wait(
          [cache.run([1], slowMiss), cache.run([1], slowMiss)]);
      expect(results, [1, 1]);
      expect(computed, 1);
    });

    test('errors are never cached', () async {
      final cache =
          MethodCache<int>(ttl: const Duration(seconds: 5), maxEntries: 8);
      var calls = 0;
      Future<int> flaky() async {
        calls++;
        if (calls == 1) throw StateError('boom');
        return calls;
      }

      await expectLater(cache.run([1], flaky), throwsStateError);
      expect(await cache.run([1], flaky), 2, reason: 'error was evicted');
      expect(await cache.run([1], flaky), 2, reason: 'success is cached');
    });

    test('clear() drops everything', () async {
      final cache =
          MethodCache<int>(ttl: const Duration(seconds: 5), maxEntries: 8);
      var computed = 0;
      Future<int> miss() async => ++computed;
      await cache.run([1], miss);
      cache.clear();
      expect(await cache.run([1], miss), 2);
    });
  });

  group('InMemoryCacheStore (pluggable default)', () {
    const specA = CacheSpec(
        method: 'Svc.a', ttl: Duration(seconds: 5), maxEntries: 8);
    const specB = CacheSpec(
        method: 'Svc.b', ttl: Duration(seconds: 5), maxEntries: 8);

    test('keeps MethodCache semantics: hit, error never cached', () async {
      final store = InMemoryCacheStore();
      var computed = 0;
      Future<int> miss() async => ++computed;

      expect(await store.run(specA, [1], miss), 1);
      expect(await store.run(specA, [1], miss), 1, reason: 'hit');
      expect(computed, 1);

      var calls = 0;
      Future<int> flaky() async {
        calls++;
        if (calls == 1) throw StateError('boom');
        return calls;
      }

      await expectLater(store.run(specA, [9], flaky), throwsStateError);
      expect(await store.run(specA, [9], flaky), 2,
          reason: 'the error was not cached');
    });

    test('namespaces by spec.method: same key, different methods', () async {
      final store = InMemoryCacheStore();
      expect(await store.run(specA, [1], () async => 'from-a'), 'from-a');
      expect(await store.run(specB, [1], () async => 'from-b'), 'from-b',
          reason: 'no cross-method collision for the same key');
      expect(await store.run(specA, [1], () async => 'MISS'), 'from-a');
    });

    test('expires by the spec TTL', () async {
      const shortLived = CacheSpec(
          method: 'Svc.short',
          ttl: Duration(milliseconds: 60),
          maxEntries: 8);
      final store = InMemoryCacheStore();
      var computed = 0;
      Future<int> miss() async => ++computed;
      expect(await store.run(shortLived, [1], miss), 1);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(await store.run(shortLived, [1], miss), 2);
    });

    test('clear() empties every method cache', () async {
      final store = InMemoryCacheStore();
      var computed = 0;
      Future<int> miss() async => ++computed;
      await store.run(specA, [1], miss);
      await store.run(specB, [1], miss);
      store.clear();
      expect(await store.run(specA, [1], miss), 3);
      expect(await store.run(specB, [1], miss), 4);
    });

    test('the generic value type survives the store round-trip', () async {
      final store = InMemoryCacheStore();
      final first = await store.run(specA, [1], () async => <String>['x']);
      expect(first, isA<List<String>>());
      final hit = await store.run(specA, [1], () async => <String>['y']);
      expect(hit, ['x']);
    });
  });

  group('RetryPolicy', () {
    test('succeeds after transient failures', () async {
      const policy =
          RetryPolicy(maxAttempts: 3, backoff: Duration(milliseconds: 5));
      var calls = 0;
      final result = await policy.run(() async {
        calls++;
        if (calls < 3) throw StateError('transient');
        return 'ok';
      });
      expect(result, 'ok');
      expect(calls, 3);
    });

    test('exhausts attempts and rethrows the last error', () async {
      const policy = RetryPolicy(maxAttempts: 2, backoff: Duration.zero);
      var calls = 0;
      await expectLater(
        policy.run<void>(() async {
          calls++;
          throw StateError('always $calls');
        }),
        throwsA(isA<StateError>()
            .having((e) => e.message, 'message', 'always 2')),
      );
      expect(calls, 2);
    });

    test('retryWhen filter passes non-matching errors straight through',
        () async {
      final policy = RetryPolicy(
          maxAttempts: 3,
          backoff: Duration.zero,
          retryWhen: (e) => e is TimeoutException);
      var calls = 0;
      await expectLater(
        policy.run<void>(() async {
          calls++;
          throw StateError('not retryable');
        }),
        throwsStateError,
      );
      expect(calls, 1);
    });

    test('applies the backoff between attempts', () async {
      const policy =
          RetryPolicy(maxAttempts: 3, backoff: Duration(milliseconds: 40));
      final sw = Stopwatch()..start();
      await expectLater(
          policy.run<void>(() async => throw StateError('x')),
          throwsStateError);
      expect(sw.elapsedMilliseconds, greaterThanOrEqualTo(70),
          reason: 'two backoffs of 40ms must elapse');
    });

    test('maxAttempts: 1 never retries', () async {
      const policy = RetryPolicy(maxAttempts: 1, backoff: Duration.zero);
      var calls = 0;
      await expectLater(
          policy.run<void>(() async {
            calls++;
            throw StateError('x');
          }),
          throwsStateError);
      expect(calls, 1);
    });
  });

  group('CircuitBreakerPolicy', () {
    test('opens at the threshold and rejects without invoking', () async {
      final breaker = CircuitBreakerPolicy(
          failureThreshold: 2, resetTimeout: const Duration(seconds: 5));
      var calls = 0;
      Future<void> failing() {
        calls++;
        throw StateError('down');
      }

      await expectLater(breaker.run(failing), throwsStateError);
      await expectLater(breaker.run(failing), throwsStateError);
      await expectLater(
          breaker.run(failing), throwsA(isA<CircuitOpenException>()));
      expect(calls, 2, reason: 'the open circuit must not invoke the call');
    });

    test('a success resets the consecutive-failure count', () async {
      final breaker = CircuitBreakerPolicy(
          failureThreshold: 2, resetTimeout: const Duration(seconds: 5));
      await expectLater(
          breaker.run(() async => throw StateError('x')), throwsStateError);
      await breaker.run(() async {});
      await expectLater(
          breaker.run(() async => throw StateError('x')), throwsStateError);
      // Still closed: the earlier failure no longer counts.
      await breaker.run(() async {});
    });

    test('half-open trial success closes the circuit', () async {
      final breaker = CircuitBreakerPolicy(
          failureThreshold: 1,
          resetTimeout: const Duration(milliseconds: 50));
      await expectLater(
          breaker.run(() async => throw StateError('x')), throwsStateError);
      await expectLater(
          breaker.run(() async {}), throwsA(isA<CircuitOpenException>()));

      await Future<void>.delayed(const Duration(milliseconds: 80));
      await breaker.run(() async {}); // half-open trial succeeds
      await breaker.run(() async {}); // closed again
    });

    test('half-open trial failure re-opens the circuit', () async {
      final breaker = CircuitBreakerPolicy(
          failureThreshold: 1,
          resetTimeout: const Duration(milliseconds: 50));
      await expectLater(
          breaker.run(() async => throw StateError('x')), throwsStateError);
      await Future<void>.delayed(const Duration(milliseconds: 80));
      await expectLater(
          breaker.run(() async => throw StateError('still down')),
          throwsStateError);
      await expectLater(
          breaker.run(() async {}), throwsA(isA<CircuitOpenException>()));
    });
  });

  group('runTimed', () {
    test('a null observer is a passthrough', () async {
      expect(await runTimed(null, 'X.m', () async => 42), 42);
    });

    test('the observer receives the name and controls execution', () async {
      final recorder = _Recorder();
      expect(await runTimed(recorder, 'X.m', () async => 'v'), 'v');
      expect(recorder.timed, ['X.m']);
    });

    test('the default observer hook is a transparent no-op', () async {
      final observer = _NoOp();
      expect(await runTimed(observer, 'X.m', () async => 7), 7);
      await expectLater(
        runTimed<void>(observer, 'X.m', () async => throw StateError('e')),
        throwsStateError,
      );
    });
  });
}

class _NoOp extends DianaObserver {}
