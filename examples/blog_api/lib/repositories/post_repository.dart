import 'package:diana/diana.dart';
import 'package:diana_data/diana_data.dart';

import '../dto/post.dart';

/// Data access over `knex_dart`. `Database` is injected by Diana; queries run
/// against the ambient transaction when inside a `@Transactional` method,
/// otherwise the pooled connection.
@Repository()
class PostRepository {
  final Database db;

  PostRepository(this.db);

  Future<List<Article>> all() async {
    final rows = await db.select(db.table('posts'));
    return rows.map(_toPost).toList();
  }

  Future<Article?> find(int id) async {
    final rows = await db.select(db.table('posts').where('id', '=', id));
    return rows.isEmpty ? null : _toPost(rows.single);
  }

  Future<int> count() async {
    final rows = await db.raw('SELECT COUNT(*) AS n FROM posts');
    return rows.single['n'] as int;
  }

  Future<Article> create(String title, String body) async {
    await db.insert(db.table('posts').insert({'title': title, 'body': body}));
    final rows = await db.raw(
        'SELECT id, title, body FROM posts ORDER BY id DESC LIMIT 1');
    return _toPost(rows.single);
  }

  static Article _toPost(Map<String, dynamic> row) => Article(
        id: row['id'] as int,
        title: row['title'] as String,
        body: row['body'] as String,
      );
}
