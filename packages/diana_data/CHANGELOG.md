# Changelog

## 0.15.1

- Package metadata for pub.dev: MIT license, repository/documentation
  links, topics, and an `example/`.
- Added a README; shorter pub.dev description.

## 0.15.0

- Version bump only (kept in lockstep with the workspace).

## 0.14.0

- Version bump only (kept in lockstep with the workspace).

## 0.13.0

- New `DianaRepository<E>` base for Spring-Data-style query repositories:
  holds the injected `Database`, declares the CRUD quartet the generator
  implements, and exposes protected `runCount`/`runExists` helpers for
  generated `countBy*`/`existsBy*` methods.

## 0.12.0

- Version bump only (kept in lockstep with the workspace).

## 0.11.0

- Version bump only (kept in lockstep with the workspace).

## 0.10.0

- Version bump only (kept in lockstep; `@Transactional` folds into the new
  aspect pipeline with unchanged semantics and output).

## 0.9.0

- The migration runner splits SQL files on top-level `;` only: quoted
  strings/identifiers and comments may contain semicolons. Dollar-quoted
  and trigger bodies remain unsupported (documented).

## 0.8.1

- `migrate()` is leader-only: worker isolates skip it so a shared database
  is migrated exactly once under multi-isolate serving.

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
