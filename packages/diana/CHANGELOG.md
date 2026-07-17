# Changelog

## 0.11.0

- New pluggable `@Cacheable` backend contract in `aspects.dart`:
  `DianaCacheStore` (wrap-style `run<V>(spec, key, miss)`), `CacheSpec`,
  and `InMemoryCacheStore` (the exposed per-isolate default).

## 0.10.0

- New aspect runtime (`aspects.dart`): `runTimed`, `MethodCache`
  (TTL+LRU, single-flight, errors never cached), `RetryPolicy`,
  `CircuitBreakerPolicy` and `CircuitOpenException` — the helpers behind
  the generated `$Aspect$X` proxies. `DianaObserver` gains the
  `observeTimedMethod` no-op hook.

## 0.9.0

- Request body size limit: `server.maxBodyBytes` (default 10 MiB) caps
  every non-multipart body read through `DianaRequest` with streaming
  enforcement (413); `server.multipart.maxSize` now bounds the raw
  multipart stream, part headers included.
- Shutdown drains in-flight remote-event dispatches before `dispose()`;
  `dispatchRemote` tolerates listeners registered mid-dispatch. Hijacked
  streaming responses send a real reason phrase and strip CR/LF from
  header values.
- Multi-isolate startup is coordinated and fail-closed: no isolate serves
  until all are initialized, and a startup failure shuts down
  already-spawned workers before rethrowing.

## 0.8.1

- Multi-isolate shutdown never hangs: worker dispose failures are reported,
  hung workers are killed after `DianaRuntime.workerShutdownTimeout`, dead
  worker isolates are detected and skipped. Scheduler: no more `Timer` leak
  on `fixedDelay` re-arms; synchronous task throws reach `onError`.
  Multipart fields decode as UTF-8; zero-length chunks no longer truncate
  streamed responses; SSE source errors stop the heartbeat; denied CORS
  responses carry `Vary: Origin`; the event bus tolerates listeners
  registered mid-dispatch.

## 0.8.0

- Added the neutral `DianaObserver` contract (`observer.dart`) and threaded
  an optional `observer` through `DianaServer`, `DianaScheduler` and
  `DianaEventBus`; `DianaScheduler.schedule` gained `name`. New
  `livenessEndpointHandler`/`readinessEndpointHandler`.

## 0.7.0

- `DianaScheduler.schedule` gains `perIsolate` (default `false`): with
  multi-isolate serving, leader-only tasks are skipped in worker isolates
  so a schedule runs once per process. New `DianaRuntime.isWorkerIsolate`
  (set before a worker's bootstrap runs).

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
