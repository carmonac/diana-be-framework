# Build diagnostics reference

Every error `diana_generator` can report, grouped by area, with the fix.
Local errors (annotations, signatures) point at the exact source span;
graph errors are collected and reported **together** in a single build
failure so you can fix a batch at once.

Messages below show the pattern; `X`, `Y`, `p` etc. stand for your names.

---

## Class-level rules

**`Class X combines @A and @B; a class may carry only one Diana role annotation.`**
A class can be a controller *or* a service *or* an advice… Split the
responsibilities into separate classes.

**`Diana-annotated classes must be public: generated wiring in other libraries needs to reference them.`**
Remove the leading underscore.

**`Class X declares type parameters. Generic injectables are not supported; provide a concrete subclass instead.`**
`class Repo<T>` can't be a provider. `class TodoRepo extends Repo<Todo>`
can — and satisfies dependencies on `Repo<Todo>`.

**`Class X is abstract and cannot be instantiated. Annotate a concrete implementation instead.`**
Move the annotation to the implementation; depend on the abstract type.

**`Class X has no public unnamed generative constructor; Diana instantiates providers through it.`**
Add one (factory-only and named-only classes are not injectable).

**`Class X is bound `as: Y` but does not implement or extend it.`**
Fix the `as:` target or add the `implements`.

---

## Dependency graph

**`No provider found for X — required by constructor parameter "p" of Y (package:...). Annotate a providing class with @Service/@Component, or check the type and qualifier.`**
Nothing in the package provides `X`. Also raised when only a
`@Named`-qualified provider exists but the parameter has no `@Named`.

**`Multiple providers implement X: A (lib), B (lib) — required by ... Disambiguate with @Named or bind one explicitly with `as:`.`**
Interface auto-binding needs exactly one implementation.

**`Multiple providers bound to X: ... Remove one, or qualify them with `name:` and select with @Named.`**
Two providers claim the same type as a *strong* binding (same class twice
via `as:`, or duplicated class).

**`Duplicate provider for X: declared in both lib_a and lib_b.`**
The same class (same type + qualifier) is registered twice.

**`Dependency cycle detected: A -> B -> A. Break the cycle, e.g. by extracting an interface or inverting one dependency.`**
Constructor injection cannot create cycles; restructure.

