# Architecture

How Diana works inside. Useful for contributors and for anyone who wants
to understand exactly what happens between annotating a class and serving
a request.

## Design principles

1. **Compile time over runtime.** Anything that can fail — dependency
   resolution, binding compatibility, JSON contracts, handler signatures —
   is checked during code generation. The runtime contains no resolution
   logic, no maps of types, no reflection.
2. **Generated code is thin; semantics live in the runtime.** Adapters and
   validators are one-liners calling tested runtime helpers
   (`bindQueryParam`, `checkNotBlank`, …). This keeps generated diffs small
   and the behaviour centrally testable.
3. **The HTTP engine is a detail.** [relic](https://pub.dev/packages/relic)
   provides the server lifecycle, trie router and path-parameter
   extraction. It is confined to a single adapter file; a test greps the
   runtime package to enforce that nothing else imports it.
4. **Deterministic output.** Same input, byte-identical output — sorted
   emission everywhere, no timestamps. Enables `git diff --exit-code`
   freshness checks.

## Package layout

```
packages/
├── diana_annotation    # const annotation classes; deps: meta only
├── diana               # runtime; deps: relic, yaml, xml; re-exports annotations
├── diana_generator     # builders; deps: analyzer, build, source_gen,
│                       # code_builder, dart_style, diana_annotation
│                       # (NOT diana — keeps relic out of the build chain)
├── diana_grpc          # gRPC runtime; deps: diana, grpc — the ONLY
│                       # package importing package:grpc
├── diana_auth          # security; deps: diana, crypto — the ONLY
│                       # package importing package:crypto
├── diana_data          # persistence; deps: diana, knex_dart — the ONLY
│                       # package importing package:knex_dart
└── diana_observability # metrics/tracing; deps: diana, opentelemetry —
                        # the ONLY package importing package:opentelemetry
```

`diana_generator` depends only on `diana_annotation`, so the build-time
transitive closure stays free of the HTTP stack. Boundary rules enforced by
tests: `package:relic` is imported only by
`diana/src/adapter/relic_adapter.dart`; `package:grpc` only by `diana_grpc`;
`package:crypto` only by `diana_auth`; `package:knex_dart` only by
`diana_data`; `package:opentelemetry` only by `diana_observability`; and the
generator imports none of the add-ons (it references
`DianaGrpcServer`, `SecuredGuard`, `Database`, the `$Tx$` proxies etc. by
import-URL string, so apps depend only on the add-ons they use).

## The build pipeline

Three builders, declared in `packages/diana_generator/build.yaml` with
`auto_apply: dependents` (users only add the package to
`dev_dependencies`):

```
lib/foo.dart ──▶ diana_metadata ──▶ foo.diana.json      (cache, hidden)
lib/foo.dart ──▶ diana_part     ──▶ foo.diana.dart      (source, part file)
lib/app.dart ──▶ diana_bootstrap──▶ app.diana_app.dart  (source, library)
                       ▲
                       └── reads every *.diana.json in the package
```

Phase ordering is guaranteed by `runs_before` +
`required_inputs: ['.diana.json']` on the bootstrap builder.

### 1. `diana_metadata` — per-library summaries

For each library, a cheap regex pre-check (does the source even mention a
Diana annotation?) avoids resolving irrelevant files. Annotated libraries
are resolved with the analyzer and read into a **plain-data
`LibrarySummary`** (`src/model/summary.dart`): injectables (with scope,
qualifier, `as:` binding, supertypes and constructor parameters as
serializable `TypeRef`s), controllers and routes, global middleware,
advices and the `@DianaApplication` entry. The summary is written as JSON
to the build cache.

`TypeRef = {libraryUri, name, typeArgs, nullable}` — its `key` (nullability
excluded) is the identity used for provider matching, which is why
fully-instantiated generic dependencies match structurally.

### 2. `diana_part` — per-library code

Emits the part file: route adapters, validators, config binders (see the
[generated-code reference](reference/generated-code.md)). All *local*
build-time validation lives here so errors carry exact source spans:
binding annotation rules, `fromJson`/`toJson` contract checks, constraint
applicability, the missing-`part`-directive error.

Part files were chosen over standalone libraries for local artifacts
because they share the host library's imports — generated code references
user types exactly as written, with zero import management. The trade-off
(users must write one `part` line) is softened by an error message
containing the exact line to paste.

### 3. `diana_bootstrap` — the aggregator

Runs on the `@DianaApplication` library only:

1. Collects every `.diana.json` (sorted by path for determinism).
2. **Resolves the graph** (`src/graph/di_graph.dart` — pure functions over
   summaries, no analyzer, no build system): indexes strong bindings (self
   type, `as:`) and auto-binding candidates (supertypes); resolves each
   constructor parameter; Kahn topological sort; DFS cycle extraction for
   readable cycle paths; scope analysis (request-reachability); every
   problem accumulated and reported together.
3. Validates middleware references (injectable, implements `Middleware`,
   singleton) and entrypoint uniqueness.
4. **Emits** with `code_builder` (its prefixing allocator manages imports
   across arbitrary user libraries) + `dart_style`: `DianaContext`,
   optional `DianaRequestScope`, `_mapException` (advice chain ordered by
   exception-type specificity, computed as supertype-chain depth at
   metadata time), `buildDianaContext`, `buildDianaServer`, `runDiana`.

### Why summaries instead of resolving everything in the aggregator?

Incrementality and cost: `build_runner` re-runs the metadata builder only
for changed libraries; the aggregator reads tiny JSON files instead of
re-resolving the whole package. The plain-data boundary also isolates
analyzer API churn (a historically unstable API) to the `readers/`
directory — graph logic and emitters never see analyzer types.

## The runtime pipeline

```
relic (trie router, HTTP server)
  └─ RelicAdapter: relic Request → DianaRequest, DianaResponse → relic Response
       └─ error boundary (ValidationException → 400, advice chain,
          HttpException → status, else opaque 500)
            └─ middleware chain: global → controller → route
                 └─ generated adapter: bind → validate → invoke → serialize
                      └─ your method
```

Composition happens once, at route-registration time (`DianaServer.
register` folds the chain into a single `DianaHandler`); nothing is looked
up per request. Diana composes middleware itself rather than using the
engine's mechanism so that the three-level ordering is deterministic and
middleware get DI.

Two pieces of server state travel **on the request** rather than being
read from configuration by generated code: `DianaRequestLimits` and the
`BodyCodecRegistry` (discovered `BodyCodec` singletons). This keeps the
generated adapter signature at `(controller, request)` and generated code
free of config lookups.

WebSocket endpoints bypass the HTTP pipeline: the adapter answers the
handshake with the engine's upgrade result and pumps the socket's event
stream into the handler's `onOpen`/`onMessage`/`onError`/`onClose`
callbacks, wrapping the engine socket in Diana's `WebSocketSession`.

Streamed responses (`DianaResponse.bodyStream`, used by SSE) also bypass
the engine's response path: `dart:io` buffers small writes, which would
hold SSE events back, so the adapter hijacks the socket (relic's `Hijack`
result) and writes the HTTP/1.1 head plus chunked frames itself —
unbuffered, with client disconnects propagated as a cancel of the source
stream.

gRPC services don't route through this pipeline at all: `DianaGrpcServer`
(package `diana_grpc`) runs `package:grpc`'s own server on a separate
port, sharing only the DI graph, configuration and lifecycle
(served on `initialize()`, shut down first on `dispose()`).

Security (package `diana_auth`) reuses the middleware pipeline rather than
adding a new mechanism: an `AuthenticationMiddleware` establishes the
principal in `request.attributes`, and `@Secured`/`@RolesAllowed` compile
to guard middleware the bootstrap appends **last** in each route's chain
(after authentication, before the handler). The principal-attribute
contract (`principalAttributeKey` + `bindPrincipal`) lives in
`package:diana` so generated part-file adapters read it without importing
`diana_auth`. gRPC — which has no request-attribute channel — is covered
by a `package:grpc` interceptor the bootstrap wires from the same
`AuthenticationMiddleware`.

Persistence (package `diana_data`) follows the same add-on shape: the
generator emits a `Database` field on the context (opened/closed with the
lifecycle) and, for `@Transactional` methods, a `$Tx$` proxy subclass that
wraps the call in an ambient transaction bound to the current `Zone`.
`knex_dart` never reaches the core; the driver package is the user's.

## Testing strategy (the framework's own)

- **Graph logic**: table-driven tests over hand-built summaries, asserting
  exact error strings — diagnostics are a feature, message regressions are
  test failures.
- **Builders**: `build_test`'s `testBuilder`/`testBuilders` with in-memory
  sources. Real `diana_annotation` sources are loaded into the in-memory
  file system; `package:diana` is stubbed with same-URI fakes so the build
  harness never needs relic.
- **Runtime**: unit tests for config, binding, validation, pipeline
  ordering and short-circuiting, exception boundary, and adapter mapping
  (served on ephemeral ports).
- **End-to-end**: the `examples/todo_api` suite boots the generated server
  and exercises every HTTP feature (including XML negotiation and SSE over
  a raw socket); `examples/greeter_grpc` does the same for gRPC with a
  protoc-generated client.
- **Boundary tests**: fail if `package:relic` leaks outside the adapter or
  `package:grpc` outside `diana_grpc`.
- **Determinism**: build twice, compare checksums (both examples).

Run everything with `tool/verify.sh`.

## Extension points and future work

- The `RelicAdapter` boundary makes engine upgrades (relic 2.x) or
  alternative engines a single-file change.
- `BodyCodec` is the format extension point: implement it on a singleton
  and annotate routes with `@Consumes`/`@Produces` — no generator changes
  needed.
- Planned: cross-package component scanning (summaries already carry
  library URIs), DI-discovered gRPC interceptors, TLS for the gRPC
  listener, multi-isolate gRPC serving.
