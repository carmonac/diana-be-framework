/// Runtime support for the generated aspect proxies (`$Aspect$X`): timing,
/// caching, retry and circuit breaking. The semantics live here, tested
/// once — generated code is a thin nest of one-liner calls, composed in the
/// fixed order Timed → Cacheable → CircuitBreaker → Retryable →
/// Transactional (outermost first).
library;

import 'dart:async';

import 'observer.dart';

/// `@Timed` glue: with no observer the call is a zero-cost passthrough
/// (`@Timed` is a silent no-op without an observability provider).
Future<T> runTimed<T>(
  DianaObserver? observer,
  String name,
  Future<T> Function() run,
) =>
    observer == null
        ? run()
        : Future.sync(() => observer.observeTimedMethod(name, run));

/// Per-method TTL + LRU cache, per isolate (`@Cacheable`).
///
/// Stores the in-flight [Future] so concurrent misses for the same key
/// share one computation (single-flight); a failed future is evicted as
/// soon as it fails — errors are never cached. Keys are argument lists
/// compared element-wise, so arguments need value equality (`==`/
/// `hashCode`) for hits to work.
class MethodCache<V> {
  final Duration ttl;
  final int maxEntries;

  /// Map literals iterate in insertion order; re-inserting on access makes
  /// the first key the least recently used.
  final Map<_CacheKey, _CacheEntry<V>> _entries = {};

  MethodCache({required this.ttl, required this.maxEntries});

  /// Returns the cached future for [key], or runs [miss] and caches it.
  Future<V> run(List<Object?> key, Future<V> Function() miss) {
    final cacheKey = _CacheKey(key);
    final now = DateTime.now();
    final hit = _entries.remove(cacheKey);
    if (hit != null && now.isBefore(hit.expiresAt)) {
      _entries[cacheKey] = hit; // re-insert: most recently used
      return hit.value;
    }
    final value = miss();
    _entries[cacheKey] = _CacheEntry(value, now.add(ttl));
    unawaited(value.then((_) {}, onError: (Object _) {
      // Evict only if this exact future is still the cached one.
      final current = _entries[cacheKey];
      if (current != null && identical(current.value, value)) {
        _entries.remove(cacheKey);
      }
    }));
    while (_entries.length > maxEntries) {
      _entries.remove(_entries.keys.first);
    }
    return value;
  }

  /// Drops every entry.
  void clear() => _entries.clear();
}

class _CacheEntry<V> {
  final Future<V> value;
  final DateTime expiresAt;
  _CacheEntry(this.value, this.expiresAt);
}

class _CacheKey {
  final List<Object?> parts;
  final int _hash;

  _CacheKey(this.parts) : _hash = Object.hashAll(parts);

  @override
  int get hashCode => _hash;

  @override
  bool operator ==(Object other) {
    if (other is! _CacheKey ||
        other._hash != _hash ||
        other.parts.length != parts.length) {
      return false;
    }
    for (var i = 0; i < parts.length; i++) {
      if (parts[i] != other.parts[i]) return false;
    }
    return true;
  }
}

/// Fixed-backoff retry with optional exception filtering (`@Retryable`).
///
/// Named `RetryPolicy` (not `Retryable`) because `package:diana` re-exports
/// the annotation of that name.
class RetryPolicy {
  /// Total attempts, first call included.
  final int maxAttempts;

  /// Fixed delay between attempts.
  final Duration backoff;

  /// Only errors this returns `true` for are retried; `null` retries all.
  final bool Function(Object error)? retryWhen;

  const RetryPolicy({
    this.maxAttempts = 3,
    this.backoff = const Duration(milliseconds: 200),
    this.retryWhen,
  });

  /// Runs [attempt] up to [maxAttempts] times; rethrows the last error.
  Future<T> run<T>(Future<T> Function() attempt) async {
    var attempts = 0;
    while (true) {
      attempts++;
      try {
        return await attempt();
      } catch (error) {
        if (attempts >= maxAttempts || !(retryWhen?.call(error) ?? true)) {
          rethrow;
        }
        if (backoff > Duration.zero) {
          await Future<void>.delayed(backoff);
        }
      }
    }
  }
}

