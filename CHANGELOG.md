# Changelog

## 0.14.0 — 2026-07-17

### STOMP 1.2 over WebSockets
- Declare a singleton `@WebSocketController` extending `StompEndpoint` and
  Diana speaks STOMP 1.2 on it — an in-memory topic broker built into
  `package:diana` (no extra dependency), reusing the existing WebSocket
  handshake (so `@UseMiddleware`/`@Secured` authenticate STOMP too).
- `@MessageMapping('/dest')` methods handle client SENDs to
  `<stomp.appPrefix>/dest` (default `/app`); the payload is a `String` or an
  `@Json` DTO, with an optional `StompMessage` context parameter (headers,
  session, principal). A non-void return is published to the `@SendTo`
  destination. Inject `StompPublisher` to publish from server code.
- Full protocol: CONNECT/CONNECTED with version + heartbeat negotiation,
  SUBSCRIBE/UNSUBSCRIBE (ack modes auto/client/client-individual), SEND,
  MESSAGE, ACK/NACK (cumulative or individual; NACK drops + logs — no
  redelivery), BEGIN/COMMIT/ABORT transactions, RECEIPT, ERROR + close on
  protocol violations, and negotiated heartbeats.
- Topic publishes fan out across isolates exactly once through the event-bus
  broadcast machinery. Every mapping rule is validated at build time with
  exact diagnostics. Apps without STOMP emit byte-identical output.
- `examples/todo_api` dogfoods a secured STOMP chat gateway with an
  end-to-end test over a raw WebSocket client.

## 0.13.0 — 2026-07-17

### Spring-Data-style query methods
- Declare an **abstract** `@Repository` class extending the new
  `DianaRepository<E>` (in `diana_data`) and Diana generates its
  implementation: `findAll`/`findById`/`save`/`deleteById` plus every
  abstract method derived from its **name** — `findByTitle`,
  `findFirstByPostIdAndAuthor`, `countByPostId`, `existsByAuthor`,
  `deleteByPostId`, `findByBodyContainsOrderByIdDesc`, ...
- Full derived-query grammar: equality, `Not`, `GreaterThan(Equal)`,
  `LessThan(Equal)`, `Like`, `Contains`/`StartsWith`/`EndsWith`,
  `In`/`NotIn`, `Between`, `IsNull`/`IsNotNull`; `And` **or** `Or`
  connectors (one per method); chainable trailing
  `OrderBy<Property>Asc|Desc`. Everything is parsed and type-checked at
  build time with exact diagnostics (unknown properties, arity/type
  mismatches, wrong return shapes).
- Entities are `@Json` classes annotated with the new `@Table('name')`;
  columns are the fields' JSON keys (`@JsonField(name:)` doubles as the
  column override) and rows map through the generated `$EFromJson`.
  `save()` inserts `toJson` minus null entries, so a nullable `id` field
  autoincrements.
- Generated `$Repo$X` implementations run through the existing `Database`
  facade — repository calls join the ambient `@Transactional` transaction.
  Apps without query repositories emit byte-identical output.
- `examples/blog_api` dogfoods the whole grammar against sqlite (a new
  `comments` table + migration).

## 0.12.0 — 2026-07-17

### Cron expressions for @Scheduled
- `@Scheduled(cron: '...')` runs a task on a cron schedule alongside the
  existing `fixedRate`/`fixedDelay` triggers (exactly one is required). Six
  fields, Spring style (`second minute hour day-of-month month
  day-of-week`), with ranges, lists, `*/step`, three-letter month/day names
  and the macros `@yearly`/`@monthly`/`@weekly`/`@daily`/`@hourly`.
- A dependency-free `CronExpression` parser in `package:diana`
  (`parse`/`nextAfter`), evaluated in the process's local time — pin the
  schedule with `TZ`. The next occurrence is computed after the previous run
  completes, so cron runs never overlap. Cron tasks are leader-only by
  default like the other schedules.
- The expression's shape is validated at build time (exact diagnostic for a
  wrong field count / unknown macro); per-field range errors surface at
  startup. Apps without cron emit byte-identical output.

