import 'package:diana/diana.dart';

import '../dto/post.dart';
import '../repositories/post_repository.dart';

/// Business logic. The `@Transactional` methods run inside a database
/// transaction: Diana generates a proxy that wraps each one, so an exception
/// rolls back every write.
@Service()
class BlogService {
  final PostRepository posts;

  BlogService(this.posts);

  Future<List<Article>> list() => posts.all();

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
