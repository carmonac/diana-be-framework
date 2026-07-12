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

Adapters are public because the bootstrap library (a different library)
references them; treat the `$diana$` prefix as internal.

### Validators

One public class per constrained DTO:

```
$<ClassName>Validator implements Validator<ClassName>   // const constructor
```

One `check*` call per constraint, plus `mergeNested` blocks for `@Valid`
cascades. Public so adapters in *other* libraries (controllers using the
DTO) can invoke them.

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

- `final DianaConfig config` (constructor parameter)
- one `late final <Type> <camelCaseName>` field per singleton provider —
  including controllers, middleware, advices, and
  `@ConfigurationProperties` classes (initialized via their generated
  binder). Name collisions across libraries are disambiguated with `$1`,
  `$2`, … suffixes.
- one `<Type> create<Type>()` factory method per transient provider.

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
DianaContext buildDianaContext({DianaConfig? config});
Future<DianaServer> buildDianaServer({DianaConfig? config});
Future<void> runDiana({DianaConfig? config});
```

`buildDianaServer`:

1. `config ?? await DianaConfig.load('<configFile>')`
2. constructs `DianaContext`
3. constructs `DianaServer` with the order-sorted global middleware and the
   advice chain
4. registers every route: `server.register(HttpMethod.x, '/full/path',
   (req) => $diana$Ctrl$method(ctx.ctrl, req), middleware: [...])` —
   controllers sorted by type for deterministic output, routes in
   declaration order, `middleware:` holding the controller-level then
   route-level chain.
5. registers every WebSocket endpoint (sorted by path):
   `server.registerWebSocket('/ws/x', () => ctx.handler)` for singleton
   handlers, `() => ctx.createHandler()` for transient (per-connection)
   ones.

## Interop with other generators

Diana uses the `.diana.dart` suffix (not `.g.dart`) precisely so it
composes with `source_gen`-based generators like `json_serializable` — a
library can have both `part 'x.diana.dart';` and `part 'x.g.dart';`, and
one `build_runner` invocation drives all builders.

## Determinism guarantees

- All emission is sorted (providers topologically then by name, controllers
  by type, global middleware by `(order, type)`, summaries by path).
- No timestamps or random values are ever emitted.
- CI can enforce freshness with `git diff --exit-code` after a build.
