/// Persistence for the Diana backend framework, built on the `knex_dart`
/// query builder.
///
/// Write a [DatabaseConnector] subclass that returns your driver connection,
/// inject [Database] into `@Repository` providers (or extend
/// [DianaRepository] with an abstract class and let Diana generate
/// Spring-Data-style query methods from their names), and wrap service
/// methods in `@Transactional` for ambient, savepoint-nesting transactions.
/// Diana opens the connection on startup, runs opt-in SQL migrations, and
/// closes it on graceful shutdown.
///
/// This is the only Diana package that depends on `package:knex_dart`
/// (enforced by a boundary test); the driver package is yours to choose.
library;

export 'src/connector.dart';
export 'src/database.dart';
export 'src/health.dart';
export 'src/repository.dart';
