# Testing

Diana applications test at three levels, all without mocking frameworks or
special test kits: your classes are plain Dart, and the generated wiring is
callable from tests.

## 1. Unit tests — plain Dart

Services, repositories, middleware and validators are ordinary classes.
Construct them by hand:

```dart
test('service reports missing todos', () {
  final service = TodoService(InMemoryTodoRepository());
  expect(() => service.getOrThrow(99), throwsA(isA<TodoNotFoundError>()));
});
```

Middleware unit-test naturally thanks to the functional `Next` parameter:

```dart
test('guard rejects a missing api key', () async {
  final guard = ApiKeyMiddleware('secret');
  final response = await guard.handle(
    DianaRequest(method: HttpMethod.get, uri: Uri.parse('/x')),
    (req) async => const DianaResponse.text('reached handler'),
  );
  expect(response.statusCode, 401);
});
```

`DianaRequest` is directly constructible for tests — pass `pathParameters`,
`headers` and a `bodyReader` as needed (see the
[runtime reference](../reference/runtime.md#dianarequest)).

Generated validators are constants:

```dart
final result = const $CreateTodoRequestValidator()
    .validate(CreateTodoRequest(title: '  '));
expect(result.isValid, isFalse);
```

## 2. Wiring tests — the generated context

`buildDianaContext({DianaConfig? config})` constructs the full DI graph
without any HTTP:

```dart
test('the graph wires singletons', () {
  final ctx = buildDianaContext(
    config: DianaConfig({'app.greeting': 'hi'}),
  );
  expect(identical(ctx.todoService.repo, ctx.inMemoryTodoRepository), isTrue);
});
```

Because resolution happened at build time, this test mostly guards runtime
behaviour (constructor side effects, config values) — a broken graph would
not have compiled.

## 3. End-to-end tests — real HTTP

`buildDianaServer()` + `serve(port: 0)` boots the actual application on an
OS-assigned port. Inject test configuration instead of relying on
`application.yaml`:

```dart
import 'dart:convert';
import 'dart:io';

import 'package:diana/diana.dart';
import 'package:test/test.dart';
import 'package:todo_api/app.diana_app.dart';

void main() {
  late DianaServer server;
  late int port;

  setUpAll(() async {
    server = await buildDianaServer(
      config: DianaConfig({'app.apiKey': 'test-key'}),
    );
    await server.serve(port: 0, quiet: true);
    port = server.port!;
  });

  tearDownAll(() => server.close());

  Future<(int, dynamic)> get(String path) async {
    final client = HttpClient();
    try {
      final req =
          await client.getUrl(Uri.parse('http://127.0.0.1:$port$path'));
      final res = await req.close();
      final text = await res.transform(utf8.decoder).join();
      return (res.statusCode, text.isEmpty ? null : jsonDecode(text));
    } finally {
      client.close();
    }
  }

  test('binds path params and maps domain errors', () async {
    final (status, body) = await get('/todos/999');
    expect(status, 404);
    expect(body, containsPair('error', 'todo_not_found'));
  });
}
```

What to cover end-to-end (the
[example's suite](../../examples/todo_api/test/api_test.dart) is a
template):

- happy paths per route, including created/deleted state
- binding failures (bad path param → 400, wrong content type → 415,
  malformed JSON → 400)
- validation failures (400 with the `fields` map)
- middleware effects (short-circuit status codes, injected headers)
- advice-mapped errors and the opaque 500 for unexpected ones

## Testing generators (contributing to Diana itself)

`diana_generator`'s own tests use `build_test`'s `testBuilder` with
in-memory sources, exact-message assertions for every diagnostic, and pure
table-driven tests for the graph resolver. See
`packages/diana_generator/test/` and the
[architecture page](../architecture.md#testing-strategy-the-frameworks-own).

## CI recipe

```bash
dart pub get
(cd examples/todo_api && dart run build_runner build)   # or your app
dart analyze --fatal-infos
dart test
git diff --exit-code   # generated code must be committed and in sync
```

Generated output is deterministic, so the final `git diff` check catches
stale generated files.
