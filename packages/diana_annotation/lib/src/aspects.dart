import 'package:meta/meta_meta.dart';

/// Records the method's invocation duration and outcome as metrics (and a
/// trace span) via the app's observability provider (Micrometer's `@Timed`).
///
/// The method must return a `Future` and live on a
/// `@Service`/`@Component`/`@Repository` provider open to extension — the
/// generator emits a proxy subclass wrapping the call. Without a
/// `DianaObservability` provider the aspect is a silent no-op, so adding
/// observability later "turns it on" with no code change.
///
/// Composes with the other aspects in a fixed order (outermost first):
/// `@Timed` → `@Cacheable` → `@CircuitBreaker` → `@Retryable` →
/// `@Transactional` — timing measures the latency the caller experiences,
/// cache hits and open-breaker rejections included.
@Target({TargetKind.method})
class Timed {
  /// Metric label; defaults to `ClassName.methodName`.
  final String? name;

  const Timed({this.name});
}

/// Caches the method's result per argument list, in memory, per isolate
/// (Spring's `@Cacheable`).
///
/// The key is the argument list in declaration order — arguments need value
/// equality (`==`/`hashCode`) for hits to work. Entries expire after
/// [ttlSeconds] and the least-recently-used entry is evicted beyond
/// [maxEntries]. Errors are never cached, and concurrent misses for the
/// same key share a single computation. The method must return `Future<T>`
/// with a non-void `T` and must not declare type parameters.
@Target({TargetKind.method})
class Cacheable {
  /// Seconds an entry stays valid. Must be >= 1.
  final int ttlSeconds;

  /// Maximum entries kept per method (LRU beyond it). Must be >= 1.
  final int maxEntries;

  const Cacheable({this.ttlSeconds = 60, this.maxEntries = 1024});
}

/// Retries the method with a fixed backoff when it throws (spring-retry's
/// `@Retryable`).
///
/// [maxAttempts] is the total number of attempts (Spring-like, default 3).
/// [retryOn] limits retries to the listed exception types (subtypes match);
/// empty retries on anything. When composed with `@Transactional`, each
/// attempt runs in a fresh transaction.
@Target({TargetKind.method})
class Retryable {
  /// Total attempts, first call included. Must be >= 1.
  final int maxAttempts;

  /// Fixed delay between attempts, in milliseconds. Must be >= 0.
  final int backoffMs;

  /// Exception types worth retrying (empty = all).
  final List<Type> retryOn;

  const Retryable({
    this.maxAttempts = 3,
    this.backoffMs = 200,
    this.retryOn = const [],
  });
}

/// Fails fast when the method keeps failing (spring-retry's
/// `@CircuitBreaker`).
///
/// After [failureThreshold] consecutive failed invocations the circuit
/// opens: calls throw `CircuitOpenException` immediately without invoking
/// the method. After [resetTimeoutMs] one half-open trial call is allowed —
/// success closes the circuit, failure re-opens it. State is per method,
/// per isolate. Composed outside `@Retryable`, one guarded invocation is
/// one full retry budget.
@Target({TargetKind.method})
class CircuitBreaker {
  /// Consecutive failures that open the circuit. Must be >= 1.
  final int failureThreshold;

  /// Milliseconds the circuit stays open before a half-open trial.
  /// Must be >= 1.
  final int resetTimeoutMs;

  const CircuitBreaker({
    this.failureThreshold = 5,
    this.resetTimeoutMs = 30000,
  });
}
