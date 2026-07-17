import 'package:diana/diana.dart';

/// A pluggable `@Cacheable` backend. Diana discovers this provider by
/// supertype and routes every `@Cacheable` method through it instead of the
/// built-in per-proxy cache.
///
/// This example just counts invocations and delegates to the in-memory
/// default; a real deployment would talk to Redis/memcached here, owning the
/// key stringification and value (de)serialization.
@Component()
class AppCacheStore extends DianaCacheStore {
  final InMemoryCacheStore _delegate = InMemoryCacheStore();

  /// How many times the store was consulted (test observability).
  int runs = 0;

  @override
  Future<V> run<V>(
      CacheSpec spec, List<Object?> key, Future<V> Function() miss) {
    runs++;
    return _delegate.run(spec, key, miss);
  }

  @override
  void clear() => _delegate.clear();
}
