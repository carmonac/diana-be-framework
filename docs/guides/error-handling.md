# Error handling

Every request runs inside Diana's exception boundary. Whatever is thrown —
from a handler, a service or middleware — is turned into a JSON error
response through a fixed pipeline. Internals never leak: an unrecognized
exception is an opaque 500.

## The pipeline

When something is thrown, the first match wins:

1. **`ValidationException`** → `400` with the
   [structured field map](validation.md#the-error-response).
2. **`@ControllerAdvice` handlers** (your generated advice chain) — checked
   by exception type, most specific subtype first.
3. **`HttpException`** (Diana's hierarchy) → its status code:
   `{"error": <reason>, "message": <message>}`.
4. **Anything else** → `500 {"error": "internal_server_error"}`; the actual
   error and stack trace go to the server's `onUnhandled` callback (default:
   printed), never to the client.

## Built-in HTTP exceptions

Throw these anywhere for an immediate, correctly-shaped error response:

| Exception | Status | `error` field |
|---|---|---|
| `BadRequestException(message)` | 400 | `bad_request` |
| `UnauthorizedException([message])` | 401 | `unauthorized` |
| `ForbiddenException([message])` | 403 | `forbidden` |
| `NotFoundException([message])` | 404 | `not_found` |
| `ConflictException(message)` | 409 | `conflict` |
| `UnsupportedMediaTypeException(message)` | 415 | `unsupported_media_type` |
| `UnprocessableEntityException(message)` | 422 | `unprocessable_entity` |
| `InternalServerErrorException([message])` | 500 | `internal_server_error` |
| `HttpException(status, message, {reason})` | any | custom |

```dart
TodoDto getOrThrow(int id) =>
    repo.find(id) ?? (throw NotFoundException('No todo with id $id.'));
```

```json
HTTP 404
{"error": "not_found", "message": "No todo with id 42."}
```

Parameter-binding and body-decoding failures throw these internally, which
is why a bad `:id` is automatically a 400 and a non-JSON body a 415.

## @ControllerAdvice — mapping domain exceptions

Domain code often shouldn't know about HTTP. Keep domain exceptions pure
and map them in one place:

```dart
// domain
class BookNotFound implements Exception {
  final int id;
  const BookNotFound(this.id);
}

// web layer
@ControllerAdvice()
class ErrorAdvice {
  @ExceptionHandler(BookNotFound)
  DianaResponse onBookNotFound(BookNotFound e, DianaRequest req) =>
      DianaResponse.json(
        {'error': 'book_not_found', 'id': e.id, 'path': req.path},
        statusCode: 404,
      );
}
```

Rules (checked at build time):

- `@ControllerAdvice` classes are injectable singletons — constructor
  injection works. They must declare at least one handler.
- Handler signature: `(E exception)` or `(E exception, DianaRequest
  request)`, where `E` is exactly the type named in
  `@ExceptionHandler(E)`.
- Return type: `DianaResponse` or `Future<DianaResponse>`.
- A handler also catches **subtypes** of its exception type. When several
  handlers match, the **most specific type wins** (a `DerivedError` handler
  beats a `BaseError` handler regardless of declaration order); exact ties
  fall back to declaration order.
- Advice handlers apply globally — to every route, and to middleware too.

You may register multiple advice classes; their handlers merge into one
chain.

## Customizing unhandled-error logging

The generated `buildDianaServer()` wires the advice chain automatically.
The `onUnhandled` hook belongs to `DianaServer`; today it defaults to
printing to stdout. Constructing a `DianaServer` manually (advanced) lets
you replace it — see the
[runtime reference](../reference/runtime.md#dianaserver).
