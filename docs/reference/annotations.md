# Annotation reference

Every annotation in `package:diana_annotation` (re-exported by
`package:diana/diana.dart`). All annotations are `const` classes with no
runtime behaviour — they exist for the generator.

Notation: `[x]` optional positional parameter, `{x}` named parameter.

---

## Dependency injection

### `@Injectable({Scope scope = Scope.singleton, Type? as, String? name})`

**Target:** class.
Marks a class as a provider in the DI graph. Instantiated through its
public unnamed generative constructor; every constructor parameter is
resolved at build time.

| Parameter | Meaning |
|---|---|
| `scope` | Lifecycle: `Scope.singleton` (default), `Scope.request`, `Scope.transient`. |
| `as` | Explicitly bind this provider to a type it implements/extends, taking precedence over auto-binding candidates. Build error if the class doesn't implement it, or if two providers claim the same type. |
| `name` | Qualifier. A named provider is only injectable through `@Named(name)`. |

### `@Service(...)`, `@Repository(...)`, `@Component(...)`

**Target:** class.
Semantic aliases of `@Injectable` with identical parameters and behaviour.
Use them to communicate a class's role.

### `@Named(String name)`

**Target:** constructor parameter.
Selects the provider registered with qualifier `name` for this parameter.

```dart
Notifier(@Named('smtp') MailSender sender);
```

### `enum Scope { singleton, request, transient }`

