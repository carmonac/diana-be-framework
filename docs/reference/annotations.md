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
Binds the JSON request body. Parameter type: a DTO with `fromJson`,
`Map<String, dynamic>`, `List<Dto>`, or a `List` of JSON primitives. Wrong
content type → 415; malformed/empty/mis-shaped JSON → 400. If the DTO has
constraint annotations, its generated validator runs before the handler.

### `@ResponseStatus(int code)`

**Target:** method.
Overrides the success status code (e.g. `201`). Applies to JSON, text and
`void` returns; ignored when the method returns `DianaResponse` (which
carries its own status).

---

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
