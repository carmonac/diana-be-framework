# Getting started

This page takes you from an empty directory to a running HTTP server.
For a full walkthrough of every feature, continue with the
[tutorial](tutorial.md).

## 1. Create a project

```bash
dart create -t console my_api
cd my_api
```

## 2. Add dependencies

```yaml
# pubspec.yaml
dependencies:
  diana: ^0.1.0

dev_dependencies:
  build_runner: ^2.12.0
  diana_generator: ^0.1.0
```

> **Working inside the Diana monorepo?** Add your package to the `workspace:`
> list of the root `pubspec.yaml` and use `resolution: workspace` instead of
> version constraints.

Run `dart pub get`.

## 3. Declare the application entrypoint

Every Diana application has exactly one class annotated with
`@DianaApplication`, placed anywhere under `lib/` (convention:
`lib/app.dart`):

```dart
// lib/app.dart
import 'package:diana/diana.dart';

@DianaApplication()
class MyApp {}
```

The class body stays empty — it only anchors the generated code. The
generator emits `lib/app.diana_app.dart` next to it.

## 4. Write a controller

Controllers declare routes with annotations. Libraries that declare routes
need a `part` directive for their generated code:

```dart
// lib/controllers/hello_controller.dart
import 'package:diana/diana.dart';

part 'hello_controller.diana.dart';

@RestController('/hello')
class HelloController {
  @Get()
  Map<String, dynamic> hello() => {'message': 'Hello from Diana!'};

  @Get('/:name')
  String greet(@PathParam() String name) => 'Hello, $name!';
}
```

## 5. Generate

```bash
dart run build_runner build
```

This emits:

- `lib/controllers/hello_controller.diana.dart` — the route adapters
- `lib/app.diana_app.dart` — the composition root: `DianaContext`,
  `buildDianaServer()` and `runDiana()`

During development, use `dart run build_runner watch` to regenerate on
save.

## 6. Run

```dart
// bin/server.dart
import 'package:my_api/app.diana_app.dart';

Future<void> main() => runDiana();
```

```bash
$ dart run bin/server.dart
[diana] Listening on http://0.0.0.0:8080

$ curl localhost:8080/hello
{"message":"Hello from Diana!"}

$ curl localhost:8080/hello/dart
Hello, dart!
```

The default address is `0.0.0.0:8080`; override it with an
`application.yaml` (`server.host`, `server.port`) or the environment
variables `SERVER_HOST` / `SERVER_PORT` — see
[Configuration](guides/configuration.md).

## Next steps

- The [tutorial](tutorial.md) builds a complete API: dependency injection,
  request bodies, validation, middleware, configuration, error handling and
  tests.
- The [guides](README.md#guides) cover each feature in depth.
