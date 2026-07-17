# Aspects: @Timed, @Cacheable, @Retryable, @CircuitBreaker

Diana's aspect annotations wrap `@Service`/`@Component`/`@Repository`
methods with cross-cutting behaviour, Spring-AOP style — but resolved at
**compile time**: the generator emits a proxy subclass (`$Aspect$X`) whose
overrides nest tested runtime helpers around `super.method(...)`. No
reflection, no interceptor registry.

All four are **method-level** annotations on public instance methods
returning `Future`; the class must be open to extension (not
`final`/`base`/`sealed`). They compose freely with each other and with
[`@Transactional`](persistence.md).

```dart
@Service()
class Reports {
  Reports(this.db);
  final Database db;

  @Timed()
  @Cacheable(ttlSeconds: 30)
  @Retryable(maxAttempts: 3, backoffMs: 100, retryOn: [DbUnavailable])
  @CircuitBreaker(failureThreshold: 5, resetTimeoutMs: 30000)
  @Transactional()
  Future<List<Row>> summarize(int year) async { ... }
}
```

## Composition order (fixed)

Aspects always nest in the same order, outermost first:

**`@Timed` → `@Cacheable` → `@CircuitBreaker` → `@Retryable` →
`@Transactional`**

- **`@Timed` outermost** — measures the latency the *caller* experiences:
  cache hits, open-breaker rejections and full retry budgets all show up
  in the histogram.
- **`@Cacheable` second** — a hit short-circuits breaker, retry and
  transaction, and does not feed the breaker's failure count (a cache hit
  says nothing about downstream health).
- **`@CircuitBreaker` outside `@Retryable`** — one guarded invocation is
  one full retry budget: transient blips the retry absorbs never trip the
  breaker, and an open breaker rejects immediately instead of burning
  `maxAttempts × backoffMs` against a known-bad dependency (spring-retry's
  own semantics).
- **`@Transactional` innermost** — every retry attempt runs in a fresh
  transaction; a rolled-back attempt leaves no state behind.

## @Timed

Records `diana_method_duration_seconds{method}` and
`diana_method_calls_total{method,result}` (plus a `method.<name>` trace
span) through the app's [observability](observability.md) provider. The
label defaults to `ClassName.methodName`; override it with
`@Timed(name: 'reports.summary')`.

Without a `DianaObservability` provider the aspect is a **silent no-op**
(the proxy holds a `null` observer): adding observability later turns the
metrics on with no code change.

## @Cacheable

In-memory, per-isolate result cache keyed by the **argument list in
declaration order**. Entries expire after `ttlSeconds` (default 60) and the
least-recently-used entry is evicted beyond `maxEntries` (default 1024, per
method). Concurrent misses for the same key share one computation, and
**errors are never cached**.

Caveats:

- Arguments need **value equality** (`==`/`hashCode`) for hits to work —
  primitives and value-type DTOs do; plain mutable objects compare by
  identity (the same caveat Spring documents for key generation).
- The method must return `Future<T>` with a non-void `T`, and must not
  declare type parameters.
- By default the cache is per isolate: with `server.isolates > 1` each
  isolate warms its own copy (see [operations](operations.md)). Declare a
  [pluggable store](#pluggable-cache-store) to share one backend across
  isolates or processes.
- Writes elsewhere in the app are invisible through the cache until the
  TTL expires — cache reads that must see writes immediately are not a fit.

### Pluggable cache store

By default `@Cacheable` uses a built-in per-isolate cache. To share a
backend — Redis, memcached, a process-wide LRU — declare **exactly one**
provider extending `DianaCacheStore` and every cached method routes through
it instead:

```dart
@Component()
class RedisCacheStore extends DianaCacheStore {
  RedisCacheStore(this._client);
  final RedisClient _client;

  @override
  Future<V> run<V>(
      CacheSpec spec, List<Object?> key, Future<V> Function() miss) async {
    final cacheKey = '${spec.method}:${key.join('|')}'; // your key policy
    final cached = await _client.get(cacheKey);
    if (cached != null) return _decode<V>(cached);
    final value = await miss();               // a throw is never cached
    await _client.setex(cacheKey, spec.ttl.inSeconds, _encode(value));
    return value;
  }
}
```

The contract is **wrap-style**: the store owns the whole policy — lookup,
populate, single-flight, TTL and eviction. Diana hands it a `CacheSpec`
(`method` for namespacing, plus the annotation's `ttl`/`maxEntries`), the
argument list as `key`, and a `miss` thunk that computes the value. What
the store must own:

- **Key stringification** — `key` is the raw argument list; turn it into a
  cache key however your backend needs.
- **Serialization** — a distributed store round-trips values itself
  (`jsonEncode`/`jsonDecode`). Note the caveat: a JSON round-trip returns
  plain maps/lists, so if the method returns a DTO you must rebuild it
  (`Dto.fromJson(...)`) on the way out — the return type is still `V`.
- **Never cache errors** — run `miss` and let a throw propagate uncached,
  as the built-in default does.

`InMemoryCacheStore` is exported so a custom store can delegate to it
(logging, metrics, a local-then-remote tier). A `DianaCacheStore` provider
must be a singleton; declaring two is a build error. Without any store the
built-in per-proxy cache is used, byte-for-byte as before.

## @Retryable

Retries the method when it throws: `maxAttempts` total attempts (default
3), a fixed `backoffMs` delay between them (default 200), and an optional
`retryOn: [SomeException, ...]` allowlist (subtypes match; empty retries on
anything). The last error is rethrown untouched when attempts run out.

Combined with `@Transactional`, each attempt gets a **fresh transaction**
— a failed attempt rolls back cleanly before the next try.

## @CircuitBreaker

After `failureThreshold` consecutive failed invocations (default 5) the
circuit opens: calls throw `CircuitOpenException` immediately **without
invoking the method**. After `resetTimeoutMs` (default 30000) one
half-open trial call is allowed — success closes the circuit, failure
re-opens it. State is per method, per isolate.

`CircuitOpenException` surfaces as an opaque 500 by default; translate it
(e.g. into a 503) with a `@ControllerAdvice`:

```dart
@ControllerAdvice()
class Failures {
  @ExceptionHandler(CircuitOpenException)
  DianaResponse open(DianaRequest req, CircuitOpenException e) =>
      const DianaResponse.json(
          {'error': 'unavailable'}, statusCode: 503);
}
```

## How it compiles

One proxy subclass per class covers all its aspected methods. Classes
using **only** `@Transactional` keep the `$Tx$X` proxy; any new aspect
switches to `$Aspect$X`, with per-method state fields (`MethodCache`,
`RetryPolicy`, `CircuitBreakerPolicy` from `package:diana`) and one-liner
overrides — see [generated code](../reference/generated-code.md). Apps
using no aspects emit byte-identical output.