See [scopes](../guides/dependency-injection.md#scopes).

---

## Web

### `@RestController([String path = '/', Scope scope = Scope.singleton])`

**Target:** class.
Declares an HTTP controller; all routes mount under `path`. The controller
joins the DI graph with the given `scope` (a controller depending on
request-scoped providers must itself be request-scoped). Requires a
`part '<file>.diana.dart';` directive in the library.

### `@Get`, `@Post`, `@Put`, `@Delete`, `@Patch` — `([String path = ''])`

**Target:** method (public, instance).
Maps the method to the HTTP verb, at `path` relative to the controller
(`''` = the controller path itself). Paths use `:name` segments for path
parameters.

### `@HttpRoute(String method, String path)`

**Target:** method.
Base class of the verb annotations; use directly for verbs without a
shorthand: `@HttpRoute('HEAD', '/status')`. `method` is upper-case.

### `@PathParam([String? name])`

**Target:** parameter.
Binds a `:name` path segment. `name` defaults to the Dart parameter name.
Type: non-nullable `String`/`int`/`double`/`bool`/`num`. Conversion failure
→ 400.

### `@QueryParam([String? name, String? defaultValue])`

**Target:** parameter.
Binds a query-string parameter. `name` defaults to the parameter name.
`defaultValue` is written as a string (`'20'`) and converted like a real
value. A nullable parameter type makes it optional (bound to `null` when
absent); a non-nullable type without default is required (400 when
missing).

### `@Header([String? name])`

**Target:** parameter.
Binds a request header, case-insensitively. Same type/nullability rules as
`@QueryParam` (no default value).

### `@Body()`

**Target:** parameter.
Binds the request body. Parameter types: a DTO (`@Json`, hand-written
`fromJson`, or json_serializable), `Map<String, dynamic>`, `List<Dto>`, a
`List` of JSON primitives, `String` (raw text, any content type) or
`FormData` (multipart / urlencoded — see
[uploads](../guides/controllers.md#request-bodies)). Wrong content type →
415; malformed/mis-shaped bodies → 400; oversized multipart → 413. DTO
validators run before the handler.

### `@ResponseStatus(int code)`

**Target:** method.
Overrides the success status code (e.g. `201`). Applies to JSON, text and
`void` returns; ignored when the method returns `DianaResponse` (which
carries its own status).

### `@CrossOrigin({origins, methods, headers, exposedHeaders, credentials, maxAge})`

**Target:** class (controller) or method (route).
Enables CORS with a policy that **fully replaces** the global
`server.cors.*` configuration (route > controller > global). Diana
registers the OPTIONS preflight automatically. Fields mirror the config
keys — see [CORS](../guides/cors-and-static.md#cors).

### `@Consumes(List<String> mimeTypes)`

**Target:** class (controller) or method (route); method replaces
controller entirely.
Restricts the request content types the route accepts; the body is decoded
with the matching registered `BodyCodec` (other content types → 415). The
listed set **replaces** the JSON default. Requires a codec-decoded `@Body`
parameter (`Map`, `List` or DTO). See
[Content negotiation](../guides/content-negotiation.md).

### `@Produces(List<String> mimeTypes)`

**Target:** class (controller) or method (route); method replaces
controller entirely.
Declares the response formats the route can produce; the response is
encoded with the first type the request's `Accept` header allows (server
preference order; nothing acceptable → 406). Applies to JSON-encodable
returns only; cannot be combined with `Stream` returns. See
[Content negotiation](../guides/content-negotiation.md).

---

## Lifecycle

### `@PostConstruct()` / `@PreDestroy()`

**Target:** method (public instance, no parameters, `void`/`Future<void>`;
at most one of each per class; singleton providers only).
Run after construction during `initialize()` (dependency order) and during
graceful shutdown in `dispose()` (reverse order). See the
[lifecycle guide](../guides/lifecycle.md).

---

## Scheduling

### `@Scheduled({int? fixedRate, int? fixedDelay, String? cron, int initialDelay = 0, bool perIsolate = false})`

**Target:** method (same signature rules as lifecycle hooks; singleton
providers only). Exactly one of `fixedRate`/`fixedDelay` (milliseconds) or
`cron`. Tasks start after initialization and stop on shutdown; `fixedRate`
skips overlapping ticks, `fixedDelay` re-arms after completion, `cron` fires
at each expression match (next occurrence computed after completion, so runs
never overlap). `cron` is a 6-field expression (`second minute hour
day-of-month month day-of-week`, Spring style; three-letter month/day names,
ranges, lists and `*/step`) or a macro (`@yearly`, `@monthly`, `@weekly`,
`@daily`, `@hourly`), evaluated in the process's local time (`initialDelay`
does not apply). With multi-isolate serving, tasks run **once per process**
(main isolate only); `perIsolate: true` opts a task into running in every
isolate. See [Observability](../guides/observability.md#scheduled-tasks).

---

## Messaging (STOMP)

STOMP handlers on singleton providers. See the [STOMP guide](../guides/stomp.md).

### `@MessageMapping(String destination)`

**Target:** method. Handles STOMP SENDs to `<appPrefix>/<destination>`
(default prefix `/app`). Takes the payload (a `String` for the raw body, or
an `@Json` class) and, optionally, a second `StompMessage` parameter; a
non-void return (`String` or `@Json`, optionally `Future`) is published to
the `@SendTo` destination. `destination` must start with `/`.

### `@SendTo(String destination)`

**Target:** method (with `@MessageMapping`). Publishes the method's return
value to `destination` (must start with `/`). Required when the method
returns a value.

---

## Events


### `@EventListener()`

**Target:** method (public instance, exactly one positional parameter — the
event type, a non-nullable class — returning `void`/`Future<void>`;
singleton providers only).
Registers the method as an application-event listener: it receives every
event published through `DianaEventPublisher` whose type matches the
parameter (subtypes included). Listeners are registered before
`initialize()`, dispatched in registration order and awaited. See the
[events guide](../guides/events.md).

---

## Authentication & authorization

These require the `diana_auth` package (the runtime types they wire in live
there). See the [auth guide](../guides/auth.md).

### `@Secured()`

**Target:** class (REST/WebSocket controller or gRPC service) or route
method; method replaces controller.
Requires an authenticated principal — anonymous requests get **401**. The
generator appends a guard after the authentication middleware.

### `@RolesAllowed(List<String> roles)`

**Target:** same as `@Secured`.
Requires the principal to hold **any** of `roles` (401 anonymous, 403
authenticated-but-missing-role). Implies `@Secured`.

### `@Principal()`

**Target:** route-method parameter.
Binds the authenticated principal (`AuthPrincipal` or a subclass). A
non-nullable parameter throws 401 when unauthenticated; a nullable one
receives `null`.

---

## JSON

### `@Json()`

**Target:** class.
Generates `$XFromJson`/`$XToJson` into the class's part file; route
adapters use them automatically for `@Body` parameters and return values —
no `fromJson`/`toJson` boilerplate. Supported field types are listed in the
[JSON guide](../guides/json.md). Requires a `part` directive and a public
unnamed constructor whose parameters match field names.

### `@JsonField({String? name})`

**Target:** field (inside a `@Json` class).
Renames the field's JSON key.

---

## WebSockets

### `@WebSocketController(String path, [Scope scope = Scope.singleton])`

**Target:** class (must implement `WebSocketHandler`, e.g. by extending
`BaseWebSocketHandler`).
Registers the class as a WebSocket endpoint at `path` (which may contain
`:name` parameters, exposed via `WebSocketSession.pathParameters`). The
class joins the DI graph:

- `Scope.singleton` (default) — one shared handler for all connections.
- `Scope.transient` — a fresh handler per connection.
- `Scope.request` — build error (not applicable to WebSockets).

Endpoint paths must be unique across the application. `@UseMiddleware` on
the class runs as **handshake interceptors** (blocking the upgrade on
short-circuit and propagating request attributes into the session); global
middleware and `@ControllerAdvice` do not apply to socket traffic. See the
[WebSockets guide](../guides/websockets.md).

---

## gRPC

### `@GrpcService()`

**Target:** class (must extend a protoc-generated `XServiceBase`, i.e. a
`package:grpc` `Service`).
Registers the class as a gRPC service: it joins the DI graph as a
singleton (constructor injection, `@Value`, lifecycle apply) and the
generated `DianaApp` serves all `@GrpcService` classes on `grpc.port`
through `package:diana_grpc` (a dependency your app must declare). Cannot
be combined with other role annotations. See the
[gRPC guide](../guides/grpc.md).

---

## Persistence

Requires the `diana_data` package (the `Database` it works with lives
there). See the [persistence guide](../guides/persistence.md).

### `@Transactional()`

**Target:** method (must return `Future`) or class (all public
`Future`-returning methods) on a `@Service`/`@Component`/`@Repository`
provider that is **extendable** (not `final`/`base`/`sealed`).
Runs the method inside a database transaction via a generated proxy
subclass. Nesting joins the enclosing transaction as a savepoint
(propagation REQUIRED); an uncaught exception rolls back and rethrows.

---

### `@Table(String name)`

**Target:** class (a `@Json` entity). Maps the entity to a database table
for [query repositories](../guides/persistence.md#query-methods-spring-data-style);
column names are the fields' JSON keys (`@JsonField(name:)` doubles as the
column override).


## Aspects

Method-level, on `@Service`/`@Component`/`@Repository` providers; the
methods must be public instance methods returning `Future`, and the class
must be extendable. Fixed composition order `@Timed` → `@Cacheable` →
`@CircuitBreaker` → `@Retryable` → `@Transactional`. See the
[aspects guide](../guides/aspects.md).

| Annotation | Parameters | Meaning |
|---|---|---|
| `@Timed` | `String? name` (default `Class.method`) | Duration/result metrics + a trace span via the observability provider (silent no-op without one) |
| `@Cacheable` | `int ttlSeconds = 60`, `int maxEntries = 1024` | Per-isolate TTL+LRU cache keyed by the argument list (or a shared backend via a [`DianaCacheStore`](../guides/aspects.md#pluggable-cache-store) provider); needs `Future<T>` with non-void `T`, no type parameters |
| `@Retryable` | `int maxAttempts = 3`, `int backoffMs = 200`, `List<Type> retryOn = const []` | Fixed-backoff retry; `retryOn` limits the exception types (empty = all) |
| `@CircuitBreaker` | `int failureThreshold = 5`, `int resetTimeoutMs = 30000` | Fail-fast after consecutive failures; half-open trial after the timeout |

## Middleware

### `@GlobalMiddleware({int order = 0})`

**Target:** class (must implement `Middleware`).
Registers the class as global middleware applied to every route, and makes
it an injectable singleton. Lower `order` runs first (outermost); ties
break by class name.

### `@UseMiddleware(List<Type> middleware)`

**Target:** class (controller) or method (route).
Applies the listed middleware — in order — to all routes of a controller or
to one route. Each type must be an injectable singleton implementing
`Middleware` (verified at build time). Effective order:
global → controller-level → route-level.

---

## Configuration

### `@Value(String key, {Object? defaultValue})`

**Target:** constructor parameter (of any injectable class).
Injects the configuration value at `key` (dot notation). The parameter type
must be `String`/`int`/`double`/`bool`/`num`. `defaultValue` must be a
`String`/`int`/`double`/`bool` literal. Without a default, a missing key
fails at startup.

### `@ConfigurationProperties(String prefix)`

**Target:** class.
Binds a configuration section to the class: each constructor parameter is
read from `<prefix>.<paramName>` (nullable parameter ⇒ optional key). The
class becomes an injectable singleton. Parameter types:
`String`/`int`/`double`/`bool`/`num` (nullable allowed). Requires a `part`
directive (the binder function is generated).

---

## Exception handling

### `@ControllerAdvice()`

**Target:** class.
Declares a global exception-handling component (an injectable singleton).
Must contain at least one `@ExceptionHandler` method.

### `@ExceptionHandler(Type exception)`

**Target:** method (inside a `@ControllerAdvice` class).
Handles thrown exceptions of `exception` **and its subtypes**. When several
handlers match, the most specific exception type wins.

Valid signatures — the first parameter type must be exactly the annotated
type:

```dart
DianaResponse on(MyError e)
DianaResponse on(MyError e, DianaRequest req)
Future<DianaResponse> on(MyError e)              // async also allowed
```

---

## Validation

All validation annotations target **fields** of DTO classes and accept an
optional `{String? message}` overriding the default text. All except
`@NotNull` skip `null` values. Wrong field type ⇒ build error.

### `@NotNull({String? message})`
Any field. Fails when the value is `null`.

### `@NotEmpty({String? message})`
`String`, `List`, `Set` or `Map`. Fails when empty.

### `@NotBlank({String? message})`
`String`. Fails when empty or whitespace-only.

### `@Min(num value, {String? message})` / `@Max(num value, {String? message})`
Numeric fields. Fail when `< value` / `> value`.

### `@Size({int? min, int? max, String? message})`
`String`, `List`, `Set` or `Map`. Fails when the length is outside
`[min, max]` (either bound optional).

### `@Pattern(String regex, {String? message})`
`String`. Fails when the value doesn't match `regex`. Note: in files
importing Diana, `Pattern` shadows `dart:core`'s `Pattern` (mirroring
Jakarta's `@Pattern`); use an import prefix if you need the core type.

### `@Email({String? message})`
`String`. Fails when not shaped like an email address.

### `@Valid()`
A DTO field or `List` of DTOs. Cascades validation into the nested type,
prefixing error field names (`address.street`, `items[2].name`). The
nested type must itself have constraints.

---

## Application

### `@DianaApplication({String configFile = 'application.yaml'})`

**Target:** class (empty body by convention), anywhere under `lib/`.
Marks the application entrypoint — **exactly one per package**. The
generator emits the composition root as a sibling `<file>.diana_app.dart`
library containing `DianaContext`, `buildDianaContext()`,
`buildDianaServer()` and `runDiana()`. `configFile` is the YAML file loaded
at startup, relative to the working directory.
