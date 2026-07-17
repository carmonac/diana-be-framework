# Diana — guidance for Claude Code

Diana is a Spring-inspired, annotation-driven backend framework for Dart.
Everything (DI, routing, validation, security, transactions) is resolved
**at compile time** by build_runner code generation — no reflection, no
runtime container. HTTP engine is **relic** (never shelf; the user
explicitly rejected it). Docs and code are in English; the user
communicates in Spanish.

## Monorepo layout (pub workspaces)

| Path | Role |
|---|---|
| `packages/diana_annotation` | const annotations only; deps: meta |
| `packages/diana` | runtime (server, pipeline, config, events, scheduler…) |
| `packages/diana_generator` | the 3 builders; depends ONLY on diana_annotation |
| `packages/diana_grpc` | gRPC add-on — the ONLY package importing `package:grpc` |
| `packages/diana_auth` | security add-on — the ONLY package importing `package:crypto` |
| `packages/diana_data` | persistence add-on (knex_dart) — the ONLY package importing `package:knex_dart` |
| `packages/diana_observability` | metrics/tracing add-on — the ONLY package importing `package:opentelemetry` |
| `examples/todo_api` | exercises everything HTTP (auth, events, XML, SSE…) |
| `examples/greeter_grpc` | gRPC + HTTP side by side (committed protoc output) |
| `examples/blog_api` | persistence dogfood (sqlite in-memory, hermetic) |

Three-builder pipeline: `diana_metadata` (per-library `.diana.json`
summaries) → `diana_part` (`.diana.dart` part files: route adapters,
validators, JSON codecs) → `diana_bootstrap` (aggregates summaries →
`.diana_app.dart` composition root). See `docs/architecture.md`.

## Hard conventions — never break these

1. **Analyzer code only in `packages/diana_generator/lib/src/readers/`.**
   Models (`model/summary.dart`), graph and emitters are plain data.
2. **Semantics live in tested runtime helpers; generated code is thin**
   (one-liner calls like `bindPathParam<T>(req, 'id')`).
3. **Byte-identical output for apps not using a feature.** Every new
   emission is conditional (see `usesEvents`/`usesData` gating and the
   `grpcServer` pattern in `bootstrap_builder.dart`). Verify with an
   absence test + zero `git diff` on the examples' generated files.
4. **Every diagnostic has an exact message and an exact-message test**
   (catalog: `docs/reference/build-diagnostics.md`).
5. **Boundary rules, enforced by walk-the-tree tests**: relic only in
   `diana/lib/src/adapter/relic_adapter.dart`; grpc only in diana_grpc;
   crypto only in diana_auth; knex_dart only in diana_data; the generator
   NEVER imports add-on packages — it references their types by import-URL
   string (`refer('X', 'package:diana_auth/diana_auth.dart')`).
6. **Generated part files resolve through the HOST library's imports** —
   they cannot reference add-on packages. Cross-package contracts live in
   `package:diana` (e.g. `principalAttributeKey`/`bindPrincipal` in
   `binding.dart`).
7. **Docs ship with the feature**: a guide in `docs/guides/` plus updates
   to the 5 references (annotations, runtime, generated-code,
   build-diagnostics, config-keys), `docs/README.md` index, root README
   and CHANGELOGs (root + per-package).
8. **Lockstep versioning**: all packages share one version; bump every
   pubspec + cross-package constraints + example constraints + doc
   snippets together.

## Commands

```bash
tool/verify.sh          # THE gate: pub get, codegen, analyze --fatal-infos,
                        # all test suites, determinism (build×2, byte-diff)
dart test               # per package/example (cd first)
dart run build_runner build   # regenerate an example (generated files are committed)
```

`analyze --fatal-infos` covers the whole workspace including `tool/`.

## Established patterns (reuse, don't reinvent)

- **New annotation**: class in `diana_annotation/lib/src/` + barrel export
  + add the NAME to `dianaAnnotationPattern` in `generator/lib/src/common.dart`
  (without this the builders skip the library) + a `TypeChecker` in
  `readers/checkers.dart`.
- **Method-level annotation on providers** (@Scheduled/@EventListener/
  @Transactional style): `_xOf(cls, scope)` reader → info class in
  `summary.dart` (omit-if-default JSON!) → carried on `InjectableInfo` →
  wired in `_injectableFrom` AND `_withLifecycle`.
- **Per-route metadata** (@CrossOrigin/@Secured style): read at method+class,
  `route.x ?? controller.x` resolution at emission.
