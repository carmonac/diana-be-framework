import 'package:diana/diana.dart';
import 'package:diana_data/diana_data.dart';
import 'package:knex_dart_sqlite/knex_dart_sqlite.dart';

/// Opens the application's SQLite database. The connector owns the driver
/// dependency (`knex_dart_sqlite`) and the driver-specific close call —
/// diana_data stays driver-agnostic.
@Component()
class SqliteConnector extends DatabaseConnector {
  @override
  Future<Object> connect(DianaConfig config) => KnexSQLite.connect(
        filename: config.get<String>('db.file', defaultValue: ':memory:'),
      );

  @override
  Future<void> close(Object connection) =>
      (connection as KnexSQLite).close();
}
