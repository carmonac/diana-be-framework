# Controllers and routing

Controllers are classes annotated with `@RestController` whose public
instance methods declare routes with HTTP-method annotations. The generator
turns each route method into an *adapter* that binds parameters, validates
bodies, invokes your method and serializes the result — your controller
code stays plain Dart.

```dart
import 'package:diana/diana.dart';

part 'todo_controller.diana.dart';   // required: adapters generate here

@RestController('/todos')
class TodoController {
  final TodoService service;
  TodoController(this.service);      // constructor injection

  @Get()
  List<TodoDto> list(@QueryParam('limit', '20') int limit) =>
      service.list(limit);

  @Get('/:id')
  TodoDto getById(@PathParam() int id) => service.getOrThrow(id);

  @Post()
  @ResponseStatus(201)
  TodoDto create(@Body() CreateTodoRequest body) => service.create(body);

  @Delete('/:id')
  void remove(@PathParam() int id) => service.delete(id);
}
```

## Declaring routes

- `@RestController([path = '/', scope = Scope.singleton])` — mounts all
  routes under `path`. Controllers join the DI graph; see
  [scopes](dependency-injection.md#scopes) for request-scoped controllers.
- `@Get`, `@Post`, `@Put`, `@Delete`, `@Patch` — each takes an optional
  path relative to the controller: `@Get('/:id')`. Empty means the
  controller path itself.
- Paths use `:name` segments for path parameters (`/todos/:id`). Routing is
  a trie — matching is exact-segment based and fast; route registration
  order never affects matching.
- Base and route paths are joined and normalized: `'/todos' + '/:id'` →
  `/todos/:id`; trailing slashes are dropped.
- For methods without a shorthand (HEAD, OPTIONS), use the base annotation:
  `@HttpRoute('HEAD', '/status')`.
- Route methods must be **public instance methods**.
- A request to an existing path with an unregistered method returns
  **405 Method Not Allowed**; an unknown path returns the JSON **404**.

## Parameter binding

Every route-method parameter needs **exactly one** binding annotation — or
be of type `DianaRequest` for raw access:

| Annotation | Source | Notes |
|---|---|---|
| `@PathParam([name])` | `:name` path segment | Must be non-nullable — the segment always exists when the route matches. |
| `@QueryParam([name, defaultValue])` | query string | Nullable type ⇒ optional. `defaultValue` is written as a string and converted like the real value. |
| `@Header([name])` | request header | Case-insensitive. Nullable type ⇒ optional. |
| `@Body()` | JSON request body | See [bodies](#request-bodies). |
| *(none — `DianaRequest` type)* | the raw request | Full access: headers, attributes, body. |

`name` always defaults to the Dart parameter name.

**Supported types** for path/query/header: `String`, `int`, `double`,
`bool`, `num` — plus their nullable forms for query/header. `bool` accepts
`true`/`1`/`false`/`0` (case-insensitive).

**Conversion failures are automatic 400s** with precise messages:

```
GET /todos/abc
→ 400 {"error":"bad_request","message":"Path parameter 'id' must be int, got 'abc'."}
```

A missing required (non-nullable, no default) query parameter or header is
also a 400.

## Request bodies

`@Body()` accepts these parameter types:

| Type | Behaviour |
|---|---|
| `Map<String, dynamic>` | Raw decoded JSON object. |
| A DTO class | `Dto.fromJson(decodedMap)`; the class must expose `factory Dto.fromJson(Map<String, dynamic>)` (checked at build time). |
| `List<Dto>` | JSON array, each element through `fromJson`. |
| `List<String>` / `List<int>` / … / `List<dynamic>` | JSON array of primitives, `.cast<T>()`. |

Body handling is strict and automatic:

- Content type other than `application/json` (or `…+json`) → **415**.
  A missing content type is tolerated.
- Empty or malformed JSON, or the wrong JSON shape (array where an object
  is expected, and vice versa) → **400**.
- If the DTO carries [validation](validation.md) constraints, the generated
  validator runs before your method — an invalid payload never reaches you
  (structured **400**).
- Bodies larger than `server.maxBodyBytes` (default 10 MiB) → **413**,
  rejected while streaming, so an oversized body is never buffered in
  memory. Multipart uploads have their own cap, `server.multipart.maxSize`
  (also 10 MiB by default) — raise that one for large file uploads. Setting
  either key to `0` disables it. See
  [config keys](../reference/config-keys.md#bodies).

## Return types

| Declared return type | Response |
|---|---|
| a DTO with `toJson()` | `200`, `application/json`, `result.toJson()` |
| `List<Dto>` | `200`, JSON array of `toJson()` |
| `Map<String, dynamic>` (and other JSON primitives/collections) | `200`, JSON |
| `String` | `200`, `text/plain` |
| `void` | **204 No Content** |
| `DianaResponse` | passed through unchanged (full control) |
| `Stream<ServerSentEvent>` / `Stream<Dto>` | `200`, `text/event-stream` — see [Server-Sent Events](server-sent-events.md) |
| `Future<...>` of any of the above | awaited, then as above |

- `@ResponseStatus(code)` overrides the success status (`201` for a POST,
  etc.). It applies to JSON/text/void returns; a returned `DianaResponse`
  keeps its own status.
- A nullable DTO return (`TodoDto?`) serializes `null` as a JSON `null`
  body with the success status.
- Returning a type with neither `toJson()` nor JSON-primitive shape is a
  build error that tells you what to add.
- Bodies and responses default to JSON; routes opt into other formats
  (XML, custom codecs) with `@Consumes`/`@Produces` — see
  [Content negotiation](content-negotiation.md).

## Errors thrown from handlers

Anything thrown inside a route (or the services it calls) flows through the
exception pipeline — built-in `HttpException`s map to their status,
`@ControllerAdvice` handlers map domain exceptions, everything else becomes
an opaque 500. See [Error handling](error-handling.md).

## Under the hood

For each route the generator emits a public adapter in the controller's
part file:

```dart
Future<DianaResponse> $diana$TodoController$create(
  TodoController c,
  DianaRequest req,
) async {
  final $a0 = CreateTodoRequest.fromJson(await decodeJsonMapBody(req));
  const $CreateTodoRequestValidator().validate($a0).throwIfInvalid();
  final result = c.create($a0);
  return DianaResponse.json(result.toJson(), statusCode: 201);
}
```

and registers it in the composition root:

```dart
server.register(
  HttpMethod.post,
  '/todos',
  (req) => $diana$TodoController$create(ctx.todoController, req),
  middleware: [ctx.apiKeyMiddleware],
);
```

See [Generated code](../reference/generated-code.md) for the full picture.

## Current limitations

- Types referenced in route signatures must be imported **without an import
  prefix** in the controller library (generated part files reproduce type
  names as written, minus prefixes).
- One binding annotation per parameter; combining two is a build error.
