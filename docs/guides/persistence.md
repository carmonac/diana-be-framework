# Persistence

Diana's data story lives in the optional **`diana_data`** package: an
injectable query executor over the
[knex_dart](https://pub.dev/packages/knex_dart) query builder, Spring-style
`@Transactional` methods, opt-in migrations and a database health check.

It is **driver-agnostic** — `diana_data` depends only on `knex_dart` core;
you pick the driver package (`knex_dart_postgres`, `knex_dart_sqlite`, …)
and supply the connection through a small connector.

## Setup

```yaml
# pubspec.yaml
dependencies:
  diana: ^0.11.0
  diana_data: ^0.11.0
  knex_dart_sqlite: ^0.4.0   # your driver of choice
```

## The connector

Write a `DatabaseConnector` subclass (a provider) that opens the driver
connection and closes it. You own the driver import and the driver-specific
close call — Diana never imports a driver:

```dart
import 'package:diana/diana.dart';
import 'package:diana_data/diana_data.dart';
import 'package:knex_dart_sqlite/knex_dart_sqlite.dart';

@Component()
class AppDb extends DatabaseConnector {
  @override
  Future<Object> connect(DianaConfig config) => KnexSQLite.connect(
        filename: config.get<String>('db.file'),
      );

  @override
  Future<void> close(Object connection) => (connection as KnexSQLite).close();
}
```

Diana opens the connection at the **start of startup** (before any provider,
so a repository's `@PostConstruct` can already query) and closes it at the
**end of graceful shutdown**. Declare exactly one connector — zero (while
using the database) or many are build errors.

## Repositories

Inject `Database` into any provider and use the knex query builder. Build a
query with `db.table('...')` (and `.where`, `.insert`, `.update`, …), then
execute it with `db.select`/`insert`/`update`/`delete`:

```dart
@Repository()
class PostRepository {
  final Database db;
  PostRepository(this.db);

  Future<List<Map<String, dynamic>>> all() => db.select(db.table('posts'));

  Future<void> add(String title) =>
      db.insert(db.table('posts').insert({'title': title}));

  Future<List<Map<String, dynamic>>> raw() => db.raw('SELECT 1');
}
```

`Database.select`/`insert`/… return `List<Map<String, dynamic>>` rows; map
them to your DTOs in the repository.

## Transactions

Annotate a service method with `@Transactional` and Diana runs it inside a
database transaction — every write commits together or rolls back together:

```dart
@Service()
class BlogService {
  final PostRepository posts;
  BlogService(this.posts);

  @Transactional()
  Future<void> publishPair(String a, String b) async {
    await posts.add(a);
    await posts.add(b);   // if this throws, the first insert is undone
  }
}
```

How it works: the generator emits a proxy subclass (`$Tx$BlogService`) that
overrides each `@Transactional` method to wrap the call in an ambient
transaction. Repositories don't change — `Database` transparently routes
queries to the current transaction (via a `Zone`) when one is active, and to
the pooled connection otherwise.

- **Propagation is REQUIRED**: a `@Transactional` method called from another
  joins the enclosing transaction as a **savepoint** — the inner method can
  roll back independently while the outer commits.
- **Rollback on throw**: an uncaught exception rolls the transaction (or
  savepoint) back and rethrows, so it still flows through your
  `@ControllerAdvice` / exception pipeline.

Constraints (build errors): the class must be **extendable** (not
`final`/`base`/`sealed`), the methods must return `Future`, and
`@Transactional` only applies to `@Service`/`@Component`/`@Repository`
providers.

**Caveat — always `await` database work inside a transaction.** The ambient
transaction travels on the current `Zone`, so anything fired and forgotten
inside a `@Transactional` body (`unawaited(db.insert(...))`, a `Timer`, a
detached `Future`) still carries the transaction after the method returns —
by then it has committed or rolled back, and a late query against it throws.
This fails loudly rather than corrupting data, but the fix is structural:
`await` every database call before the transactional method returns.

`@Transactional` composes with the [aspects](aspects.md)
(`@Retryable` retries each attempt in a fresh transaction; `@Cacheable`
misses populate through the transaction).

## Migrations

Set `db.migrations.dir` and Diana runs every `*.sql` file in that directory
(lexically sorted) that hasn't been applied yet, once each, during startup —
tracked in a `_diana_migrations` table. Migrations are **leader-only**
(like `@Scheduled`): under multi-isolate serving only the main isolate
migrates, so a shared database is migrated exactly once. It is opt-in:
with the key unset,
nothing runs.

```yaml
db:
  migrations:
    dir: migrations
```

```sql
-- migrations/001_create_posts.sql
CREATE TABLE posts (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  title TEXT NOT NULL
);
```

A file may hold several statements, separated by `;`. The splitter
understands single-quoted strings (including `''` escapes), double-quoted
identifiers and `--` / `/* */` comments, so a `;` inside any of those does
not break a statement apart, and separator-only or comment-only segments
are dropped.

**Limitations** — it is not a full SQL parser. Constructs that carry a raw
`;` inside a statement body still fragment:

- Postgres **dollar-quoted bodies** (`$$ … $$` in `CREATE FUNCTION` /
  `DO` blocks);
- SQLite **trigger bodies** (`CREATE TRIGGER … BEGIN … ; … END`).

Apply such DDL outside the migration runner (e.g. via `db.raw(...)` from a
`@PostConstruct` hook), or write the body without inner semicolons. Each
migration file runs in a single transaction, so a mis-split statement fails
the file atomically at startup — the schema is left untouched.

## Health

Register the built-in indicator to expose database connectivity on
`/actuator/health`:

```dart
@Component()
class DbHealth extends DatabaseHealthIndicator {
  DbHealth(super.db);
}
```

## Configuration

The connector reads whatever `db.*` keys it needs via `@Value` or the
injected `DianaConfig` (`config.get('db.host')`, …). Only
`db.migrations.dir` is read by diana_data itself.

| Key | Meaning |
|---|---|
| `db.migrations.dir` | Directory of `*.sql` migrations to apply on startup (opt-in) |
| `db.*` | Anything your connector reads (host, port, file, credentials, …) |

## Testing

`Database` runs against an in-memory SQLite database with no external
server, so tests stay hermetic:

```dart
final app = await buildDianaApp(config: DianaConfig({
  'db.file': ':memory:',
  'db.migrations.dir': 'migrations',
}));
await app.initialize();
// ...exercise repositories / transactional services...
await app.dispose();
```

See [`examples/blog_api`](../../examples/blog_api) for a complete app.

## See also

- [Dependency injection](dependency-injection.md) — providers and scopes
- [Application lifecycle](lifecycle.md) — startup/shutdown ordering
- [Observability](observability.md) — `/actuator/health`
- [Build diagnostics](../reference/build-diagnostics.md) — the persistence errors
