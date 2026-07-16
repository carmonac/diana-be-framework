# Application lifecycle

Diana applications have an explicit lifecycle:

```
buildDianaApp() → initialize() → serve() → [SIGINT/SIGTERM] → close() → dispose()
```

`runDiana()` drives all of it (via `DianaRuntime.run`); tests and embeddings
can drive each step themselves.

## @PostConstruct / @PreDestroy

Run code after construction and during shutdown, Spring-style:

```dart
@Repository()
class Db {
  late final Connection _conn;

  @PostConstruct()
  Future<void> connect() async => _conn = await Connection.open(...);

  @PreDestroy()
  Future<void> disconnect() => _conn.close();
}
```

Rules (build-verified): public instance method, no parameters, returns
`void` or `Future<void>`, at most one of each per class, **singleton
providers only**.

- `initialize()` constructs every singleton in dependency order and awaits
  each `@PostConstruct` — including `@ConfigurationProperties` binding, so
  missing required config keys fail here, before the port opens.
- `dispose()` runs `@PreDestroy` hooks in **reverse** dependency order,
  after the server has stopped and in-flight requests have drained.

Publishing [application events](events.md) from `@PostConstruct` is fully
supported — listeners are registered before initialization runs.

## Graceful shutdown

`runDiana()` installs SIGINT/SIGTERM handlers (SIGTERM skipped on Windows).
On a signal it stops accepting connections, waits for in-flight requests,
then disposes. Programmatic control:

```dart
final shutdown = Completer<void>();
await DianaRuntime.run(
  () async { final app = await buildDianaApp(); ... },
  installSignalHandlers: false,
  shutdownTrigger: shutdown.future,
);
```

## The generated DianaApp

```dart
final app = await buildDianaApp(config: ..., overrides: ...);
app.context;         // the DI container
app.server;          // the DianaServer
await app.initialize();
await app.server.serve(port: 0);
...
await app.server.close();
await app.dispose();
```

When `@Scheduled` tasks exist, `app.initialize()` also starts the scheduler
and `app.dispose()` stops it; with multi-isolate serving, tasks run once
per process unless annotated `perIsolate: true` (see
[Observability § Scheduling](observability.md#scheduled-tasks)).

## Test overrides — DianaOverrides

Every provider gets a nullable slot in the generated `DianaOverrides`
class; a non-null value replaces the real provider **everywhere it is
injected** (Spring `@MockBean` analog):

```dart
class FakeRepo implements InMemoryTodoRepository { ... }

final ctx = buildDianaContext(
  overrides: DianaOverrides(inMemoryTodoRepository: FakeRepo()),
);
expect(ctx.todoService.repo, isA<FakeRepo>());
```

Notes:

- Overrides are **per concrete provider class** (unambiguous when several
  classes implement one interface). Fakes can `implements` the concrete
  class.
- Works with `buildDianaContext`, `buildDianaServer`, `buildDianaApp` and
  `runDiana`.
- Overriding a transient provider effectively makes it a singleton for that
  context — exactly what tests want.
- With multi-isolate serving, overrides must be sendable (tests normally
  run single-isolate; not a practical concern).
