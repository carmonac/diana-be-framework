# diana_data

Persistence for the [Diana framework](https://github.com/carmonac/diana-be-framework):
an injectable `Database` over the [knex_dart](https://pub.dev/packages/knex_dart)
query builder, ambient transactions with `@Transactional`,
Spring-Data-style query repositories, a lightweight migration runner and a
database health indicator.

```yaml
dependencies:
  diana: ^0.15.0
  diana_data: ^0.15.0
  knex_dart_sqlite: ^0.4.0 # or the driver for your database
```

It is driver-agnostic: `diana_data` depends only on `knex_dart` core, and
you supply the connection through a small connector.

Read the [persistence guide](https://carmonac.github.io/diana-be-framework/guides/persistence/).
