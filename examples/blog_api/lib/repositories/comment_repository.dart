import 'package:diana/diana.dart';
import 'package:diana_data/diana_data.dart';

import '../dto/comment.dart';

/// A Spring-Data-style query repository: every abstract method below is
/// implemented by the generator from its name (plus the CRUD quartet
/// declared by [DianaRepository]). Exercises the whole derived-query
/// grammar against the `comments` table.
@Repository()
abstract class CommentRepository extends DianaRepository<Comment> {
  CommentRepository(super.db);

  Future<List<Comment>> findByPostId(int postId);
  Future<Comment?> findFirstByPostIdAndAuthor(int postId, String author);
  Future<int> countByPostId(int postId);
  Future<bool> existsByAuthor(String author);
  Future<void> deleteByPostId(int postId);
  Future<List<Comment>> findByBodyContainsOrderByIdDesc(String fragment);
  Future<List<Comment>> findByIdBetween(int low, int high);
  Future<List<Comment>> findByAuthorIn(List<String> authors);
  Future<List<Comment>> findByAuthorOrBody(String author, String body);
  Future<List<Comment>> findByBodyIsNull();
  Future<List<Comment>> findByPostIdNot(int postId);
  Future<List<Comment>> findByAuthorStartsWithOrderByAuthorAscIdDesc(
      String prefix);
  Future<List<Comment>> findByIdGreaterThanEqual(int id);
}
