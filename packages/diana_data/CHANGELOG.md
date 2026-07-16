# Changelog

## 0.8.0

- `Database` accepts an optional `DianaObserver`, wrapping the five query
  methods and `runTransactional` for metrics/tracing.

## 0.7.0

- Version bump only (kept in lockstep with the workspace).

## 0.6.0

- Initial release: persistence for Diana over the `knex_dart` query builder.
- `Database` — an injectable query executor (`table`/`select`/`insert`/
  `update`/`delete`/`raw`) that resolves the ambient transaction from the
  current `Zone` or the pooled connection.
- `DatabaseConnector` — a user-subclassed provider that opens the driver
  connection (`KnexPostgres`/`KnexSQLite`/…) and owns its close; keeps
  diana_data driver-agnostic. `diana_data` depends only on `knex_dart`
  core (the only Diana package importing it).
- Ambient transactions: `runTransactional` (called by generated
  `@Transactional` proxies) nests as a savepoint and rolls back on throw.
- A lightweight opt-in migration runner (`db.migrations.dir`) and a
  `DatabaseHealthIndicator`.
