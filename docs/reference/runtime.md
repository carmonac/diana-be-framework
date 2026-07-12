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

| Member | Description |
|---|---|
| `int statusCode` | HTTP status. |
| `Map<String, String> headers` | Extra headers (content type travels in `mimeType`). |
| `String? bodyText` / `List<int>? bodyBytes` | The body (at most one set). |
| `String? mimeType` | Body MIME type. |
| `copyWith({statusCode, headers})` | Copy preserving the body — the idiomatic way for middleware to add headers. |

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

---

## Server

### `DianaServer`

```dart
DianaServer({
  DianaConfig config = const DianaConfig.empty(),
  List<Middleware> globalMiddleware = const [],
  ExceptionMapper? exceptionMapper,
  void Function(Object error, StackTrace stackTrace)? onUnhandled,
})
```

Applications normally don't construct this — the generated
`buildDianaServer()` does. Constructing it manually is the extension point
for custom `onUnhandled` logging or programmatic route registration.

| Member | Description |
|---|---|
| `void register(HttpMethod method, String path, DianaHandler handler, {List<Middleware> middleware})` | Registers a route. `middleware` is the controller+route chain; global middleware wrap around it. Every route is wrapped in the error boundary. |
| `void registerWebSocket(String path, WebSocketHandlerFactory factory)` | Registers a WebSocket endpoint; `factory` runs once per connection. Middleware and the error boundary do not apply — errors reach the handler's `onError`. |
| `Future<void> serve({int? port, bool quiet = false})` | Binds to `server.host`/`server.port` from config (defaults `0.0.0.0:8080`). `port` overrides — pass `0` for an OS-assigned port in tests. Prints `[diana] Listening on …` unless `quiet`. |
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
| `static Future<DianaConfig> load(String path, {Map<String, String>? environment})` | Loads a YAML file (missing file ⇒ env-only config), flattens nested maps to dot-keys, overlays `Platform.environment` (or the given map). |
| `T get<T>(String key, {T? defaultValue})` | Reads and coerces. Precedence: environment, then file. Missing key: `defaultValue` if given, `null` if `T` is nullable, otherwise throws `ConfigException` naming the key and its environment variable. Uncoercible value ⇒ `ConfigException`. |
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
| `UnprocessableEntityException(message)` | 422 | `unprocessable_entity` |
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
| `class DianaContext` | The DI container: `config` plus one typed member per provider. |
| `class DianaRequestScope` | Present only when request-scoped providers exist. |
| `DianaContext buildDianaContext({DianaConfig? config})` | Constructs the graph (no HTTP). Default config: empty. |
| `Future<DianaServer> buildDianaServer({DianaConfig? config})` | Loads config (or uses the override), builds the context, registers every route with its middleware and the advice chain. |
| `Future<void> runDiana({DianaConfig? config})` | `buildDianaServer` + `serve()`. |

See [Generated code](generated-code.md) for naming and structure details.
