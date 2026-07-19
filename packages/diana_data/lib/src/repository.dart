import 'package:knex_dart/knex_dart.dart' show QueryBuilder;
import 'package:meta/meta.dart';

import 'database.dart';

/// Base class for Diana query repositories (Spring Data style).
///
/// Extend it with an **abstract** `@Repository` class and Diana generates
/// the implementation: the four CRUD methods below plus every abstract
/// query method derived from its name (`findByTitle`, `countByBodyLike`,
/// `findByIdInOrderByIdDesc`, ...). The entity `T` must be a `@Json` class
/// annotated with `@Table('name')`; column names are the fields' JSON keys.
///
/// ```dart
/// @Repository()
/// abstract class CommentRepository extends DianaRepository<Comment> {
///   CommentRepository(super.db);
///
///   Future<List<Comment>> findByTitle(String title);
/// }
/// ```
///
/// A **concrete** subclass is an ordinary provider — you implement
/// everything yourself (the classic hand-written repository).
abstract class DianaRepository<T> {
  /// The injected executor; generated queries join the ambient transaction
  /// when called inside a `@Transactional` method.
  final Database db;

  DianaRepository(this.db);

  /// Every row of the entity's table.
  Future<List<T>> findAll();

  /// The row whose id column equals [id], or `null`.
  Future<T?> findById(Object id);

  /// Inserts [entity]: its `toJson` map minus null entries, so an
  /// autoincrement id can be omitted through a nullable `id` field. Null
  /// non-id columns fall back to their SQL defaults.
  Future<void> save(T entity);

  /// Deletes the row whose id column equals [id]; a no-op when absent.
  Future<void> deleteById(Object id);

  /// Runs [query] as `SELECT COUNT(*)` — the helper behind generated
  /// `countBy*` methods (kept here so generated code never touches
  /// `package:knex_dart` types). The count is the single column of the
  /// single result row, whatever the driver names it.
  @protected
  Future<int> runCount(QueryBuilder query) async {
    final rows = await db.select(query.count('*'));
    return (rows.single.values.single as num).toInt();
  }

  /// Whether [query] matches at least one row — the helper behind
  /// generated `existsBy*` methods.
  @protected
  Future<bool> runExists(QueryBuilder query) async => await runCount(query) > 0;
}