**`Singleton X (lib) depends on request-scoped Y: a singleton outlives every request. Make X request-scoped, or make Y a singleton.`**
Scope safety — see [scopes](../guides/dependency-injection.md#scopes).

**`Constructor parameter "p" of X has unsupported type T; only class types can be injected.`**
Function types, records and type variables aren't injectable.

---

## Lifecycle and scheduling

**`@PostConstruct method X.y must be a public instance method with no parameters returning void or Future<void>.`**
(Same for `@PreDestroy` and `@Scheduled`.)

**`Class X declares multiple @PostConstruct methods; declare at most one.`**
(Same for `@PreDestroy`.)

**`@PostConstruct on X requires singleton scope; found transient.`**
(Same for `@PreDestroy` and `@Scheduled` — per-instance lifecycle on
transient/request providers is not supported.)

**`@Scheduled on X.y requires exactly one of fixedRate or fixedDelay.`**

---

## JSON (@Json)

**`Unsupported field type T in @Json class X. Supported: String, int, double, bool, num, dynamic, DateTime, enums, List/Map<String, _> of supported types, and nested classes that are @Json or expose fromJson/toJson.`**

**`@Json class X has no public unnamed generative constructor.`**

**`Constructor parameter "p" of @Json class X has no matching field; @Json builds instances by matching constructor parameters to fields by name.`**

**`@Json map fields must have String keys — got Map<int, String> in X.`**

---

## Actuator

**`X implements HealthIndicator but is transient-scoped; health indicators must be singletons.`**

---

## Application entrypoint

**`Multiple @DianaApplication classes found: A (lib), B (lib). A package must declare exactly one application entrypoint.`**

---

## Controllers and routes

**`Route method X.m must be a public instance method.`**

**`Parameter "p" of route method X.m needs exactly one binding annotation (@PathParam, @QueryParam, @Header, @Body or @Principal), or be of type DianaRequest for raw access.`**

**`Parameter "p" of route method X.m combines multiple binding annotations; use exactly one.`**

**`Parameter "p" of route method X.m must be String, int, double, bool or num (nullable allowed for @QueryParam/@Header) — got T.`**

**`Path parameter "p" of X.m is always present when the route matches; use a non-nullable type.`**

**`@Body parameter "p" of X.m has unsupported type T.`**
See [supported body types](../guides/controllers.md#request-bodies).

**`X is used with @Body in Y.m but has no `factory X.fromJson(Map<String, dynamic>)`. Write one manually or generate it with json_serializable (both work with Diana).`**

**`X is returned from route method Y.m but has no `Map<String, dynamic> toJson()`. Write one manually or generate it with json_serializable (both work with Diana).`**

**`Route method X.m has unsupported return type T. Supported: a DTO with toJson(), List of DTOs, Map, String, void, DianaResponse — optionally wrapped in Future.`**

**`x.dart declares Diana members that need generated code, but is missing the part directive. Add: part 'x.diana.dart';`**
Copy the printed line into the file, below the imports.

---

## Content negotiation

**`@Consumes on X.m lists no MIME types.`**
(Also raised for `@Produces`.) The list must contain at least one entry.

**`@Consumes on X.m requires a codec-decoded @Body parameter (Map, List or DTO); String, FormData and raw-request bodies bypass codecs.`**

**`@Produces on X.m requires a JSON-encodable return (DTO, List of DTOs, Map or List); String, void and DianaResponse returns are not negotiated.`**

**`X implements BodyCodec but is <scope>-scoped; body codecs must be singletons.`**
Codecs are discovered through the DI graph and wired once into the server.

---

## Server-Sent Events

**`Route method X.m returns Stream<Y>; supported stream element types are ServerSentEvent or a DTO with toJson().`**

**`@ResponseStatus cannot be combined with a Stream return on X.m; SSE responses are always 200.`**

**`@Produces cannot be combined with a Stream return on X.m; SSE always produces text/event-stream.`**

---

## gRPC

**`@GrpcService class X does not extend a grpc service base class. Extend your protoc-generated XServiceBase (package:grpc Service).`**
Only classes whose supertype chain reaches `package:grpc`'s `Service`
qualify — your protoc-generated `XServiceBase` does.

---

## Events

**`@EventListener method X.m must be a public instance method with exactly one positional parameter returning void or Future<void>.`**

**`@EventListener parameter "p" of X.m must be a non-nullable class type; found T.`**
The parameter is the subscribed event type — `dynamic`, nullable and
function types cannot be matched.

**`@EventListener on X requires singleton scope; found <scope>.`**
Listeners need a stable instance for the application's lifetime.

---

## Authentication & authorization

**`@RolesAllowed on X lists no roles.`**

**`@Secured/@RolesAllowed on X has no effect: it is not a REST controller, WebSocket controller, gRPC service, or route method.`**
A silently ignored security annotation is a hole you believe is closed.

**`@Principal parameter "p" of X.m must be a class type.`**
The bound principal must be `AuthPrincipal` or a class subtype.

**`@Secured/@RolesAllowed on @GrpcService X requires exactly one singleton provider extending diana_auth's AuthenticationMiddleware; found ...`**

**`gRPC security is server-wide in this version; all @GrpcService classes must declare identical @Secured/@RolesAllowed (found differing declarations on A and B).`**

The `@Principal` binding also participates in the existing "needs exactly
one binding annotation" / "combines multiple binding annotations" errors.

---

## Persistence

**`@Transactional/Database injection found but no DatabaseConnector provider was declared. Add a @Component extending diana_data's DatabaseConnector.`**

**`Multiple DatabaseConnector providers: A (lib), B (lib). Declare exactly one.`**

**`@Transactional class X must be extendable: remove the final/base/sealed modifier so Diana can generate a transactional proxy subclass.`**

**`@Transactional method X.m must return Future (transactions are asynchronous); found T.`**

**`@Transactional on X has no effect: it is not a @Service/@Component/@Repository provider.`**

---

## Middleware

**`X, referenced by @GlobalMiddleware, is not an injectable class. Annotate it with @Component (or another injectable annotation).`**
Also raised for `@UseMiddleware on Controller` /
`@UseMiddleware on Controller.method`.

**`X, referenced by ..., does not implement Diana's Middleware interface.`**

**`X, referenced by ..., is request-scoped; middleware must be singletons.`**
(Also applies to `@UseMiddleware on @WebSocketController X` — handshake
interceptors.)

**`@UseMiddleware entries must be type literals.`**
Only `@UseMiddleware([SomeType])` — no expressions.

---

## WebSockets

**`@WebSocketController class X (lib) does not implement Diana's WebSocketHandler interface. Implement it, or extend BaseWebSocketHandler.`**

**`Duplicate WebSocket path "/ws/x": handled by both A and B.`**
Each endpoint path maps to exactly one handler class.

**`@WebSocketController class X cannot be request-scoped; use Scope.singleton (shared handler) or Scope.transient (one handler per connection).`**

---

## Configuration

**`@Value parameter "p" of X must be String, int, double, bool or num — got T.`**

**`@Value defaultValue must be a String, int, double or bool literal.`**

**`@ConfigurationProperties class X has no public unnamed generative constructor.`**

**`Constructor parameter "p" of @ConfigurationProperties class X must be String, int, double, bool or num (nullable for optional keys) — got T.`**

---

## Exception handling

**`@ControllerAdvice class X declares no @ExceptionHandler methods.`**

**`@ExceptionHandler on X.m must reference a class type.`**

**`Exception handler X.m must take (E) or (E, DianaRequest).`**
The first parameter's type must be exactly the annotated exception type;
the optional second must be `DianaRequest`.

**`Exception handler X.m must return DianaResponse (or Future<DianaResponse>).`**

---

## Validation

**`@Min on X.f requires a numeric field — got T.`**
Analogous messages for each constraint: `@Max` (numeric), `@NotBlank`,
`@Email`, `@Pattern` (String), `@NotEmpty`, `@Size` (String, List, Set or
Map).

**`@Valid on X.f cascades into T, which has no constraint annotations.`**
Add constraints to the nested type, or drop `@Valid`.

---

## Runtime startup errors

Not build errors, but startup failures worth knowing:

**`ConfigException: Missing required config key "k" (checked the YAML config file and environment variable "K").`**
A `@Value` without default or a non-nullable `@ConfigurationProperties`
key is absent from every source.

**`ConfigException: Config key "k" has value "v" (RuntimeType), which cannot be read as T.`**
The configured value can't be coerced — fix the YAML/env value.
