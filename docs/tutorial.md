# Tutorial: build a bookstore API

In this tutorial you build a complete REST API with Diana, one feature at a
time. Every step compiles and runs, so you can follow along and `curl` as
you go.

What you'll cover:

1. [Project setup](#1-project-setup)
2. [First endpoint](#2-first-endpoint)
3. [Dependency injection: repository and service](#3-dependency-injection)
4. [Path and query parameters](#4-path-and-query-parameters)
5. [Request bodies and validation](#5-request-bodies-and-validation)
6. [Domain errors and @ControllerAdvice](#6-domain-errors-and-controlleradvice)
7. [Middleware](#7-middleware)
8. [Configuration](#8-configuration)
9. [Testing](#9-testing)
10. [Development workflow](#10-development-workflow)

The finished project layout:

```
bookstore/
├── application.yaml
├── bin/server.dart
├── lib/
│   ├── app.dart
│   ├── advice/error_advice.dart
│   ├── controllers/book_controller.dart
│   ├── dto/{book_dto.dart, create_book_request.dart}
│   ├── errors/book_not_found.dart
│   ├── middleware/{timing_middleware.dart, admin_guard.dart}
│   ├── repositories/book_repository.dart
│   └── services/book_service.dart
└── test/api_test.dart
```

---

## 1. Project setup

```bash
dart create -t console bookstore
cd bookstore
```

Edit `pubspec.yaml`:

```yaml
name: bookstore
environment:
  sdk: ^3.6.0

dependencies:
  diana: ^0.15.0

dev_dependencies:
  build_runner: ^2.12.0
  diana_generator: ^0.15.0
  test: ^1.25.0
```

```bash
dart pub get
```

Declare the application entrypoint — one class, one annotation, empty body:

```dart
// lib/app.dart
import 'package:diana/diana.dart';

@DianaApplication()
class BookstoreApp {}
```

And the launcher:

```dart
// bin/server.dart
import 'package:bookstore/app.diana_app.dart';

Future<void> main() => runDiana();
```

`app.diana_app.dart` doesn't exist yet — the generator creates it in the
next step.

## 2. First endpoint

```dart
// lib/controllers/book_controller.dart
import 'package:diana/diana.dart';

part 'book_controller.diana.dart';

@RestController('/books')
class BookController {
  @Get('/ping')
  String ping() => 'pong';
}
```

Two things to note:

- `@RestController('/books')` mounts every route in the class under
  `/books`.
- The `part` directive is **required** in any library that declares routes:
  the generator writes the route adapters into
  `book_controller.diana.dart`. Forget it and the build tells you exactly
  what line to add.

Generate and run:

```bash
$ dart run build_runner build
$ dart run bin/server.dart
[diana] Listening on http://0.0.0.0:8080
```

```bash
$ curl localhost:8080/books/ping
pong
```

A `String` return becomes a `text/plain` response. Anything unmatched gets a
JSON 404:

```bash
$ curl localhost:8080/nope
{"error":"not_found","message":"No route matches this path."}
```

## 3. Dependency injection

Diana instantiates your classes through their constructors and resolves
every parameter **at build time**. Let's add a data layer.

The DTO (plain Dart, JSON by convention — see
[JSON serialization](guides/json.md)):

```dart
// lib/dto/book_dto.dart
class BookDto {
  final int id;
  final String title;
  final String author;

  const BookDto({required this.id, required this.title, required this.author});

  factory BookDto.fromJson(Map<String, dynamic> json) => BookDto(
        id: json['id'] as int,
        title: json['title'] as String,
        author: json['author'] as String,
      );

  Map<String, dynamic> toJson() =>
      {'id': id, 'title': title, 'author': author};
}
```

A repository interface with an in-memory implementation:

```dart
// lib/repositories/book_repository.dart
import 'package:diana/diana.dart';

import '../dto/book_dto.dart';

abstract interface class BookRepository {
  List<BookDto> findAll({int limit});
  BookDto? find(int id);
  BookDto save(String title, String author);
}

@Repository()
class InMemoryBookRepository implements BookRepository {
  final _books = <int, BookDto>{
    1: const BookDto(id: 1, title: 'Dart in Action', author: 'M. Ford'),
  };
  int _nextId = 2;

  @override
  List<BookDto> findAll({int limit = 20}) =>
      _books.values.take(limit).toList();

  @override
  BookDto? find(int id) => _books[id];

  @override
  BookDto save(String title, String author) {
    final book = BookDto(id: _nextId++, title: title, author: author);
    _books[book.id] = book;
    return book;
  }
}
```

A service that depends on the **interface**:

```dart
// lib/services/book_service.dart
import 'package:diana/diana.dart';

import '../dto/book_dto.dart';
import '../repositories/book_repository.dart';

@Service()
class BookService {
  final BookRepository repo;

  BookService(this.repo);

  List<BookDto> list(int limit) => repo.findAll(limit: limit);
}
```

`BookService` asks for `BookRepository`; `InMemoryBookRepository` is the
only provider implementing it, so Diana **auto-binds** them. If you later
add a second implementation, the build fails with an ambiguity error and
tells you to pick one with `@Named` or `as:` — see
[Dependency injection](guides/dependency-injection.md).

Inject the service into the controller and add a real route:

```dart
@RestController('/books')
class BookController {
  final BookService service;

  BookController(this.service);

  @Get()
  List<BookDto> list() => service.list(20);
}
```

Rebuild and try it:

```bash
$ dart run build_runner build && dart run bin/server.dart
$ curl localhost:8080/books
[{"id":1,"title":"Dart in Action","author":"M. Ford"}]
```

Peek at `lib/app.diana_app.dart` to see what the generator wired:

```dart
class DianaContext {
  DianaContext(this.config);
  final DianaConfig config;
  late final InMemoryBookRepository inMemoryBookRepository =
      InMemoryBookRepository();
  late final BookService bookService = BookService(inMemoryBookRepository);
  late final BookController bookController = BookController(bookService);
}
```

This class **is** the DI container — plain typed fields in dependency
order. No maps, no reflection, nothing to misconfigure at runtime.

## 4. Path and query parameters

```dart
// in BookController
@Get()
List<BookDto> list(@QueryParam('limit', '20') int limit) =>
    service.list(limit);

@Get('/:id')
BookDto getById(@PathParam() int id) => service.getOrThrow(id);
```

And in `BookService`:

```dart
BookDto getOrThrow(int id) =>
    repo.find(id) ?? (throw NotFoundException('No book with id $id.'));
```

Parameter binding rules (full list in
[Controllers and routing](guides/controllers.md)):

- `@PathParam()` binds `:id` from the route; the name defaults to the Dart
  parameter name. Path parameters must be non-nullable.
- `@QueryParam('limit', '20')` binds `?limit=`; the second positional
  argument is the default (always written as a string). A nullable type
  (`int?`) makes the parameter optional instead.
- Values convert to `String`, `int`, `double`, `bool` or `num`. A failed
  conversion is an automatic 400 — no code on your part:

```bash
$ curl localhost:8080/books/abc
{"error":"bad_request","message":"Path parameter 'id' must be int, got 'abc'."}
```

`NotFoundException` is one of Diana's built-in HTTP exceptions — thrown
anywhere during a request, it becomes a JSON response with its status code:

```bash
$ curl localhost:8080/books/99
{"error":"not_found","message":"No book with id 99."}
```

## 5. Request bodies and validation

Create a request DTO with constraint annotations. Libraries whose classes
carry constraints also need a `part` directive (the generator writes a
validator there):

```dart
// lib/dto/create_book_request.dart
import 'package:diana/diana.dart';

part 'create_book_request.diana.dart';

class CreateBookRequest {
  @NotBlank(message: 'title is required')
  @Size(max: 200)
  final String title;

  @NotBlank()
  final String author;

  CreateBookRequest({required this.title, required this.author});

  factory CreateBookRequest.fromJson(Map<String, dynamic> json) =>
      CreateBookRequest(
        title: json['title'] as String? ?? '',
        author: json['author'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {'title': title, 'author': author};
}
```

The route:

```dart
// in BookController
@Post()
@ResponseStatus(201)
BookDto create(@Body() CreateBookRequest body) => service.create(body);
```

```dart
// in BookService
BookDto create(CreateBookRequest request) =>
    repo.save(request.title, request.author);
```

The generated adapter decodes the JSON body, builds the DTO with
`fromJson`, runs the generated validator, and only then calls your method.
You never see an invalid object:

```bash
$ curl -X POST localhost:8080/books -H 'Content-Type: application/json' \
       -d '{"title": "Effective Dart", "author": "The Dart Team"}'
{"id":2,"title":"Effective Dart","author":"The Dart Team"}     # 201

$ curl -X POST localhost:8080/books -H 'Content-Type: application/json' \
       -d '{"title": "   "}'
{"error":"validation_failed","fields":{"title":["title is required"],"author":["must not be blank"]}}
```

Malformed JSON is a 400, and a non-JSON content type is a 415 —
automatically. All constraints and the cascade rules (`@Valid`) are in the
[validation guide](guides/validation.md).

## 6. Domain errors and @ControllerAdvice

Built-in exceptions are convenient, but a domain layer usually shouldn't
know about HTTP. Define a domain error:

```dart
// lib/errors/book_not_found.dart
class BookNotFound implements Exception {
  final int id;
  const BookNotFound(this.id);
}
```

Throw it from the service instead of `NotFoundException`:

```dart
BookDto getOrThrow(int id) => repo.find(id) ?? (throw BookNotFound(id));
```

And map it to HTTP in one place:

```dart
// lib/advice/error_advice.dart
import 'package:diana/diana.dart';

import '../errors/book_not_found.dart';

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

```bash
$ curl localhost:8080/books/99
{"error":"book_not_found","id":99,"path":"/books/99"}
```

Handlers are selected by exception type, most specific subtype first. Any
exception nothing handles becomes an **opaque** 500 — internals never leak
to clients. Details in [Error handling](guides/error-handling.md).

## 7. Middleware

Middleware wrap request handling, Spring-interceptor style. A global one
that times every request:

```dart
// lib/middleware/timing_middleware.dart
import 'package:diana/diana.dart';

@GlobalMiddleware(order: 0)
class TimingMiddleware implements Middleware {
  @override
  Future<DianaResponse> handle(DianaRequest request, Next next) async {
    final watch = Stopwatch()..start();
    final response = await next(request);
    return response.copyWith(headers: {
      ...response.headers,
      'x-response-time-ms': '${watch.elapsedMilliseconds}',
    });
  }
}
```

And a guard applied to a single route. Middleware are regular injectable
components — constructor injection (including `@Value`, next section)
works:

```dart
// lib/middleware/admin_guard.dart
import 'package:diana/diana.dart';

@Component()
class AdminGuard implements Middleware {
  final String apiKey;

  AdminGuard(@Value('app.adminKey', defaultValue: 'changeme') this.apiKey);

  @override
  Future<DianaResponse> handle(DianaRequest request, Next next) async {
    if (request.header('x-api-key') != apiKey) {
      return DianaResponse.json({'error': 'unauthorized'}, statusCode: 401);
    }
    return await next(request);
  }
}
```

Apply it with `@UseMiddleware` (works on a method or on the whole
controller):

```dart
@Post()
@ResponseStatus(201)
@UseMiddleware([AdminGuard])
BookDto create(@Body() CreateBookRequest body) => service.create(body);
```

```bash
$ curl -X POST localhost:8080/books -d '{}'                      # 401
$ curl -s -D - -o /dev/null localhost:8080/books | grep x-response-time
x-response-time-ms: 0
```

Execution order is always *global (by `order`) → controller-level →
route-level → handler*, and returning without calling `next` short-circuits
the chain. See [Middleware](guides/middleware.md).

## 8. Configuration

Create `application.yaml` in the project root:

```yaml
server:
  port: 8080

app:
  adminKey: s3cret
  info:
    name: bookstore
    version: 1.0.0
```

Nested keys flatten to dot-keys (`app.adminKey`), and **any** key can be
overridden by the corresponding environment variable — dots become
underscores, upper-cased:

```bash
$ SERVER_PORT=9000 APP_ADMINKEY=other dart run bin/server.dart
[diana] Listening on http://0.0.0.0:9000
```

You've already used `@Value` in `AdminGuard`. To bind a whole section as a
typed object, use `@ConfigurationProperties` (also needs a `part`
directive):

```dart
// lib/config/app_info.dart
import 'package:diana/diana.dart';

part 'app_info.diana.dart';

@ConfigurationProperties('app.info')
class AppInfo {
  final String name;
  final String version;

  const AppInfo({required this.name, required this.version});
}
```

The class becomes injectable like any other component:

```dart
@RestController('/info')
class InfoController {
  final AppInfo info;
  InfoController(this.info);

  @Get()
  Map<String, dynamic> get() => {'name': info.name, 'version': info.version};
}
```

A required key that's missing from every source fails **at startup** with a
message naming both the key and the environment variable that could supply
it. See [Configuration](guides/configuration.md).

## 9. Testing

The generated `buildDianaServer()` accepts a config override and can bind
to an ephemeral port — ideal for end-to-end tests without touching the real
`application.yaml`:

```dart
// test/api_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:bookstore/app.diana_app.dart';
import 'package:diana/diana.dart';
import 'package:test/test.dart';

void main() {
  late DianaServer server;
  late int port;

  setUpAll(() async {
    server = await buildDianaServer(
      config: DianaConfig({'app.adminKey': 'test-key'}),
    );
    await server.serve(port: 0, quiet: true); // OS-assigned port
    port = server.port!;
  });

  tearDownAll(() => server.close());

  test('lists the seeded book', () async {
    final client = HttpClient();
    final req =
        await client.getUrl(Uri.parse('http://127.0.0.1:$port/books'));
    final res = await req.close();
    final body = jsonDecode(await res.transform(utf8.decoder).join());
    expect(res.statusCode, 200);
    expect(body, hasLength(1));
    client.close();
  });
}
```

For plain unit tests of your object graph — no HTTP — use the generated
`buildDianaContext()`:

```dart
final ctx = buildDianaContext();
expect(ctx.bookService.list(10), hasLength(1));
```

More patterns (unit-testing middleware, validators, config) in the
[testing guide](guides/testing.md).

## 10. Development workflow

Two terminals:

```bash
# terminal 1 — regenerate on save
dart run build_runner watch

# terminal 2 — run with the VM service so relic can hot-reload routes
dart run --enable-vm-service bin/server.dart
```

Handler-body edits apply on hot reload. Changes that reshape the DI graph
(new providers, changed constructors) rewrite the composition root and need
a process restart.

## Where to go next

- Deep-dive any feature in the [guides](README.md#guides)
- Look anything up in the [reference](README.md#reference)
- Browse the finished [todo_api example](../examples/todo_api) in this
  repository — it exercises every feature and has a full e2e test suite
