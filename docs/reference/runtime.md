# Runtime API reference

Every public symbol of `package:diana/diana.dart` (which also re-exports
the [annotations](annotations.md)).

---

## HTTP model

### `enum HttpMethod`

`get, head, post, put, delete, patch, options`

- `static HttpMethod parse(String name)` — parses a case-insensitive
  method name; throws `ArgumentError` for unknown methods.

### `DianaRequest`

Diana's view of an incoming request. Handlers, middleware and advices only
ever see this type.

```dart
DianaRequest({
  required HttpMethod method,
  required Uri uri,
  Map<String, String> pathParameters = const {},
  Map<String, List<String>> headers = const {},
  Future<String> Function()? bodyReader,
})
```

Directly constructible — useful in unit tests.

| Member | Description |
|---|---|
| `HttpMethod method` | Request method. |
| `Uri uri` | Requested URI (path + query). |
| `String path` | Path component, always starting with `/`. |
| `Map<String, String> pathParameters` | Router-extracted `:name` segments. |
| `Map<String, String> queryParameters` | Single-valued query parameters. |
| `Map<String, List<String>> queryParametersAll` | Multi-valued query parameters. |
| `String? header(String name)` | First value of a header, case-insensitive; `null` when absent. |
| `List<String> headerAll(String name)` | All values of a header. |
| `Future<String> readBodyAsString()` | Reads the body; the first read is cached, so multiple readers (middleware + binding) are safe. |
| `Map<String, Object?> attributes` | Per-request bag for middleware → handler communication. |
| `BodyCodecRegistry codecs` | Registered body codecs (JSON always available) — consulted by the `@Consumes`/`@Produces` helpers. Stamped by the server, like `limits`. |

### `DianaResponse`

Immutable response value. Route methods usually return DTOs and let the
generated adapter build one; return a `DianaResponse` for full control.

| Constructor | Produces |
|---|---|
| `DianaResponse({statusCode = 200, headers, bodyText, bodyBytes, mimeType})` | fully manual |
| `DianaResponse.json(Object? data, {statusCode = 200, headers})` | `jsonEncode(data)`, `application/json` |
| `DianaResponse.text(String body, {statusCode = 200, headers})` | `text/plain` |
| `DianaResponse.noContent({headers})` | `204`, empty body |
| `DianaResponse.bytes(List<int> body, {statusCode = 200, mimeType = 'application/octet-stream', headers})` | binary |
| `DianaResponse.stream(Stream<List<int>> body, {statusCode = 200, mimeType = 'application/octet-stream', headers})` | streaming (chunked) — used by SSE |

| Member | Description |
|---|---|
| `int statusCode` | HTTP status. |
| `Map<String, String> headers` | Extra headers (content type travels in `mimeType`). |
| `String? bodyText` / `List<int>? bodyBytes` / `Stream<List<int>>? bodyStream` | The body (at most one set). Stream bodies are written unbuffered with chunked framing. |
| `String? mimeType` | Body MIME type. |
| `copyWith({statusCode, headers})` | Copy preserving the body (including a stream body) — the idiomatic way for middleware to add headers. |

### `DianaRequestLimits`

`const DianaRequestLimits({int multipartMaxBytes = 10485760, int
sseHeartbeatSeconds = 15})` — limits stamped onto every request by the
server (from `server.multipart.maxSize` and `server.sse.heartbeatSeconds`),
consulted by binding helpers. Exposed as `DianaRequest.limits`.

`DianaRequest` also exposes `Stream<Uint8List> readBodyAsBytes()` for raw
byte access (used by multipart decoding).

---

## Pipeline

### `typedef DianaHandler = FutureOr<DianaResponse> Function(DianaRequest)`

The composed unit of the pipeline. Generated route adapters conform to it.

### `typedef Next = FutureOr<DianaResponse> Function(DianaRequest)`

The continuation passed to middleware.

### `abstract interface class Middleware`

```dart
FutureOr<DianaResponse> handle(DianaRequest request, Next next);
```

Call `next(request)` to continue; return a response directly to
short-circuit. See the [middleware guide](../guides/middleware.md).

