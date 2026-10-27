# diana_data example

```yaml
dependencies:
  diana: ^0.15.0
  diana_data: ^0.15.0
  knex_dart_sqlite: ^0.4.0 # your driver of choice
```

Provide one connector — you own the driver import, Diana never does:

```dart
import 'package:diana/diana.dart';
import 'package:diana_data/diana_data.dart';
import 'package:knex_dart_sqlite/knex_dart_sqlite.dart';

@Component()
class AppDb extends DatabaseConnector {
  @override
  Future<Object> connect(DianaConfig config) =>
      KnexSQLite.connect(filename: config.get<String>('db.file'));

  @override
  Future<void> close(Object connection) => (connection as KnexSQLite).close();
}
```

Declare a Spring-Data-style repository — Diana generates the
implementation from the method names — and use it transactionally:

```dart
import 'package:diana/diana.dart';
import 'package:diana_data/diana_data.dart';

part 'comments.diana.dart';

@Json()
@Table('comments')
class Comment {
  final int? id;
  @JsonField(name: 'post_id')
  final int postId;
  final String author;
  const Comment({this.id, required this.postId, required this.author});
}

@Repository()
abstract class CommentRepository extends DianaRepository<Comment> {
  CommentRepository(super.db);

  Future<List<Comment>> findByPostId(int postId);
  Future<int> countByPostId(int postId);
}

@Service()
class CommentService {
  final CommentRepository comments;
  CommentService(this.comments);

  @Transactional() // both inserts commit together or roll back together
  Future<void> addPair(Comment a, Comment b) async {
    await comments.save(a);
    await comments.save(b);
  }
}
```

A complete, hermetic app (SQLite in memory) is in
[examples/blog_api](https://github.com/carmonac/diana-be-framework/tree/main/examples/blog_api).
See the [persistence guide](https://carmonac.github.io/diana-be-framework/guides/persistence/)
for raw queries, migrations and health checks.