- **Framework injectable** (DianaEventPublisher/Database style):
  `ResolvedDep.isX` flag + short-circuit in `di_graph.dart` matching
  `param.type.name` + `libraryUri` prefix, field on `DianaContext`.
- **Neutral observer contract** (observability style): when core/`diana_data`
  must be instrumented by an add-on they can't import, put an abstract
  no-op contract in `package:diana` (e.g. `DianaObserver` in `observer.dart`);
  runtime classes take an optional `observer`; the generator discovers the
  add-on provider by supertype and threads it in, gated for byte-identity.
- **Composable aspect pipeline** (@Timed/@Cacheable/@Retryable/
  @CircuitBreaker/@Transactional): ONE proxy subclass per provider class —
  `$Tx$X` kept verbatim when tx-only (byte-identity), `$Aspect$X` otherwise
  (`bootstrap_builder.dart` `_txOnlyProxy`/`_aspectProxy`). Semantics in
  `diana/lib/src/aspects.dart` runtime helpers; overrides nest one-liners
  in the FIXED order Timed→Cacheable→Breaker→Retry→Tx; per-method state as
  `_cache$m`/`_retry$m`/`_breaker$m` fields; `Code.scope` + `_typeCode` for
  allocator-prefixed types in string bodies; annotation `Type` lists read
  via `toListValue()`/`toTypeValue()` and emitted as `e is X` predicates.
  @Cacheable has a pluggable backend: a `DianaCacheStore` provider
  (discovered by supertype in core, patrón DianaObservability) swaps the
  `_cache$m` MethodCache field for a `static const _spec$m` CacheSpec routed
  through `_cacheStore.run(...)` — gated so store-less apps stay
  byte-identical; ctor slot order is observer?/cacheStore/db.
- **Discovery by supertype** (BodyCodec/HealthIndicator/AuthenticationMiddleware):
  scan `provider.info.supertypes` for name + library-prefix; singleton-scope
  check with the `'X implements Y but is <scope>-scoped'` message pattern.
- **Test harness**: generator tests run in-memory via
  `test/util/package_assets.dart` — REAL diana_annotation sources + same-URI
  FAKE stubs of diana/grpc/diana_auth. New runtime symbols used by emitted
  code need a stub there too.

## Codegen gotchas (they will bite)

- Stale AOT builder cache: after changing generator source, if a build
  emits old-format code, `rm -rf .dart_tool/build` at the **workspace
  root** (not the example's).
- Generated-output test matchers must be **allocator-prefix-agnostic**
  (`_i\d+\.`) and **dart_style-tolerant** (long lines split multiline with
  trailing commas) — use `matches(RegExp(...))`, not exact `contains`.
- Diana's `@Service` annotation collides with grpc's `Service` class if a
  fixture imports both unprefixed — mimic protoc (base class in its own
  library) in gRPC test fixtures.
- `DartObject.getField` does not traverse superclass fields — use the
  `(super)` walk helper (`_constField` in library_reader.dart).
- Python heredoc string-replace on Dart sources containing `\n` literals or
  `$` fails silently — prefer the Edit tool and grep-verify.
- The main isolate's `debugName` under `dart test` is a `file:` URI — don't
  split test payloads on `:`.

## Multi-isolate semantics (subtle, user-decided)

- `@Scheduled` runs **once per process** (leader-only; workers skip via
  `DianaRuntime.isWorkerIsolate`); `perIsolate: true` opts out. Supports
  `cron:` (6-field Spring, `CronExpression` in `diana/lib/src/cron.dart`,
  local time; re-armed after completion so no overlap). The generator can't
  import package:diana, so the reader only shape-checks cron (6 fields or
  macro); range errors surface at startup via `CronExpression.parse`.
- Event `broadcast()` bridges isolates hub-and-spoke, exactly-once each.
- gRPC serving and per-isolate state constraints: see
  `docs/guides/operations.md`.

## Decisions already made with the user — do not relitigate

- relic as HTTP engine; 100% compile-time DI; pub-workspaces monorepo.
- Add-ons live in separate packages (grpc/auth/data), never in core.
- knex_dart for persistence (NOT drift); driver-agnostic connector pattern.
- Auth: strategy chain, HS256 in-package, @Secured/@RolesAllowed guards.
- Events: sync/awaited local dispatch + cross-isolate broadcast.
- The user asks explicitly for commits — don't commit unprompted.
