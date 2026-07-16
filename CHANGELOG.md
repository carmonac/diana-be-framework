# Changelog

## 0.7.0 — 2026-07-13

### @Scheduled: leader-only in multi-isolate serving (behavior fix)
- With `server.isolates > 1`, every isolate used to start its own
  scheduler, so a `@Scheduled` task ran once **per isolate**. Tasks now run
  once **per process**: only the main isolate starts them
  (`DianaScheduler` skips leader-only tasks when
  `DianaRuntime.isWorkerIsolate` is set by the worker entrypoint).
- Tasks that genuinely need to run in every isolate (e.g. refreshing an
  isolate-local cache) opt in with `@Scheduled(perIsolate: true)`.
- Single-isolate serving and embedded use (`buildDianaApp()` +
  `initialize()`) are unaffected; generated output is byte-identical for
  apps not using the new flag. Multi-**process** coordination (replicas)
  remains out of scope — a distributed-lock option via `diana_data` is on
  the roadmap.

## 0.6.0 — 2026-07-13

### Persistence (new `diana_data` package)
- Data access for Diana built on the `knex_dart` query builder — the only
  package depending on `knex_dart` (core), driver-agnostic and
  boundary-tested; the generator references it by import URL only, so apps
  without persistence emit byte-identical code.
- `Database` — an injectable query executor (`table`/`select`/`insert`/
  `update`/`delete`/`raw`) resolving the ambient transaction from the
  current `Zone` or the pooled connection. Injected into `@Repository`
  providers through a framework-injectable seam.
- `DatabaseConnector` — a user-subclassed provider that opens the driver
  connection (Postgres, SQLite, …) and owns its close; the driver package
  is the user's choice.
- **`@Transactional`** (Spring-style): the generator emits a `$Tx$X` proxy
  subclass wrapping each annotated method in an ambient transaction
  (`db.trx` + a `Zone`). Nesting joins the enclosing transaction as a
  savepoint (propagation REQUIRED); an uncaught exception rolls back and
  rethrows. Build errors for non-extendable classes, non-`Future` methods,
  misplaced annotations and missing/duplicate connectors.
- Lifecycle: the connection opens (and runs opt-in SQL migrations from
  `db.migrations.dir`) at the start of `initialize()` and closes at the end
  of `dispose()`. A `DatabaseHealthIndicator` feeds `/actuator/health`.
- New example `examples/blog_api` (SQLite in-memory): migrations, a
  repository, transactional service methods with commit/rollback, all
  hermetic (no external database).

## 0.5.0 — 2026-07-13

### Authentication & authorization (new `diana_auth` package)
- Spring Security analog in the optional `diana_auth` package — the only
  package depending on `package:crypto` (boundary-tested); it never imports
  `package:grpc`, and the generator references it by import URL only, so
  apps without security emit byte-identical code.
- Pluggable `Authenticator` strategies with three built-ins: **JWT Bearer**
  (in-package HS256 via `Hs256TokenVerifier` — exact-alg allowlist rejecting
  `none`/confusion, constant-time compare, exp/nbf skew, iss/aud checks;
  `TokenVerifier` seam for RS256/JWKS; `Hs256TokenSigner` for login
  endpoints), **HTTP Basic** (`UserStore`), and **API key** (`ApiKeyValidator`).
- `AuthenticationMiddleware` runs the strategy chain, stamps an
  `AuthPrincipal` under the `package:diana` `principalAttributeKey`
  contract, and challenges 401s. Assembled by subclassing (Spring's
  explicit filter chain).
- `@Secured()` (401) and `@RolesAllowed([...])` (403, any-of) on
  controllers/routes (method replaces controller); the generator appends a
  guard last in each route's middleware chain. `@Principal()` binds the
  identity into handler parameters via `bindPrincipal<T>` (added to
  `package:diana`). Misplaced or empty security annotations are build
  errors.
