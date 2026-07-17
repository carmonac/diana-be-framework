# Changelog

## 0.9.0

- Version bump only (kept in lockstep with the workspace).

## 0.8.1

- Version bump only (kept in lockstep with the workspace).

## 0.8.0

- Discovers a `DianaObservability` provider and wires its observer into the
  server, scheduler, event bus and database, plus `/actuator/metrics`
  (compile-time gated) and always-on liveness/readiness routes. New
  diagnostics for duplicate/non-singleton observability providers.

## 0.7.0

- Scheduler emission forwards `perIsolate: true` from the annotation
  (omitted when false — byte-identical output for existing apps).

## 0.6.0

- `@Transactional` support: reads annotated methods (capturing full
  signatures), injects diana_data's `Database` into `@Repository`/service
  providers via a framework-injectable seam, opens/migrates/closes the
  connection in the context lifecycle, and emits `$Tx$X` proxy subclasses
  that wrap each transactional method in an ambient transaction. New
  connector-cardinality and `@Transactional` placement/signature
  diagnostics. Apps without data emit byte-identical output.

## 0.5.0

- `@Secured`/`@RolesAllowed` support: `SecurityInfo` captured on routes,
  controllers, WebSocket controllers and gRPC services (method replaces
  controller); guards from `diana_auth` (referenced by import URL only)
  appended last in HTTP route and WebSocket handshake middleware; a
  `grpcAuthInterceptor` wired from the app's `AuthenticationMiddleware`
  (server-wide). New diagnostics for empty roles, misplaced annotations
  and gRPC security. `@Principal` parameter binding via `bindPrincipal`.
  OpenAPI gains a bearer scheme and per-operation `security`. Apps without
  security emit byte-identical output.

## 0.4.0

- `@EventListener` support: listener methods are validated (signature,
  non-nullable class-typed event parameter, singleton scope) and
  registered on a `DianaEventBus` in the generated `DianaContext`
  constructor; `DianaEventPublisher` constructor parameters are satisfied
  by the context's bus; `runDiana` hands the bus to the runtime for the
  cross-isolate bridge. Apps without events emit byte-identical output.

## 0.3.0

- `@Consumes`/`@Produces` classification and emission: annotated routes
  decode through the request's codec registry and negotiate the response
  format; MIME sets are projected into the OpenAPI document.
- Body-codec discovery: singleton `BodyCodec` implementations are wired
  into `DianaServer(bodyCodecs: ...)` in the composition root.
- Server-Sent Events: `Stream<ServerSentEvent>` and `Stream<DTO>` route
  returns compile to `sseResponse(...)`; OpenAPI marks them
  `text/event-stream`. New diagnostics for unsupported stream shapes and
  invalid `@ResponseStatus`/`@Produces` combinations.
- `@GrpcService` support: validates the class extends a
  `package:grpc` `Service`, injects it as a singleton and wires a
  `DianaGrpcServer` into `DianaApp.grpcServer` (served on `initialize()`,
  stopped first on `dispose()`). Apps without gRPC services emit
  byte-identical output.

## 0.2.0

- Lifecycle wiring (`@PostConstruct`/`@PreDestroy`, `DianaApp` composition
  root, `DianaOverrides`).
- CORS, static files, multipart, `@Scheduled`, WebSocket handshake
  interceptors.
- Native JSON codecs (`@Json`/`@JsonField`) and OpenAPI 3 generation from
  the shared route-classification pass.

## 0.1.0

- Initial release: three-builder pipeline (metadata → part files →
  bootstrap), compile-time DI graph resolution with exact-message
  diagnostics, route adapters, validators, config binders.
