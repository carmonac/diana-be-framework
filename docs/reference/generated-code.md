# Generated code reference

What `diana_generator` emits, where, and under which names. Generated files
start with `// GENERATED CODE - DO NOT MODIFY BY HAND` and suppress lints
with `// ignore_for_file: type=lint`; they are analyzed for *errors* like
any other code. Output is deterministic — rebuilding unchanged sources is
byte-identical, so generated files can (and should) be committed.

## The three builders

| Builder | Input | Output | Visible? |
|---|---|---|---|
| `diana_metadata` | every `lib/**.dart` with Diana annotations | `<file>.diana.json` | no (build cache) |
| `diana_part` | libraries needing local code | `<file>.diana.dart` (part) | yes (source tree) |
| `diana_bootstrap` | the `@DianaApplication` library | `<file>.diana_app.dart` | yes (source tree) |

They are auto-applied when `diana_generator` is in `dev_dependencies` — no
`build.yaml` needed in applications.

## Part files (`<file>.diana.dart`)

A library gets a part file when it declares any of:

- a `@RestController` with routes → **route adapters**
- a class with validation constraints (or referenced via `@Valid`) →
  **validators**
- a `@Json` class → **JSON codecs** (`$XFromJson`/`$XToJson`)
- a `@ConfigurationProperties` class → **config binders**

The library must contain `part '<file>.diana.dart';` — the build fails
with the exact line to add when it's missing. Libraries with only
injectables/middleware/advices don't need one.

### Route adapters

One public function per route method:

```
$diana$<ControllerName>$<methodName>
Future<DianaResponse> Function(<ControllerName> c, DianaRequest req)
```

The adapter performs, in order: parameter binding → body decoding → DTO
construction (`fromJson`) → validation (if the DTO has constraints) →
method invocation (awaited if `Future`) → result serialization (with
`@ResponseStatus` applied).

Variations by annotation/return type:

- `@Consumes` routes decode through `decodeMapBody`/`decodeListBody` with
  the declared MIME list instead of the JSON-only helpers.
- `@Produces` routes serialize through `negotiatedResponse` with the
  declared MIME list instead of `DianaResponse.json`.
- `Stream` returns compile to `return sseResponse(req, result);` —
  `Stream<Dto>` elements are first mapped through
  `ServerSentEvent.json($<Dto>ToJson(e))`.
- `@Principal()` parameters bind via `bindPrincipal<T>(req)` (exported from
  `package:diana`, so the part file needs no `diana_auth` import).

Adapters are public because the bootstrap library (a different library)
references them; treat the `$diana$` prefix as internal.

For providers with `@Transactional` methods the composition root also emits
a `$Tx$<Provider>` proxy subclass (in the app library) overriding each such
method to wrap `super.method(...)` in `Database.runTransactional`; the graph
injects the proxy in place of the raw class.

### Validators

One public class per constrained DTO:

```
$<ClassName>Validator implements Validator<ClassName>   // const constructor
```

One `check*` call per constraint, plus `mergeNested` blocks for `@Valid`
cascades. Public so adapters in *other* libraries (controllers using the
DTO) can invoke them.

### JSON codecs

One public pair per `@Json` class:

```
$<ClassName>FromJson(Map<String, dynamic>) → <ClassName>
$<ClassName>ToJson(<ClassName>) → Map<String, dynamic>
```

Route adapters call these automatically (wrapped in `decodeDto`, so shape
mismatches surface as 400s).

### Config binders

One public function per `@ConfigurationProperties` class:

```
$<ClassName>FromConfig(DianaConfig config) → <ClassName>
```

## The composition root (`<file>.diana_app.dart`)

A standalone library generated next to the `@DianaApplication` class. All
imports are prefixed (`_i1`, `_i2`, …) and managed automatically.

### `DianaContext`

The DI container. Contents, in topological (dependency) order:

- `final DianaConfig config` and `final DianaOverrides _overrides`
  (constructor parameters)
- one `late final <Type> <camelCaseName>` field per singleton provider —
  wired as `_overrides.x ?? RealX(...)` — including controllers,
  middleware, advices, and `@ConfigurationProperties` classes (initialized
  via their generated binder). Name collisions are disambiguated with `$1`,
  `$2`, … suffixes.
- one `<Type> create<Type>()` factory method per transient provider.
- when the app uses events: a `final DianaEventBus eventBus = DianaEventBus();`
  field, with one `eventBus.on<EventType>((e) => provider.method(e));`
  registration per `@EventListener` in the constructor body (closures, so
  no provider is constructed eagerly), and `DianaEventPublisher`
  constructor parameters satisfied with `eventBus` (or `_ctx.eventBus` on
  the request scope).