- Coverage across **HTTP**, **WebSocket handshakes** (guards as handshake
  interceptors) and **gRPC** (a `grpcAuthInterceptor` in `diana_grpc`,
  wired from the app's `AuthenticationMiddleware`; server-wide in v1).
- OpenAPI projects a `bearerAuth` scheme and per-operation `security` for
  secured routes.
- The `todo_api` example now dogfoods `diana_auth` (JWT + API key, a login
  endpoint, `@Secured`/`@RolesAllowed`/`@Principal`, secured WebSocket).

## 0.4.0 — 2026-07-13

### Application events
- Spring's `ApplicationEventPublisher` analog: annotate a method on any
  singleton provider with `@EventListener` (exactly one parameter — the
  event type — returning `void`/`Future<void>`) and it receives every
  published event whose type matches, subtypes included.
- Injectable `DianaEventPublisher` interface: `publish(event)` runs local
  listeners in registration order, awaited — errors propagate to the
  publisher (Spring's synchronous semantics); `broadcast(event)`
  additionally relays the event to every other isolate.
- **Cross-isolate bridge**: with `server.isolates > 1`, broadcast events
  are relayed hub-and-spoke through the main isolate and delivered
  exactly once per isolate — the built-in answer to multi-isolate
  coordination. Broadcast events must be plain data; unsendable events
  fail fast with a clear `ArgumentError` before local dispatch.
- Listeners are registered in the generated `DianaContext` constructor
  (publishing from `@PostConstruct` is delivered) via lazy closures (no
  eager provider construction). Apps without events emit byte-identical
  code.
- `DianaEventBus` is constructible directly in tests (`on<T>()`,
  `publish`, `dispatchRemote`, `onError`).

## 0.3.0 — 2026-07-13

### Content negotiation
- Pluggable `BodyCodec` interface (Spring `HttpMessageConverter` analog):
  decode/encode between a wire format and the `Map`/`List`/scalar
  representation the DTO pipeline already consumes. Codecs are ordinary DI
  singletons, discovered through the graph and wired into the server.
- `XmlCodec` included (`application/xml`, `text/xml`) with a documented
  Map↔XML convention; enable with
  `@Component() class AppXmlCodec extends XmlCodec {}`.
- `@Consumes`/`@Produces` on controllers or routes (method replaces
  controller; the annotated set replaces the JSON default). 415 for
  unlisted or codec-less content types, 400 for malformed bodies, 406 when
  nothing in `produces` is acceptable — server preference order. MIME sets
  are projected into the OpenAPI document.
- New helpers: `decodeMapBody`/`decodeListBody`/`negotiatedResponse`; the
  codec registry travels on `DianaRequest.codecs`.

### Server-Sent Events
- Routes returning `Stream<ServerSentEvent>` or `Stream<Dto>` (DTO with
  `toJson()`) become SSE endpoints: 200 `text/event-stream`,
  spec-compliant framing (`id:`/`event:`/`retry:`/multi-line `data:`),
  `cache-control: no-cache`.
- Keep-alive heartbeats every `server.sse.heartbeatSeconds` (default 15,
  `0` disables); client disconnect cancels the source stream.
- `DianaResponse.stream(...)`/`bodyStream` for arbitrary chunked
  responses; stream bodies bypass the engine's buffered response path and
  are written unbuffered (socket hijack + chunked framing) so events flush
  immediately.
- OpenAPI documents SSE routes as `text/event-stream`.

### gRPC
- New package `packages/diana_grpc` — the only Diana package depending on
  `package:grpc` (boundary-tested); HTTP-only apps carry no gRPC
  dependency.
- `@GrpcService()` on a class extending a protoc-generated `XServiceBase`:
  joins the DI graph as a singleton and is served by the generated
  `DianaApp.grpcServer` next to HTTP (started on `initialize()`, stopped
  first on shutdown, waiting for in-flight calls).
- Config keys `grpc.enabled` (default `true`), `grpc.host`, `grpc.port`
  (default 9090). Single-isolate only: `serve()` fails fast when
  `server.isolates > 1`.
- New example `examples/greeter_grpc` (gRPC + HTTP side by side, committed
  protoc output, end-to-end tests).

### Tooling & docs
- `tool/verify.sh` covers the new package and example (tests +
  determinism for both examples).
- New guides: content negotiation, Server-Sent Events, gRPC; reference
  docs updated (annotations, runtime, generated code, build diagnostics,
  config keys); per-package CHANGELOGs added.

## 0.2.0 — 2026-07-12

### Core & lifecycle
- `@PostConstruct`/`@PreDestroy` lifecycle hooks (singleton providers), run
  in (reverse) dependency order by the generated
  `DianaContext.initialize()`/`dispose()`.
- Generated `DianaApp` (`context` + `server` + lifecycle) with
  `buildDianaApp()`; `buildDianaServer`/`buildDianaContext` gained an
  `overrides` parameter and kept their signatures.
- `DianaOverrides`: per-provider test overrides (Spring `@MockBean` analog).
- `DianaRuntime.run`: graceful shutdown on SIGINT/SIGTERM (drains in-flight
  requests, then `@PreDestroy`), programmatic shutdown trigger for tests.
- Request scope exercised end-to-end (fresh instances per request).

### Web
- CORS: global `server.cors.*` config, `@CrossOrigin` per controller/route
  (full-policy replacement), automatic OPTIONS preflight routes.
- Static files via the engine's hardened handler: `server.static.*`
  (prefix, index, SPA fallback, cache headers).
- Multipart/urlencoded uploads: `@Body() FormData` with `UploadedFile`s,
  in-memory with `server.multipart.maxSize` guard (413).
- Raw text bodies: `@Body() String`.
- Minimal content negotiation: incompatible `Accept` → 406 (`*/*` passes).
- HTTPS (`server.ssl.certPath`/`keyPath`/`keyPassword`) and experimental
  multi-isolate serving (`server.isolates`, Diana-managed workers).
- WebSocket handshake interceptors: `@UseMiddleware` on
  `@WebSocketController` guards the upgrade; request attributes propagate
  into `WebSocketSession.attributes`.

### Config & JSON
- Profiles: `DIANA_PROFILE` env (comma-separated) overlays
  `application-{profile}.yaml` in order.
- Typed list config values (`get<List<String>>`, …) from YAML lists or
  comma-separated env vars; `section(prefix)`.
- Native JSON codegen: `@Json`/`@JsonField` generate `$XFromJson`/`$XToJson`
  — zero DTO boilerplate; route adapters use them automatically. Convention
  and json_serializable DTOs keep working. DTO shape mismatches are 400s.

### Platform
- OpenAPI 3 document generated at build time from routes, DTOs and
  validation constraints; served at `GET /openapi.json` when
  `server.openapi.enabled` (title/version patched from config).
- Actuator-style endpoints (`management.enabled`): `/actuator/health`
  (aggregating `HealthIndicator` components, 503 when down) and
  `/actuator/info` (nested `info.*` config).
- `@Scheduled(fixedRate:/fixedDelay:/initialDelay:)` tasks on singleton
  providers, started after initialization, stopped on shutdown (overlap-safe).

### Tooling
- `tool/verify.sh` now enforces byte-identical rebuilds (determinism).
- Architectural test pinning the HTTP engine to the adapter file.

## 0.1.0 — 2026-07-12

Initial release: compile-time DI, REST controllers with param/body binding
and validation, middleware, YAML/env configuration,
`@ControllerAdvice` exception mapping, WebSockets, complete example and
documentation.
