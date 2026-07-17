import 'dart:async';
import 'dart:io';

import 'package:diana/diana.dart' show DianaConfig, DianaObserver, DianaRuntime;
import 'package:knex_dart/knex_dart.dart' show QueryBuilder;

import 'connector.dart';

/// Zone key carrying the ambient transaction executor established by
/// [Database.runTransactional]. Repositories read it transparently through
/// the executor resolution in [_executor].
const Symbol _txZoneKey = #dianaDataTx;

/// The injectable query executor. Repositories receive it via constructor
/// injection; the generated composition root wires it and manages its
/// lifecycle (open on startup, close on shutdown).
///
/// **knex_dart 1.3 note:** the runnable API (`select`/`insert`/`trx`/`close`)
/// lives on the *driver* connection and on `KnexTransaction`, with no shared
/// static interface between them, so this facade dispatches **dynamically**
/// to whichever executor is current — the ambient transaction from the Zone,
/// else the pooled connection — while presenting a typed surface over the
/// core `QueryBuilder`.
class Database {
  final DatabaseConnector _connector;
  final DianaConfig config;

  /// Observes query and transaction durations. `null` costs nothing.
  final DianaObserver? observer;

  dynamic _conn;

  Database(this._connector, this.config, {this.observer});

  /// Opens the connection/pool (application startup).
  Future<void> open() async {
    _conn = await _connector.connect(config);
  }

  /// Closes the connection/pool (graceful shutdown). Idempotent.
  Future<void> close() async {
    final Object? conn = _conn;
    _conn = null;
    if (conn != null) await _connector.close(conn);
  }

  /// The executor for the current query: the ambient transaction when inside
  /// a [runTransactional] scope, otherwise the pooled connection.
  dynamic get _executor => Zone.current[_txZoneKey] ?? _conn;

  /// A query builder scoped to [table].
  QueryBuilder table(String table) =>
      (_conn as dynamic).queryBuilder().table(table) as QueryBuilder;

  /// A bare query builder (for sub-queries, CTEs, …).
  QueryBuilder query() => (_conn as dynamic).queryBuilder() as QueryBuilder;

  /// Wraps a database operation in the observer, if any.
  Future<T> _observed<T>(String operation, Future<T> Function() run) async =>
      observer == null
          ? await run()
          : await observer!.observeQuery(operation, run);

  /// Runs a SELECT-shaped [query] and returns the rows.
  Future<List<Map<String, dynamic>>> select(QueryBuilder query) => _observed(
      'select',
      () async => (await (_executor as dynamic).select(query) as List)
          .cast<Map<String, dynamic>>());

  /// Runs an INSERT [query].
  Future<List<Map<String, dynamic>>> insert(QueryBuilder query) => _observed(
      'insert',
      () async => (await (_executor as dynamic).insert(query) as List)
          .cast<Map<String, dynamic>>());

  /// Runs an UPDATE [query].
  Future<List<Map<String, dynamic>>> update(QueryBuilder query) => _observed(
      'update',
      () async => (await (_executor as dynamic).update(query) as List)
          .cast<Map<String, dynamic>>());

  /// Runs a DELETE [query].
  Future<List<Map<String, dynamic>>> delete(QueryBuilder query) => _observed(
      'delete',
      () async => (await (_executor as dynamic).delete(query) as List)
          .cast<Map<String, dynamic>>());

  /// Executes raw [sql] against the ambient executor.
  Future<List<Map<String, dynamic>>> raw(String sql,
          [List<Object?> bindings = const []]) =>
      _observed(
          'raw',
          () async =>
              (await (_executor as dynamic).rawSql(sql, bindings) as List)
                  .cast<Map<String, dynamic>>());

  /// Runs [body] inside a transaction. Nested calls **join** the enclosing
  /// transaction as a savepoint (propagation REQUIRED); a throw rolls the
  /// (save)point back and rethrows. This is what generated `@Transactional`
  /// proxies call.
  Future<T> runTransactional<T>(Future<T> Function() body) =>
      _observed('transaction', () async {
        // Nest on the *current* executor so an inner transaction becomes a
        // savepoint of the outer one rather than a new top-level transaction.
        final executor = _executor;
        return await (executor as dynamic).trx((dynamic tx) {
          return runZoned(body, zoneValues: {_txZoneKey: tx});
        }) as T;
      });

  /// Applies pending SQL migrations from `db.migrations.dir` (opt-in — a no-op
  /// when the key is unset). Runs each `*.sql` file (lexically sorted) that
  /// isn't yet recorded in `_diana_migrations`, one transaction per file.
  Future<void> migrate() async {
    final dir = config.get<String?>('db.migrations.dir');
    if (dir == null) return;
    // Leader-only, like @Scheduled: every isolate opens the pool, but with
    // multi-isolate serving a shared database must be migrated exactly once
    // (concurrent DDL from N isolates races and crashes worker startup).
    if (DianaRuntime.isWorkerIsolate) return;
    await raw('CREATE TABLE IF NOT EXISTS _diana_migrations '
        '(name TEXT PRIMARY KEY, applied_at TEXT NOT NULL)');
    final applied = {
      for (final row in await select(table('_diana_migrations')))
        row['name'] as String,
    };
    final files = Directory(dir)
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.sql'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    for (final file in files) {
      final name = file.uri.pathSegments.last;
      if (applied.contains(name)) continue;
      await runTransactional(() async {
        for (final statement in _splitStatements(file.readAsStringSync())) {
          await raw(statement);
        }
        await insert(table('_diana_migrations').insert({
          'name': name,
          'applied_at': DateTime.now().toIso8601String(),
        }));
      });
    }
  }

  /// Splits [sql] into statements on top-level `;`, skipping separators that
  /// appear inside single-quoted strings (with `''` escapes), double-quoted
  /// identifiers (with `""` escapes), `--` line comments or `/* */` block
  /// comments. Segments containing only whitespace/comments are dropped.
  ///
  /// Not a full SQL parser — dollar-quoted bodies (`$$ … $$`, Postgres) and
  /// procedural `BEGIN … END;` bodies (SQLite triggers) still fragment; see
  /// the limitations note in docs/guides/persistence.md.
  static Iterable<String> _splitStatements(String sql) sync* {
    final statement = StringBuffer();
    var hasContent = false; // any non-comment, non-whitespace character
    var i = 0;
    while (i < sql.length) {
      final c = sql[i];
      if (c == ';') {
        if (hasContent) yield statement.toString().trim();
        statement.clear();
        hasContent = false;
        i++;
      } else if (c == "'" || c == '"') {
        // Quoted string/identifier: a doubled quote is an escape, not an end.
        final start = i++;
        while (i < sql.length) {
          if (sql[i] != c) {
            i++;
          } else if (i + 1 < sql.length && sql[i + 1] == c) {
            i += 2;
          } else {
            i++;
            break;
          }
        }
        statement.write(sql.substring(start, i));
        hasContent = true;
      } else if (c == '-' && i + 1 < sql.length && sql[i + 1] == '-') {
        final start = i;
        final newline = sql.indexOf('\n', i);
        i = newline == -1 ? sql.length : newline;
        statement.write(sql.substring(start, i));
      } else if (c == '/' && i + 1 < sql.length && sql[i + 1] == '*') {
        final start = i;
        final end = sql.indexOf('*/', i + 2);
        i = end == -1 ? sql.length : end + 2;
        statement.write(sql.substring(start, i));
      } else {
        statement.write(c);
        if (c.trim().isNotEmpty) hasContent = true;
        i++;
      }
    }
    if (hasContent) yield statement.toString().trim();
  }
}
