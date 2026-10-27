import 'package:diana/diana.dart';
import 'package:diana_data/diana_data.dart';
import 'package:knex_dart_sqlite/knex_dart_sqlite.dart';
import 'package:test/test.dart';

/// In-memory connector with an `accounts` table (hermetic).
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

/// A hand-written concrete subclass — exercises the base's protected
/// helpers the same way generated `$Repo$X` implementations do.
class AccountRepository extends DianaRepository<Map<String, dynamic>> {
  AccountRepository(super.db);

  @override
  Future<List<Map<String, dynamic>>> findAll() =>
      db.select(db.table('accounts'));

  @override
  Future<Map<String, dynamic>?> findById(Object id) async {
    final rows =
        await db.select(db.table('accounts').where('id', '=', id).limit(1));
    return rows.isEmpty ? null : rows.first;
  }

  @override
  Future<void> save(Map<String, dynamic> entity) =>
      db.insert(db.table('accounts').insert(entity));

  @override
  Future<void> deleteById(Object id) =>
      db.delete(db.table('accounts').where('id', '=', id).delete());

  Future<int> countRich() =>
      runCount(db.table('accounts').where('balance', '>', 100));

  Future<bool> anyPoor() =>
      runExists(db.table('accounts').where('balance', '<', 10));
}

Future<AccountRepository> open() async {
  final db = Database(SqliteConnector(), const DianaConfig.empty());
  await db.open();
  return AccountRepository(db);
}

void main() {
  test('runCount and runExists aggregate through the query builder', () async {
    final repo = await open();
    addTearDown(repo.db.close);

    await repo.save({'name': 'ada', 'balance': 500});
    await repo.save({'name': 'bob', 'balance': 50});
    await repo.save({'name': 'eve', 'balance': 5});

    expect(await repo.countRich(), 1);
    expect(await repo.anyPoor(), isTrue);

    await repo.deleteById(3);
    expect(await repo.anyPoor(), isFalse);
  });

  test('CRUD helpers behave and findById misses return null', () async {
    final repo = await open();
    addTearDown(repo.db.close);

    await repo.save({'name': 'ada', 'balance': 500});
    expect(await repo.findAll(), hasLength(1));
    expect((await repo.findById(1))!['name'], 'ada');
    expect(await repo.findById(99), isNull);
  });

  test('runCount joins the ambient transaction', () async {
    final repo = await open();
    addTearDown(repo.db.close);

    await repo.db.runTransactional(() async {
      await repo.save({'name': 'tx', 'balance': 999});
      // Visible inside the same transaction before commit.
      expect(await repo.countRich(), 1);
    });
    expect(await repo.countRich(), 1, reason: 'committed');
  });
}