### `typedef ExceptionMapper = FutureOr<DianaResponse?> Function(Object error, StackTrace stackTrace, DianaRequest request)`

Maps an exception to a response, or returns `null` to fall through to
built-in handling. The generated `@ControllerAdvice` chain implements this.

### `DianaHandler composeMiddleware(List<Middleware> middleware, DianaHandler handler)`

Folds `middleware` around `handler`, first element outermost.

### `DianaHandler withErrorBoundary(DianaHandler handler, {ExceptionMapper? mapper, void Function(Object, StackTrace)? onUnhandled})`

Wraps a handler in Diana's exception pipeline:
`ValidationException` → structured 400; `mapper`; `HttpException` → its
status; anything else → opaque 500 (details to `onUnhandled`).

Both functions are used by `DianaServer` internally and exported for
advanced composition and tests.

### CORS (`cors.dart`)

- `CorsPolicy({allowedOrigins = ['*'], allowedMethods, allowedHeaders = ['*'], exposedHeaders = [], allowCredentials = false, maxAgeSeconds = 3600})`
  — `allowOriginFor(origin)` returns the `Access-Control-Allow-Origin`
  value or `null` (not allowed); `CorsPolicy.fromConfig(config)` builds the
  global policy (or `null` when disabled).
- `DianaHandler withCors(CorsPolicy, DianaHandler)` — adds CORS headers to
  actual responses.
- `DianaHandler corsPreflightHandler(Map<HttpMethod, CorsPolicy>)` — the
  automatic OPTIONS handler.

### Content negotiation (`content.dart`)

`bool acceptsMime(String acceptHeader, String mime)` — wildcard-aware
`Accept` matching (`q=0` excludes; other q-values ignored). The server
wraps every route: incompatible `Accept` ⇒ empty 406.

### Body codecs (`codec.dart`)

- `abstract interface class BodyCodec { List<String> mimeTypes; Object?
  decode(String body); String encode(Object? value); }` — translates a
  wire format to/from `Map`/`List`/scalars. Implement on a **singleton**
  injectable; the generator wires it into the server. First `mimeTypes`
  entry is the canonical response type; `decode` throws `FormatException`
  on malformed input.
- `JsonBodyCodec` — the built-in JSON codec (also matched for `…+json`).
- `BodyCodecRegistry([List<BodyCodec> extra])` — `BodyCodec?
  forMime(String mime)` (parameters like `; charset=` ignored; JSON
  fallback built in). Travels on requests as `DianaRequest.codecs`.
- `Future<Map<String, dynamic>> decodeMapBody(DianaRequest, {required
  List<String> consumes})` / `decodeListBody` — decode the body with the
  codec matching its content type, restricted to `consumes`. 415 when the
  content type isn't listed or has no codec; 400 for malformed input or
  the wrong shape. Generated `@Consumes` adapters call these.
- `DianaResponse negotiatedResponse(DianaRequest, Object? payload,
  {required List<String> produces, int statusCode = 200})` — encodes with
  the first `produces` entry the `Accept` header allows;
  `NotAcceptableException` (406) when none is. Generated `@Produces`
  adapters call this.

See [Content negotiation](../guides/content-negotiation.md).

### XML (`xml_codec.dart`)