- when the app uses observability: `DianaServer`, the event bus, the
  scheduler and `Database` receive `observer: <the DianaObservability
  provider field>`, and `@Scheduled` tasks are emitted with a `name:`.
- when the app uses persistence: a `late final Database database =
  Database(connector, config);` field (from `package:diana_data`), opened
  (and migrated) at the start of `initialize()` and closed at the end of
  `dispose()`; `Database` constructor parameters are satisfied with it.
- `Future<void> initialize()` — constructs every singleton in dependency
  order and runs `@PostConstruct` hooks.
- `Future<void> dispose()` — runs `@PreDestroy` hooks in reverse order.

### `DianaOverrides`

One nullable `final` field per provider (typed by the concrete class),
`const` constructor — the test-override surface (see
[lifecycle guide](../guides/lifecycle.md#test-overrides--dianaoverrides)).

### `DianaApp`

`context` + `server` + `initialize()`/`dispose()`. When `@Scheduled`
methods exist, it also owns a `DianaScheduler` (`late final`, registrations
in the initializer, `perIsolate: true` forwarded from the annotation)
started by `initialize()` and stopped first in `dispose()` — the scheduler
itself skips leader-only tasks in worker isolates. When `@GrpcService` classes exist, it owns a
`DianaGrpcServer` (from `package:diana_grpc`) holding every service
instance from the context, served by `initialize()` and shut down first in
`dispose()` — exposed as `app.grpcServer`.

### `DianaRequestScope`

Emitted only when request-scoped providers exist. Holds a reference to the
`DianaContext` plus `late final` fields for request-scoped providers (and
factory methods for transients that depend on them). A fresh scope is
created per request for request-scoped controllers.

### `_mapException`

Emitted when `@ControllerAdvice` classes exist: a private function chaining
`if (e is X) return ctx.advice.handler(e[, req]);` checks, most specific
exception type first, ending in `return null;` (fall through to built-in
handling).

### Public functions

```dart
DianaContext buildDianaContext({DianaConfig? config, DianaOverrides overrides});
Future<DianaApp> buildDianaApp({DianaConfig? config, DianaOverrides overrides});
Future<DianaServer> buildDianaServer({DianaConfig? config, DianaOverrides overrides});
Future<void> runDiana({DianaConfig? config, DianaOverrides overrides});
const String dianaOpenApiJson;
```

`buildDianaApp`:

1. `config ?? await DianaConfig.load('<configFile>')` (profile overlays
   included)
2. constructs `DianaContext(cfg, overrides)`
3. constructs `DianaServer` with the order-sorted global middleware, the
   advice chain and any discovered `BodyCodec` singletons
   (`bodyCodecs: [...]`, emitted only when codecs exist)
4. registers actuator endpoints (guarded by `management.enabled`) and the
   OpenAPI route (guarded by `server.openapi.enabled`)
5. registers every route: `server.register(HttpMethod.x, '/full/path',
   (req) => $diana$Ctrl$method(ctx.ctrl, req), middleware: [...],
   cors: ...)` — controllers sorted by type, routes in declaration order.
   When a route (or its controller) carries `@Secured`/`@RolesAllowed`, a
   `const SecuredGuard()` / `RolesGuard([...])` from `package:diana_auth`
   is appended **last** in `middleware:` (runs after authentication,
   before the handler)
6. registers every WebSocket endpoint (sorted by path) with its handshake
   middleware: `server.registerWebSocket('/ws/x', () => ctx.handler,
   middleware: [...])`

`runDiana` wraps `buildDianaApp` in `DianaRuntime.run` (initialize → serve
→ graceful shutdown → dispose), passing `eventBus: app.context.eventBus`
to `DianaRunnable` when the app uses events (enables the cross-isolate
broadcast bridge).

## Interop with other generators

Diana uses the `.diana.dart` suffix (not `.g.dart`) precisely so it
composes with `source_gen`-based generators like `json_serializable` — a
library can have both `part 'x.diana.dart';` and `part 'x.g.dart';`, and
one `build_runner` invocation drives all builders.

## Determinism guarantees

- All emission is sorted (providers topologically then by name, controllers
  by type, global middleware by `(order, type)`, summaries by path).
- No timestamps or random values are ever emitted.
- Optional features (`eventBus`, `grpcServer`, `scheduler`, `bodyCodecs`,
  auth guards, the gRPC auth interceptor, the `database` field and `$Tx$`
  proxies, and the observability wiring / `/actuator/metrics`) are emitted
  only when used — an app without them produces
  byte-identical output before and after a generator upgrade that adds the
  feature.
- CI can enforce freshness with `git diff --exit-code` after a build.