/// Circuit breaker (`@CircuitBreaker`): closed → open after
/// [failureThreshold] consecutive failed calls; while open, [run] throws
/// [CircuitOpenException] without invoking the call; after [resetTimeout]
/// one half-open trial is allowed — success closes the circuit, failure
/// re-opens it. State is per instance (one per proxied method), per
/// isolate. Named `CircuitBreakerPolicy` because `package:diana` re-exports
/// the `CircuitBreaker` annotation.
class CircuitBreakerPolicy {
  final int failureThreshold;
  final Duration resetTimeout;

  int _consecutiveFailures = 0;
  DateTime? _openedAt;
  bool _halfOpenInFlight = false;

  CircuitBreakerPolicy({
    this.failureThreshold = 5,
    this.resetTimeout = const Duration(seconds: 30),
  });

  Future<T> run<T>(Future<T> Function() call) async {
    if (_openedAt != null) {
      final elapsed = DateTime.now().difference(_openedAt!);
      if (elapsed < resetTimeout || _halfOpenInFlight) {
        throw const CircuitOpenException();
      }
      _halfOpenInFlight = true; // exactly one half-open trial
    }
    try {
      final result = await call();
      _consecutiveFailures = 0;
      _openedAt = null;
      _halfOpenInFlight = false;
      return result;
    } catch (_) {
      if (_halfOpenInFlight) {
        _openedAt = DateTime.now(); // failed trial: fresh open window
        _halfOpenInFlight = false;
      } else {
        _consecutiveFailures++;
        if (_consecutiveFailures >= failureThreshold) {
          _openedAt = DateTime.now();
        }
      }
      rethrow;
    }
  }
}

/// Thrown by [CircuitBreakerPolicy.run] while the circuit is open. Maps to
/// an opaque 500 by default; use a `@ControllerAdvice` to translate it
/// (e.g. into a 503).
class CircuitOpenException implements Exception {
  const CircuitOpenException();

  @override
  String toString() => 'CircuitOpenException: circuit is open';
}

/// Per-method cache configuration handed to a [DianaCacheStore].
class CacheSpec {
  /// `Class.method` — unique per app, meant for key namespacing.
  final String method;

  final Duration ttl;

  /// Entry-count hint; the in-memory store enforces it (LRU), distributed
  /// stores may ignore it in favour of their own eviction.
  final int maxEntries;

  const CacheSpec({
    required this.method,
    required this.ttl,
    required this.maxEntries,
  });
}

/// Pluggable `@Cacheable` backend: declare exactly one singleton provider
/// extending this and every cached method routes through it instead of the
/// built-in per-proxy [MethodCache].
///
/// Wrap-style: the store owns the whole policy — lookup, populate,
/// single-flight, TTL and eviction — and how to stringify/serialize
/// [key] (the argument list, compared element-wise by the default). A
/// distributed store must round-trip the cached values itself; misses run
/// [miss] and the result must come back as `V`.
abstract class DianaCacheStore {
  const DianaCacheStore();

  Future<V> run<V>(
      CacheSpec spec, List<Object?> key, Future<V> Function() miss);

  /// Drops every entry (optional; no-op by default).
  FutureOr<void> clear() {}
}

/// The per-isolate default, exposed for stores that decorate it (logging,
/// metrics, fallbacks): one [MethodCache] per [CacheSpec.method], with the
/// same semantics as the built-in backend — TTL + LRU, single-flight,
/// errors never cached.
class InMemoryCacheStore extends DianaCacheStore {
  final Map<String, MethodCache<Object?>> _caches = {};

  @override
  Future<V> run<V>(
      CacheSpec spec, List<Object?> key, Future<V> Function() miss) async {
    final cache = _caches.putIfAbsent(spec.method,
        () => MethodCache<Object?>(ttl: spec.ttl, maxEntries: spec.maxEntries));
    return await cache.run(key, miss) as V;
  }

  @override
  void clear() {
    for (final cache in _caches.values) {
      cache.clear();
    }
  }
}