`class XmlCodec implements BodyCodec` — `application/xml` and `text/xml`
with a fixed Map↔XML convention (root name ignored, repeated siblings and
`<item>` children become lists, scalar inference, attributes ignored;
encode root is `<response>`). Register with
`@Component() class AppXmlCodec extends XmlCodec {}`. Convention details in
[the guide](../guides/content-negotiation.md#the-xml-convention).

### Server-Sent Events (`sse.dart`)

- `ServerSentEvent(String data, {String? id, String? event, int?
  retryMs})` + `ServerSentEvent.json(Object? data, …)` (JSON-encodes the
  payload).
- `Stream<List<int>> encodeSse(Stream<ServerSentEvent> events, {int
  heartbeatSeconds = 0})` — spec-compliant framing with optional
  `: keep-alive` comments; cancelling the result cancels the source.
- `String encodeSseEvent(ServerSentEvent)` — frames a single event.
- `DianaResponse sseResponse(DianaRequest, Stream<ServerSentEvent>)` —
  200 `text/event-stream`, `cache-control: no-cache`, heartbeat from
  `request.limits.sseHeartbeatSeconds`. What generated `Stream` routes
  return.

See [Server-Sent Events](../guides/server-sent-events.md).

### Multipart (`multipart.dart`)

- `UploadedFile { String name; String? filename; String? contentType; Uint8List bytes; int size; }`
- `FormData { Map<String, String> fields; List<UploadedFile> files; UploadedFile? file(name); }`
- `Future<FormData> decodeFormBody(DianaRequest)` — parses
  `multipart/form-data` (with the size guard → 413) and
  `application/x-www-form-urlencoded`; other types ⇒ 415.

### Health (`health.dart`)

- `HealthIndicator { String get name; Future<HealthStatus> health(); }` —
  implement on a singleton provider; discovered via the DI graph.
- `HealthStatus.up([details]) / HealthStatus.down([details])`.
- `healthEndpointHandler(List<HealthIndicator>)` /
  `infoEndpointHandler(DianaConfig)` — the generated `/actuator/*` handlers.
- `livenessEndpointHandler()` (trivial `200 UP`) /
  `readinessEndpointHandler(List<HealthIndicator>)` (indicator aggregate) —
  the `/actuator/health/{liveness,readiness}` probes.

### Scheduler (`scheduler.dart`)

`DianaScheduler({onError, DianaObserver? observer})` — `schedule({required
task, int? fixedRateMs, int? fixedDelayMs, int initialDelayMs = 0, bool
perIsolate = false, String? name})`, `start()` (skips leader-only tasks in
worker isolates), `Future<void> stop()` (cancels timers, awaits in-flight
runs). Semantics in
[Observability](../guides/observability.md#scheduled-tasks).

### Events (`events.dart`)

- `abstract interface class DianaEventPublisher { Future<void>
  publish(Object event); Future<void> broadcast(Object event); }` — inject
  into any provider. `publish` runs matching local listeners in
  registration order, awaited (errors propagate and skip later listeners);
  `broadcast` additionally relays the event to every other isolate
  (fire-and-forget) and equals `publish` in single-isolate mode. An
  unsendable broadcast event throws `ArgumentError` before local dispatch.
- `class DianaEventBus implements DianaEventPublisher` — the bus the
  generated context owns. `on<T extends Object>(FutureOr<void>
  Function(T))` registers a listener (subtype matching); `remoteSink` is
  the runtime-wired relay hook; `dispatchRemote(event)` delivers a
  remote event locally (never relays; listener errors go to the `onError`
  constructor callback, default prints). Constructible directly in tests.

See [Application events](../guides/events.md).

### Runtime (`runtime.dart`)

- `DianaRunnable({required server, required initialize, required dispose,
  DianaEventBus? eventBus})` — what the generated bootstrap hands to the
  runtime; `eventBus` is passed only when the app uses events.
- `DianaRuntime.run(bootstrap, {int? isolates, bool installSignalHandlers =
  true, Future<void>? shutdownTrigger})` — bootstrap → initialize → serve →
  wait for shutdown → close (drain) → dispose. `isolates` defaults to
  `server.isolates`; see
  [operations](../guides/operations.md#multi-isolate-serving-experimental).
  With multiple isolates and an event bus, broadcast events are bridged
  hub-and-spoke through the main isolate (exactly-once per isolate).
- `DianaRuntime.isWorkerIsolate` — `true` inside worker isolates spawned
  by multi-isolate serving (set before the worker's bootstrap runs);
  `false` on the main isolate and in embedded use. `DianaScheduler`
  consults it to run leader-only tasks once per process.

### OpenAPI (`openapi.dart`)

`String patchOpenApiInfo(String document, DianaConfig config)` — patches
`info.title`/`info.version` from `server.openapi.*` into the generated
document.

---

## Server

### `DianaServer`

```dart
DianaServer({
  DianaConfig config = const DianaConfig.empty(),
  List<Middleware> globalMiddleware = const [],
  ExceptionMapper? exceptionMapper,
  List<BodyCodec> bodyCodecs = const [],
  void Function(Object error, StackTrace stackTrace)? onUnhandled,
})
```

Applications normally don't construct this — the generated
`buildDianaServer()` does. Constructing it manually is the extension point
for custom `onUnhandled` logging or programmatic route registration.

| Member | Description |
|---|---|
| `void register(HttpMethod method, String path, DianaHandler handler, {List<Middleware> middleware})` | Registers a route. `middleware` is the controller+route chain; global middleware wrap around it. Every route is wrapped in the error boundary. |
| `void registerWebSocket(String path, WebSocketHandlerFactory factory, {List<Middleware> middleware})` | Registers a WebSocket endpoint; `factory` runs once per connection. `middleware` run as handshake interceptors (short-circuit blocks the upgrade; request attributes propagate into the session); after the upgrade, errors reach the handler's `onError`. |
| `Future<void> serve({int? port, bool quiet = false, bool shared = false})` | Binds to `server.host`/`server.port` (defaults `0.0.0.0:8080`); HTTPS when `server.ssl.*` is set; mounts static files and CORS preflights. `port: 0` for ephemeral; `shared` allows several isolates on one port. |
| `int? get port` | The bound port (`null` before `serve`). |
| `Future<void> close()` | Stops the server. |
| `DianaConfig config`, `List<Middleware> globalMiddleware`, `ExceptionMapper? exceptionMapper`, `onUnhandled` | The values passed at construction. |

Unmatched routes get `404 {"error":"not_found","message":"No route matches
this path."}`.

---

## WebSockets

### `sealed class WebSocketMessage`

`final class TextMessage { String text; }` ·
`final class BinaryMessage { Uint8List data; }` — pattern-match in
`onMessage`.

### `abstract interface class WebSocketSession`

One live connection (Spring: `WebSocketSession`).

| Member | Description |
|---|---|
| `String id` | Unique per connection (`ws-1`, `ws-2`, …). |
| `Uri uri` | The URI the client connected to. |
| `Map<String, String> pathParameters` | Route `:name` parameters. |
| `Map<String, String> queryParameters` | Handshake query string. |
| `Map<String, Object?> attributes` | Per-connection bag, alive for the session. |
| `bool isOpen` | Whether the connection is open (may briefly report `true` after an undetected peer disconnect). |
| `bool sendText(String)` / `bool sendBytes(Uint8List)` | Send a frame; `false` when already closed (never throws). |
| `Future<void> close([int? code, String? reason])` | Close (`code`: 1000 or 3000–4999; `reason` ≤ 123 UTF-8 bytes). |

### `abstract interface class WebSocketHandler`

Endpoint lifecycle (Spring: `WebSocketHandler`). All callbacks may return
`FutureOr<void>`; frames of one connection dispatch sequentially.

```dart
onOpen(session);
onMessage(session, message);
onError(session, error, stackTrace);   // connection closes (1011) after
onClose(session, code, reason);        // always called last
```

### `abstract class BaseWebSocketHandler implements WebSocketHandler`

No-op implementations of all four callbacks — extend and override what you
need. `const` constructor.

### `typedef WebSocketHandlerFactory = FutureOr<WebSocketHandler> Function()`

Produces the handler for a new connection; generated code passes
`() => ctx.handler` (singleton) or `() => ctx.createHandler()` (transient).

---

## Configuration

### `DianaConfig`

| Member | Description |
|---|---|
| `DianaConfig(Map<String, Object?> values, {Map<String, String>? environment})` | From flattened dot-keys; pass `environment` to enable env overrides (tests inject fakes). |
| `const DianaConfig.empty()` | No values, no environment. |
| `static Future<DianaConfig> load(String path, {Map<String, String>? environment})` | Loads YAML (missing file ⇒ env-only), applies profile overlays (`DIANA_PROFILE` / `diana.profile` → `application-{p}.yaml` in order), flattens to dot-keys, overlays the environment. |
| `List<String> activeProfiles` | Profiles applied by `load`. |
| `Map<String, Object?> section(String prefix)` | Flattened keys under `prefix.` (stripped), env overrides applied. |
| `T get<T>(String key, {T? defaultValue})` | Reads and coerces scalars **and typed lists** (`List<String>`/`List<int>`/… from YAML lists or comma-separated env values). Precedence: environment, then file. Missing key: `defaultValue` if given, `null` if `T` nullable, else `ConfigException`. |
| `bool contains(String key)` | Whether any source has the key. |
| `static String envNameFor(String key)` | `server.port` → `SERVER_PORT` (upper-case; dots and dashes → underscores). |

Coercion rules are in the
[configuration guide](../guides/configuration.md#type-coercion). A key
present with an explicit `null` value is treated as absent.

### `ConfigException`

Thrown for missing required keys or uncoercible values. `String message`.

---

## Binding helpers

Targeted by generated route adapters; also useful in hand-written
`DianaHandler`s. `T` may be `String`, `int`, `double`, `bool`, `num` or a
nullable form. All failures throw `BadRequestException` (→ 400) except the
content-type check (→ 415).

| Function | Behaviour |
|---|---|
| `T bindPathParam<T>(DianaRequest r, String name)` | Missing (non-nullable) or unparsable ⇒ 400. |
| `T bindQueryParam<T>(DianaRequest r, String name, {String? defaultValue})` | Absent ⇒ default if given, `null` if `T` nullable, else 400. |
| `T bindHeader<T>(DianaRequest r, String name)` | Case-insensitive; same nullability rules. |
| `Future<Map<String, dynamic>> decodeJsonMapBody(DianaRequest r)` | Non-JSON content type ⇒ 415; empty/malformed/non-object ⇒ 400. |
| `Future<List<dynamic>> decodeJsonListBody(DianaRequest r)` | Same, expecting an array. |
| `T decodeDto<T>(T Function() decode)` | Wraps DTO construction; shape mismatches (`TypeError`/`FormatException`/enum errors) become 400s. |

`bool` binding accepts `true`/`1`/`false`/`0` (case-insensitive).

---

## Validation

### `abstract interface class Validator<T>`

```dart
ValidationResult validate(T value);
```

Implemented by generated `$XValidator` classes.

### `ValidationResult`

| Member | Description |
|---|---|
| `const ValidationResult(List<FieldError> errors)` | |
| `bool get isValid` | No errors. |
| `void throwIfInvalid()` | Throws `ValidationException` when invalid. |

### `FieldError`

`const FieldError(String field, String message)` — one field-level failure.

### Check helpers

One per constraint; generated validators call them. Signature pattern:
`check<Rule>(value, [ruleArgs,] String field, List<FieldError> errors,
{String? message})`. All skip `null` except `checkNotNull`.

`checkNotNull`, `checkNotEmpty`, `checkNotBlank`,
`checkMin(num? v, num min, …)`, `checkMax(num? v, num max, …)`,
`checkSize(Object? v, …, {int? min, int? max})`,
`checkPattern(String? v, String regex, …)`, `checkEmail(String? v, …)`,
and `mergeNested(ValidationResult nested, String prefix, List<FieldError>
errors)` for `@Valid` cascades.

Default messages are listed in the
[validation guide](../guides/validation.md#validating-manually).

---

## Exceptions

### `HttpException`

`const HttpException(int statusCode, String message, {String reason =
'error'})` — base of the hierarchy. Thrown anywhere in a request, produces
`statusCode` with body `{"error": reason, "message": message}`.

Subclasses (constructor → status/reason):

| Class | Status | reason |
|---|---|---|
| `BadRequestException(message)` | 400 | `bad_request` |
| `UnauthorizedException([message = 'Unauthorized'])` | 401 | `unauthorized` |
| `ForbiddenException([message = 'Forbidden'])` | 403 | `forbidden` |
| `NotFoundException([message = 'Not found'])` | 404 | `not_found` |
| `ConflictException(message)` | 409 | `conflict` |
| `UnsupportedMediaTypeException(message)` | 415 | `unsupported_media_type` |
| `PayloadTooLargeException(message)` | 413 | `payload_too_large` |
| `UnprocessableEntityException(message)` | 422 | `unprocessable_entity` |
| `NotAcceptableException(message)` | 406 | `not_acceptable` |
| `InternalServerErrorException([message])` | 500 | `internal_server_error` |

### `ValidationException`

`const ValidationException(List<FieldError> errors)` — mapped to the
structured 400. `Map<String, List<String>> get fieldMap` groups messages by
field.

---

## Generated API (per application)

These are emitted into `<app>.diana_app.dart` by the generator — documented
here because they are the API you actually call:

| Symbol | Description |
|---|---|
| `class DianaContext` | The DI container: `config` plus one typed member per provider, and `initialize()`/`dispose()` lifecycle methods. When events are used it also owns `eventBus` (a `DianaEventBus`), with listeners registered in the constructor. |
| `class DianaOverrides` | One nullable slot per provider for test overrides. |
| `class DianaRequestScope` | Present only when request-scoped providers exist. |
| `class DianaApp` | `context` + `server` + `initialize()`/`dispose()` (starts/stops the scheduler when `@Scheduled` tasks exist; serves/stops `grpcServer` when `@GrpcService` classes exist). |
| `DianaContext buildDianaContext({DianaConfig? config, DianaOverrides overrides})` | Constructs the graph (no HTTP). |
| `Future<DianaApp> buildDianaApp({DianaConfig? config, DianaOverrides overrides})` | Loads config, builds the context, registers routes/WebSockets/actuator/OpenAPI. |
| `Future<DianaServer> buildDianaServer({DianaConfig? config, DianaOverrides overrides})` | `buildDianaApp(...).server`. |
| `Future<void> runDiana({DianaConfig? config, DianaOverrides overrides})` | `DianaRuntime.run` over `buildDianaApp` — lifecycle + graceful shutdown (passes the context's `eventBus` to the runtime when events are used). |
| `const String dianaOpenApiJson` | The build-time OpenAPI document. |

See [Generated code](generated-code.md) for naming and structure details.

---

## gRPC (`package:diana_grpc`)

Lives in its own package — the only one depending on `package:grpc`
(HTTP-only apps carry no gRPC dependency). Re-exports `Service`,
`ServiceCall` and `Interceptor` from `package:grpc`.

### `DianaGrpcServer`

```dart
DianaGrpcServer(DianaConfig config,
    {required List<Service> services, List<Interceptor> interceptors = const []})
```

Wraps `package:grpc`'s server with Diana configuration and lifecycle. The
generator constructs one per app with every `@GrpcService` instance and
exposes it as `DianaApp.grpcServer`.

| Member | Description |
|---|---|
| `bool get enabled` | `grpc.enabled` (default `true`). |
| `Future<void> serve({int? port, bool quiet = false})` | Binds `grpc.host:grpc.port` (defaults `0.0.0.0:9090`). No-op when disabled. Fails fast (`StateError`) when `server.isolates > 1` — gRPC serving is single-isolate. |
| `int? get port` | Bound port (`null` before `serve` or when disabled). |
| `Future<void> shutdown()` | Stops the server, waiting for in-flight calls. |

See the [gRPC guide](../guides/grpc.md).

`diana_grpc` also exports `Interceptor grpcAuthInterceptor(Future<Set<String>?>
Function(Map<String, String>) authorize, {List<String> rolesAllowed})` — the
generator wires it from a `diana_auth` `AuthenticationMiddleware` to secure
`@GrpcService` classes (UNAUTHENTICATED / PERMISSION_DENIED).

---

## Observability contract (`observer.dart`)

`abstract class DianaObserver` — the neutral hook the runtime calls into so
`package:diana` never depends on an observability implementation. All
methods have no-op defaults:

- `observeHttp(HttpMethod, String routeTemplate, DianaRequest, DianaHandler
  next)` — wraps a route (outside the error boundary, so it sees the final
  status and never an exception).
- `observeUnmatched()` — a 404 (no path, bounded cardinality).
- `observeQuery<T>(String operation, FutureOr<T> Function() run)` — a
  database operation (wired by `diana_data`).
- `observeScheduledRun(String? name, Duration, {required bool success})` and
  `observeEventDispatch(String eventType, Duration)`.

`DianaServer`, `DianaScheduler`, `DianaEventBus` and `Database` all take an
optional `observer`; the generator wires the app's `DianaObservability`
provider (from `package:diana_observability`) into each when present.

## Observability (`package:diana_observability`)

The optional metrics/tracing package — the only one depending on
`package:opentelemetry`.

- `class DianaObservability extends DianaObserver` — subclass and register
  as a `@Component`. Records the built-in Prometheus series and, when
  constructed with `TracingOptions`, OpenTelemetry spans. `MeterRegistry get
  meters` for application metrics; `String scrape()` renders the exposition
  text; `void close()` flushes the tracer.
- `Counter`/`Gauge`/`Histogram`/`MeterRegistry` — the in-package metrics
  model (Prometheus 0.0.4 text format).
- `class TracingOptions {String? endpoint; String serviceName}` — OTLP
  collector target; omit `endpoint` to disable tracing.
- `metricsEndpointHandler(DianaObservability)` — the `/actuator/metrics`
  handler.

See the [observability guide](../guides/observability.md).

## Authentication (`package:diana_auth`)

The optional security package. Its only allowed crypto dependency is
`package:crypto` (boundary-tested); it never imports `package:grpc`.

### Principal & strategies

- `class AuthPrincipal { String name; Set<String> roles; Map<String,
  Object?> attributes; bool hasRole(String); }` — the authenticated
  identity; subclass for a richer one.
- `abstract interface class Authenticator { String? get challenge;
  FutureOr<AuthPrincipal?> authenticate(AuthRequest); }` — one strategy.
  Return `null` = no credentials for this scheme; throw
  `InvalidCredentialsException` = present-but-invalid (→ 401).
- `abstract interface class AuthRequest { String? header(String); }` with
  `MapAuthRequest` (gRPC metadata / tests) and `DianaAuthRequest`
  (HTTP / WS) views.
- Built-ins: `JwtAuthenticator(TokenVerifier, {rolesClaim})`,
  `BasicAuthenticator(UserStore, {realm})`,
  `ApiKeyAuthenticator(ApiKeyValidator, {headerName})`.
- JWT: `TokenVerifier` (interface), `Hs256TokenVerifier(secret, {clockSkew,
  issuer, audience})` (hardened HS256), `Hs256TokenSigner(secret)` with
  `sign(claims)` and `claimsFor(sub, {roles, ttl, rolesClaim})`.

### Middleware & guards

- `class AuthenticationMiddleware implements Middleware` —
  `AuthenticationMiddleware({required List<Authenticator> authenticators,
  bool challengeOnUnauthorized = true})`. Runs the chain, stamps the
  principal under `principalAttributeKey`, attaches `WWW-Authenticate` to
  401s. `Future<AuthPrincipal?> authenticate(AuthRequest)` and
  `Future<Set<String>?> authorizeMetadata(Map<String, String>)` (the gRPC
  seam). Assemble by subclassing.
- `class SecuredGuard implements Middleware` (const) — 401 when anonymous.
- `class RolesGuard implements Middleware` — `const RolesGuard(List<String>
  roles)`; 401 anonymous, 403 missing every role.

`principalAttributeKey` and `T bindPrincipal<T>(DianaRequest)` live in
`package:diana` (`binding.dart`) — the cross-package contract read by
`@Principal()` adapters.

See the [auth guide](../guides/auth.md).

---

## Persistence (`package:diana_data`)

The optional data package — the only one depending on `package:knex_dart`
(boundary-tested); driver-agnostic.

- `class Database` — the injectable query executor. `QueryBuilder
  table(String)` / `query()` build queries;
  `Future<List<Map<String, dynamic>>> select/insert/update/delete(QueryBuilder)`
  and `raw(String, [bindings])` run them against the ambient executor (the
  current transaction from the `Zone`, else the pooled connection).
  `Future<T> runTransactional<T>(Future<T> Function())` opens/nests a
  transaction (called by generated `@Transactional` proxies).
  `open()`/`migrate()`/`close()` are the lifecycle hooks the generated
  context drives.
- `abstract class DatabaseConnector { Future<Object> connect(DianaConfig);
  Future<void> close(Object connection); }` — subclass as a provider; opens
  your driver connection and owns its close.
- `class DatabaseHealthIndicator implements HealthIndicator` — takes a
  `Database`, pings `SELECT 1`; register as a `@Component` to expose it on
  `/actuator/health`.

See the [persistence guide](../guides/persistence.md).