## 0.11.0 — 2026-07-17

### Pluggable @Cacheable store
- New `DianaCacheStore` contract in `package:diana`: declare exactly one
  singleton provider extending it and every `@Cacheable` method routes
  through it instead of the built-in per-isolate cache — the seam for
  Redis/memcached/shared backends, driver-agnostic (no new dependency).
- Wrap-style contract (`Future<V> run<V>(CacheSpec spec, List<Object?> key,
  Future<V> Function() miss)`): the store owns lookup, populate,
  single-flight, TTL, eviction and value serialization; `CacheSpec` carries
  the method name (for key namespacing) plus the annotation's ttl/maxEntries.
- `InMemoryCacheStore` exposed as the default backend, so custom stores can
  delegate to it (logging, metrics, local-then-remote tiers).
- Discovered by supertype and wired into the `$Aspect$X` proxy only when
  present (a `DianaCacheStore` field + a `static const CacheSpec` per cached
  method); apps without a store keep the built-in `MethodCache` emission
  byte-for-byte. Build diagnostics for duplicate or non-singleton stores.
- `examples/blog_api` dogfoods a custom store that delegates to the
  in-memory default.

## 0.10.0 — 2026-07-17

### Compile-time aspects (Spring AOP without reflection)
- Four new method-level annotations on `@Service`/`@Component`/
  `@Repository` providers — **`@Timed`**, **`@Cacheable`**,
  **`@Retryable`**, **`@CircuitBreaker`** — composed with `@Transactional`
  through a generalized generated-proxy pipeline (`$Aspect$X`), always in
  the fixed order Timed → Cacheable → CircuitBreaker → Retryable →
  Transactional (cache hits skip everything below; each retry runs in a
  fresh transaction; the breaker guards a whole retry budget).
- Runtime semantics live in tested `package:diana` helpers: `runTimed`,
  `MethodCache` (per-isolate TTL+LRU, single-flight, errors never cached),
  `RetryPolicy` (fixed backoff, exception-type filter) and
  `CircuitBreakerPolicy` (open/half-open/closed, `CircuitOpenException`).
- `@Timed` reports through the neutral `DianaObserver.observeTimedMethod`
  hook: with `diana_observability` present it feeds
  `diana_method_duration_seconds{method}`,
  `diana_method_calls_total{method,result}` and a `method.<name>` trace
  span — without it, a silent no-op.
- Exact build diagnostics for placement, signatures (Future-returning,
  public instance, non-generic/non-void for `@Cacheable`) and value ranges.
- Transactional-only classes keep emitting the `$Tx$X` proxy byte-for-byte;
  apps using no aspects are byte-identical. Generic aspect methods now
  re-declare their type parameters on the generated override (previously a
  generic `@Transactional` method produced non-compiling code).
- `examples/blog_api` dogfoods the pipeline: a cached+timed stats endpoint,
  a flaky retry+transaction write committing exactly once, and a
  circuit-broken endpoint.

## 0.9.0 — 2026-07-17

### Request body size limit (security hardening)
- New `server.maxBodyBytes` config key (default 10 MiB): all request
  bodies read through `DianaRequest` — JSON, urlencoded forms, raw
  `@Body String`, custom codecs — are now capped, returning **413** when
  exceeded. Enforcement is streaming: an oversized declared
  `Content-Length` is rejected before the body is read, and chunked bodies
  are cut off as soon as the count passes the cap — an oversized body is
  never fully buffered. `multipart/form-data` keeps its own key,
  `server.multipart.maxSize`, which now bounds the raw stream (part
  headers included). Setting either key to `0` disables that cap.

### Multi-isolate startup hardening (behavior fix)
- Startup is now fail-closed: if a worker fails to spawn or the main
  isolate's `initialize()`/bind throws, `DianaRuntime.run` shuts down the
  already-spawned workers before rethrowing instead of leaking live
  serving isolates with no coordinator.
