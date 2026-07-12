# diana

Runtime for the [Diana framework](../../README.md): `DianaServer`, the
request pipeline (middleware composition + exception boundary),
`DianaRequest`/`DianaResponse`, `DianaConfig` (YAML + environment variables),
and the binding/validation helpers targeted by generated code.

Re-exports `package:diana_annotation`, so applications only import
`package:diana/diana.dart`.

The HTTP engine ([relic](https://pub.dev/packages/relic)) is confined to
`src/adapter/relic_adapter.dart` — nothing else in the framework, and nothing
in application code, touches it.
