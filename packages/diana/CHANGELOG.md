# Changelog

## 0.6.0

- Version bump only (kept in lockstep with the workspace; `diana_data`
  builds on this release).

## 0.5.0

- Added `principalAttributeKey` and `bindPrincipal<T>(DianaRequest)` to
  `binding.dart` — the cross-package contract used by `diana_auth`'s
  authentication middleware and by generated `@Principal()` adapters.

## 0.4.0

- **Application events**: `DianaEventPublisher` (injectable interface) and
  `DianaEventBus` — awaited local dispatch in registration order with
  subtype matching (`publish`), plus `broadcast` for cross-isolate
  delivery.
- `DianaRuntime` bridges broadcast events hub-and-spoke across worker
  isolates (exactly-once per isolate); `DianaRunnable` gains an optional
  `eventBus`. Unsendable broadcast events fail fast with `ArgumentError`.

## 0.3.0

- **Content negotiation**: pluggable `BodyCodec` interface with a
  `BodyCodecRegistry`; codecs are discovered through DI (any singleton
  implementing `BodyCodec`). New helpers `decodeMapBody`/`decodeListBody`
  (415/400 semantics) and `negotiatedResponse` (Accept-driven, 406 via
  `NotAcceptableException`).
- **XML out of the box**: `XmlCodec` (`application/xml`, `text/xml`) with a
  documented Map↔XML convention — register it with
  `@Component() class AppXmlCodec extends XmlCodec {}`.
- **Server-Sent Events**: `ServerSentEvent` (+ `.json`), spec-compliant
  encoder (`encodeSse`, id/event/retry/multi-line data, heartbeats) and
  `sseResponse`. Streamed responses use `DianaResponse.stream` with a new
  `bodyStream` field; the relic adapter serves them over a hijacked socket
  with chunked framing so events flush immediately.
- New config key `server.sse.heartbeatSeconds` (default 15, `0` disables).
- `DianaRequest` now carries the codec registry (`codecs`) alongside
  `limits`.

## 0.2.0

- Application lifecycle: `@PostConstruct`/`@PreDestroy`, `DianaApp`,
  `DianaRuntime.run` with graceful shutdown, `DianaOverrides` for tests.
- Configuration profiles, typed lists and `section()`.
- HTTPS (TLS) and experimental multi-isolate serving.
- CORS (`@CrossOrigin`, global config, automatic preflight).
- Static file serving with SPA fallback.
- Multipart uploads, raw `String` bodies and 406 Accept negotiation.
- Native JSON codegen (`@Json`/`@JsonField`).
- OpenAPI 3 document generation and `/openapi.json`.
- Actuator endpoints `/actuator/health` and `/info`.
- `@Scheduled` tasks (fixedRate/fixedDelay).
- WebSocket handshake interceptors.

## 0.1.0

- Initial release: compile-time DI, controllers/routing on relic,
  parameter/body binding, DTO validation, middleware chains, configuration,
  `HttpException` hierarchy with `@ControllerAdvice`, WebSocket support.
