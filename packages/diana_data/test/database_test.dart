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
  Future<void> close(Object connection) =>
      (connection as KnexSQLite).close();
}

Future<Database> openDb() async {
  final db = Database(SqliteConnector(), const DianaConfig.empty());
  await db.open();
  return db;
}

Future<int> balance(Database db, String name) async {
  final rows =
      await db.select(db.table('accounts').where('name', '=', name));
  return rows.single['balance'] as int;
}

void main() {
  test('insert + select round-trip through the facade', () async {
    final db = await openDb();
    addTearDown(db.close);
    await db.insert(db.table('accounts').insert({'name': 'ada', 'balance': 100}));
    expect(await balance(db, 'ada'), 100);
  });

  test('runTransactional commits on success', () async {
    final db = await openDb();
    addTearDown(db.close);
    await db.insert(db.table('accounts').insert({'name': 'ada', 'balance': 100}));
    await db.runTransactional(() async {
      await db.update(
          db.table('accounts').where('name', '=', 'ada').update({'balance': 50}));
    });
    expect(await balance(db, 'ada'), 50);
  });

  test('runTransactional rolls back on throw', () async {
    final db = await openDb();
    addTearDown(db.close);
    await db.insert(db.table('accounts').insert({'name': 'ada', 'balance': 100}));
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
    await db.insert(db.table('accounts').insert({'name': 'ada', 'balance': 100}));
    await db.runTransactional(() async {
      await db.update(
          db.table('accounts').where('name', '=', 'ada').update({'balance': 90}));
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
}
