# Changelog

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
