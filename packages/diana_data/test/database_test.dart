import 'dart:io';

import 'package:diana/diana.dart';
import 'package:diana_data/diana_data.dart';
import 'package:knex_dart_sqlite/knex_dart_sqlite.dart';
import 'package:test/test.dart';

/// A real connector over an in-memory SQLite database — hermetic, no
/// external server.
class SqliteConnector extends DatabaseConnector {
  @override
  Future<Object> connect(DianaConfig config) async {
    final db = await KnexSQLite.connect(filename: ':memory:');
    await db.executeSchema((s) {
      s.createTable('accounts', (t) {
        t.increments('id');
        t.string('name').notNullable();
        t.integer('balance').notNullable();
      });
    });
    return db;
  }

  @override
  Future<void> close(Object connection) => (connection as KnexSQLite).close();
}

Future<Database> openDb() async {
  final db = Database(SqliteConnector(), const DianaConfig.empty());
  await db.open();
  return db;
}

Future<int> balance(Database db, String name) async {
  final rows = await db.select(db.table('accounts').where('name', '=', name));
  return rows.single['balance'] as int;
}

void main() {
  test('insert + select round-trip through the facade', () async {
    final db = await openDb();
    addTearDown(db.close);
    await db
        .insert(db.table('accounts').insert({'name': 'ada', 'balance': 100}));
    expect(await balance(db, 'ada'), 100);
  });

  test('runTransactional commits on success', () async {
    final db = await openDb();
    addTearDown(db.close);
    await db
        .insert(db.table('accounts').insert({'name': 'ada', 'balance': 100}));
    await db.runTransactional(() async {
      await db.update(db
          .table('accounts')
          .where('name', '=', 'ada')
          .update({'balance': 50}));
    });
    expect(await balance(db, 'ada'), 50);
  });

  test('runTransactional rolls back on throw', () async {
    final db = await openDb();
    addTearDown(db.close);
    await db
        .insert(db.table('accounts').insert({'name': 'ada', 'balance': 100}));
    await expectLater(
      db.runTransactional(() async {
        await db.update(db
            .table('accounts')
            .where('name', '=', 'ada')
            .update({'balance': 0}));
        throw StateError('boom');
      }),
      throwsA(isA<StateError>()),
    );
    expect(await balance(db, 'ada'), 100, reason: 'the update must be undone');
  });

  test('nested transaction: inner rollback keeps outer work (savepoint)',
      () async {
    final db = await openDb();
    addTearDown(db.close);
    await db
        .insert(db.table('accounts').insert({'name': 'ada', 'balance': 100}));
    await db.runTransactional(() async {
      await db.update(db
          .table('accounts')
          .where('name', '=', 'ada')
          .update({'balance': 90}));
      // Inner transaction fails and rolls back to its savepoint only.
      try {
        await db.runTransactional(() async {
          await db.update(db
              .table('accounts')
              .where('name', '=', 'ada')
              .update({'balance': 0}));
          throw StateError('inner boom');
        });
      } on StateError {
        // swallow: outer transaction continues
      }
    });
    expect(await balance(db, 'ada'), 90,
        reason: 'outer commit survives; inner savepoint rolled back');
  });

  test('observer sees each operation labelled by kind', () async {
    final obs = _RecordingObserver();
    final db =
        Database(SqliteConnector(), const DianaConfig.empty(), observer: obs);
    await db.open();
    addTearDown(db.close);

    await db
        .insert(db.table('accounts').insert({'name': 'ada', 'balance': 10}));
    await db.select(db.table('accounts'));
    await db.runTransactional(() async {
      await db.update(db
          .table('accounts')
          .where('name', '=', 'ada')
          .update({'balance': 5}));
    });
    expect(obs.ops, containsAll(['insert', 'select', 'transaction', 'update']));
  });

  test('without an observer the facade is a passthrough', () async {
    final db = await openDb();
    addTearDown(db.close);
    await db.insert(db.table('accounts').insert({'name': 'x', 'balance': 1}));
    expect(await balance(db, 'x'), 1);
  });

  test('migrate() is leader-only: worker isolates skip it', () async {
    final dir = Directory.systemTemp.createTempSync('diana_mig');
    addTearDown(() => dir.deleteSync(recursive: true));
    File('${dir.path}/001_notes.sql')
        .writeAsStringSync('CREATE TABLE notes (id INTEGER PRIMARY KEY);');
    final config = DianaConfig({'db.migrations.dir': dir.path});

    final db = Database(SqliteConnector(), config);
    await db.open();
    addTearDown(db.close);

    DianaRuntime.isWorkerIsolate = true;
    addTearDown(() => DianaRuntime.isWorkerIsolate = false);
    await db.migrate();
    // Skipped: the migration table itself must not have been created.
    expect(
      () => db.select(db.table('_diana_migrations')),
      throwsA(anything),
    );

    DianaRuntime.isWorkerIsolate = false;
    await db.migrate();
    expect(await db.select(db.table('_diana_migrations')), hasLength(1));
    await db.insert(db.table('notes').insert({'id': 1}));
  });

  group('migrate statement splitting', () {
    late Directory dir;

    setUp(() => dir = Directory.systemTemp.createTempSync('diana_migrations'));
    tearDown(() => dir.deleteSync(recursive: true));

    Future<Database> openMigrated() async {
      final db = Database(
          SqliteConnector(), DianaConfig({'db.migrations.dir': dir.path}));
      await db.open();
      await db.migrate();
      return db;
    }

    test('a multi-statement file runs once and is recorded', () async {
      File('${dir.path}/001_t.sql')
          .writeAsStringSync('CREATE TABLE t (id INTEGER PRIMARY KEY);\n'
              'INSERT INTO t (id) VALUES (1);\n');
      final db = await openMigrated();
      addTearDown(db.close);
      await db.migrate(); // second run: already recorded, must not re-insert
      expect(await db.select(db.table('t')), hasLength(1));
      final applied = await db.select(db.table('_diana_migrations'));
      expect(applied.single['name'], '001_t.sql');
    });

    test("';' inside a single-quoted literal (with '' escape) does not split",
        () async {
      File('${dir.path}/001_notes.sql').writeAsStringSync(r'''
CREATE TABLE notes (id INTEGER PRIMARY KEY, body TEXT NOT NULL);
INSERT INTO notes (body) VALUES ('first; it''s got; semicolons');
INSERT INTO notes (body) VALUES ('second');
''');
      final db = await openMigrated();
      addTearDown(db.close);
      final rows = await db.select(db.table('notes'));
      expect(rows, hasLength(2));
      expect(rows.first['body'], "first; it's got; semicolons");
    });

    test("';' inside comments and double-quoted identifiers does not split",
        () async {
      File('${dir.path}/001_odd.sql').writeAsStringSync(r'''
-- line comment; not a separator
/* block; comment */
CREATE TABLE "odd;name" (id INTEGER PRIMARY KEY, "col;umn" TEXT NOT NULL);
INSERT INTO "odd;name" ("col;umn") VALUES ('x');
-- trailing comment; must not become a statement
''');
      final db = await openMigrated();
      addTearDown(db.close);
      final rows = await db.raw('SELECT "col;umn" AS v FROM "odd;name"');
      expect(rows.single['v'], 'x');
    });
  });
}

class _RecordingObserver extends DianaObserver {
  final List<String> ops = [];

  @override
  Future<T> observeQuery<T>(String operation, dynamic run) async {
    ops.add(operation);
    return await run() as T;
  }
}