- Workers no longer serve during the startup window: they bootstrap and
  `initialize()` when spawned but bind the shared socket only after every
  worker exists and the main isolate has initialized, so an early request
  can no longer trigger a broadcast that reaches an uninitialized main
  context or misses a not-yet-spawned sibling (restores the documented
  exactly-once delivery from the very first request).

### Remaining audit follow-ups
- Shutdown now drains in-flight cross-isolate event dispatches (on the main
  isolate and in workers) before `dispose()`, so a listener mid-run never
  sees its dependencies torn down; `dispatchRemote` also tolerates listeners
  registered mid-dispatch.
- Hijacked streaming responses send a real reason phrase per status code,
  and CR/LF in application-supplied header values is stripped (no header
  injection through the manually framed head).
- Documented the ambient-transaction caveat: database work fired and
  forgotten inside `@Transactional` outlives the transaction and fails
  loudly — always `await` it (persistence guide).

### Migration runner: robust SQL statement splitting
- `diana_data` now splits migration files on top-level `;` only —
  single-quoted strings (with `''` escapes), double-quoted identifiers and
  `--` / `/* */` comments may contain semicolons without fragmenting a
  statement. Dollar-quoted (Postgres) and trigger `BEGIN … END` (SQLite)
  bodies remain unsupported (documented in the persistence guide).

## 0.8.1 — 2026-07-17

### Hardening (adversarial-review fixes)
- **Auth**: malformed-but-signed claims now reject cleanly as 401 instead of
  crashing to 500 (numeric `sub` is accepted, other non-string shapes
  reject; non-finite `exp`/`nbf` reject) — and a present but non-numeric
  `exp`/`nbf` is **rejected instead of silently skipped** (was fail-open:
  such a token never expired).
- **Multi-isolate shutdown never hangs**: a worker whose dispose throws is
  reported (with its stack) instead of deadlocking the process; a worker
  that hangs is killed after `DianaRuntime.workerShutdownTimeout`; a worker
  isolate that dies is detected (`onExit`/`onError`), logged, and skipped
  by the event relay and shutdown. An erroring `shutdownTrigger` still
  shuts down.
- **Scheduler**: `fixedDelay` re-arms no longer leak a `Timer` per run;
  a task throwing synchronously lands in `onError` instead of killing the
  isolate.
- **HTTP**: multipart text fields are UTF-8 decoded (was Latin-1 mojibake;
  invalid UTF-8 is a 400); a zero-length chunk no longer terminates chunked
  streaming responses; an SSE source error now closes the stream and stops
  the heartbeat (was a timer/socket leak); CORS responses for denied or
  absent origins carry `Vary: Origin` (shared-cache safety).
- **Events**: a listener registering another listener mid-dispatch no
  longer throws `ConcurrentModificationError`; failed dispatches are still
  counted by the observer.
- **Data**: `migrate()` is leader-only, like `@Scheduled` — with
  multi-isolate serving a shared database is migrated exactly once.

## 0.8.0 — 2026-07-17

### Observability (new `diana_observability` package)
- In-package Prometheus metrics served at `/actuator/metrics` (0.0.4 text
  format, no dependency): automatic HTTP (by route template, with the final
  status), database, scheduler and event series, plus process RSS — and an
  injectable `MeterRegistry` for application metrics.
- OpenTelemetry tracing (opt-in via `observability.tracing.endpoint`): a
  server span per request continuing an inbound W3C `traceparent`, child
  spans per database operation, OTLP export. The only package depending on
  `package:opentelemetry` (boundary-tested); tracing is Beta upstream.
- Kubernetes-style probes in the core: `/actuator/health/liveness` (trivial
  UP) and `/actuator/health/readiness` (indicator aggregate); the existing
  `/actuator/health` is unchanged.
- Neutral `DianaObserver` contract in `package:diana` (no dependency on the
  add-on): `DianaServer`, `DianaScheduler`, `DianaEventBus` and (via
  `diana_data`) `Database` take an optional observer, wired by the generator
  when a `DianaObservability` provider is present. Apps without it emit
  byte-identical code (bar the always-on liveness/readiness routes).
- `examples/blog_api` scrapes real metrics; new build diagnostics for
  duplicate or non-singleton observability providers.

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
