import 'package:diana_generator/src/model/summary.dart';
import 'package:test/test.dart';

const _string = TypeRef(name: 'String', libraryUri: 'dart:core');
const _future =
    TypeRef(name: 'Future', libraryUri: 'dart:async', typeArgs: [_string]);

void main() {
  test('AspectMethodInfo round-trips with every aspect populated', () {
    const info = AspectMethodInfo(
      methodName: 'lookup',
      returnType: _future,
      typeParams: [TypeParamInfo(name: 'T', bound: _string)],
      params: [
        AspectParamInfo(
            name: 'id', type: _string, kind: 'requiredPositional'),
        AspectParamInfo(
            name: 'limit',
            type: _string,
            kind: 'named',
            required: true,
            defaultCode: null),
      ],
      transactional: true,
      timed: TimedInfo(name: 'custom'),
      cacheable: CacheableInfo(ttlSeconds: 30, maxEntries: 16),
      retryable:
          RetryableInfo(maxAttempts: 5, backoffMs: 50, retryOn: [_string]),
      circuitBreaker:
          CircuitBreakerInfo(failureThreshold: 2, resetTimeoutMs: 1000),
    );

    final back = AspectMethodInfo.fromJson(info.toJson());
    expect(back.methodName, 'lookup');
    expect(back.typeParams.single.name, 'T');
    expect(back.typeParams.single.bound!.name, 'String');
    expect(back.params, hasLength(2));
    expect(back.params.last.required, isTrue);
    expect(back.transactional, isTrue);
    expect(back.timed!.name, 'custom');
    expect(back.cacheable!.ttlSeconds, 30);
    expect(back.cacheable!.maxEntries, 16);
    expect(back.retryable!.maxAttempts, 5);
    expect(back.retryable!.backoffMs, 50);
    expect(back.retryable!.retryOn.single.name, 'String');
    expect(back.circuitBreaker!.failureThreshold, 2);
    expect(back.circuitBreaker!.resetTimeoutMs, 1000);
  });

  test('defaults are omitted from JSON and restored on read', () {
    const info = AspectMethodInfo(
      methodName: 'm',
      returnType: _future,
      transactional: true,
    );
    final json = info.toJson();
    expect(json.keys, unorderedEquals(['method', 'returnType', 'tx']));

    const specs = AspectMethodInfo(
      methodName: 'm',
      returnType: _future,
      timed: TimedInfo(),
      cacheable: CacheableInfo(),
      retryable: RetryableInfo(),
      circuitBreaker: CircuitBreakerInfo(),
    );
    final specsJson = specs.toJson();
    // Default-valued specs serialize as empty maps (presence = enabled).
    expect(specsJson['timed'], isEmpty);
    expect(specsJson['cacheable'], isEmpty);
    expect(specsJson.containsKey('tx'), isFalse);
    final back = AspectMethodInfo.fromJson(specsJson);
    expect(back.cacheable!.ttlSeconds, 60);
    expect(back.retryable!.maxAttempts, 3);
    expect(back.circuitBreaker!.failureThreshold, 5);
    expect(back.transactional, isFalse);
  });
}
