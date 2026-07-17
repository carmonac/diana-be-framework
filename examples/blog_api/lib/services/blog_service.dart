import 'package:diana/diana.dart';

import '../dto/post.dart';
import '../repositories/post_repository.dart';

/// Business logic. The `@Transactional` methods run inside a database
/// transaction: Diana generates a proxy that wraps each one, so an exception
/// rolls back every write.
/// Thrown by the flaky publisher to exercise `@Retryable`.
class TransientDbFailure implements Exception {}

@Service()
class BlogService {
  final PostRepository posts;

  int _flakyAttempts = 0;

  BlogService(this.posts);

  Future<List<Article>> list() => posts.all();

  /// Cached: repeated calls within the TTL skip the database entirely, and
  /// `@Timed` feeds `diana_method_duration_seconds{method=...}`.
  @Timed()
  @Cacheable(ttlSeconds: 60)
  Future<int> totalPosts() => posts.count();

  /// Retries with a fresh transaction per attempt: each failed attempt
  /// rolls its insert back, the final one commits exactly one row.
  @Retryable(maxAttempts: 3, backoffMs: 10, retryOn: [TransientDbFailure])
  @Transactional()
  Future<Article> publishFlaky(CreatePost post) async {
    final article = await posts.create(post.title, post.body);
    if (++_flakyAttempts % 3 != 0) throw TransientDbFailure();
    return article;
  }

  /// Always fails: after two consecutive failures the circuit opens and
  /// rejects immediately with `CircuitOpenException`.
  @CircuitBreaker(failureThreshold: 2, resetTimeoutMs: 60000)
  Future<void> unstable() async =>
      throw ConflictException('Simulated dependency outage.');

  Future<Article> get(int id) async =>
      await posts.find(id) ?? (throw NotFoundException('No post $id.'));

  /// Two inserts in one transaction — both commit or neither does.
  @Transactional()
  Future<List<Article>> publishPair(CreatePost first, CreatePost second) async {
    final a = await posts.create(first.title, first.body);
    final b = await posts.create(second.title, second.body);
    return [a, b];
  }

  /// Demonstrates rollback: the second insert throws, so the first is undone.
  @Transactional()
  Future<void> publishThenFail(CreatePost post) async {
    await posts.create(post.title, post.body);
    throw ConflictException('Simulated failure after the insert.');
  }
}
