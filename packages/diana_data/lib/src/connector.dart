import 'package:diana/diana.dart' show DianaConfig;

/// Bridges Diana to a concrete `knex_dart` driver.
///
/// Subclass it as a provider (e.g. `@Component`) and return the driver
/// connection your application uses. **You** own the driver package
/// dependency (`knex_dart_postgres`, `knex_dart_sqlite`, …) and the
/// driver-specific close call — Diana never imports a driver.
///
/// ```dart
/// @Component()
/// class AppDb extends DatabaseConnector {
///   @override
///   Future<Object> connect(DianaConfig config) =>
///       KnexSQLite.connect(filename: config.get<String>('db.file'));
///
///   @override
///   Future<void> close(Object connection) =>
///       (connection as KnexSQLite).close();
/// }
/// ```
abstract class DatabaseConnector {
  /// Opens the connection/pool. Called once during application startup,
  /// before any provider is constructed.
  Future<Object> connect(DianaConfig config);

  /// Closes the connection/pool during graceful shutdown (postgres:
  /// `db.destroy()`, sqlite: `db.close()`).
  Future<void> close(Object connection);
}
