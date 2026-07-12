# Changelog

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
