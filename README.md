# Diana

A Spring-inspired, annotation-driven backend framework for Dart.

Diana brings the Spring Boot developer experience to Dart — declarative
controllers, dependency injection, middleware, configuration and validation —
with one key difference: **everything is resolved at compile time**. There is
no reflection, no runtime container and no classpath scanning. A code
generator (built on `build_runner`, riverpod-style) resolves your dependency
graph and wires your application while you build, so missing dependencies,
ambiguous bindings and dependency cycles are **build errors, not runtime
crashes** — and startup is instant.

HTTP is served by [relic](https://pub.dev/packages/relic), the
high-performance typed successor of shelf by the Serverpod team. Diana fully
abstracts it: your code never touches the HTTP engine.

```dart
@RestController('/todos')
class TodoController {
  final TodoService service;
  TodoController(this.service); // injected at compile time

  @Get('/:id')
  TodoDto getById(@PathParam() int id) => service.getOrThrow(id);

  @Post()
  @ResponseStatus(201)
  TodoDto create(@Body() CreateTodoRequest body) => service.create(body);
}
```

## Features

- **Compile-time dependency injection** — `@Service`, `@Repository`,
  `@Component`, `@Injectable(scope:, as:, name:)` with constructor injection,
  interface auto-binding, `@Named` qualifiers and `singleton`/`request`/
  `transient` scopes. The generated `DianaContext` *is* the container: typed
  fields in topological order, no maps, no `Type` lookups.
- **Declarative REST controllers** — `@RestController`, `@Get`/`@Post`/
  `@Put`/`@Delete`/`@Patch`, `@PathParam`, `@QueryParam`, `@Header`, `@Body`,
  `@ResponseStatus`, with automatic JSON (de)serialization. DTOs follow the
  `fromJson`/`toJson` convention — hand-written or via `json_serializable`,
  both verified at build time with actionable errors.
- **Middleware** — a `Middleware` interface with `@GlobalMiddleware(order:)`
  and `@UseMiddleware([...])` at controller or route level; middleware join
  the DI graph like any other component.
- **Configuration** — `application.yaml` flattened to dot-keys and overridden
  by environment variables (`server.port` ← `SERVER_PORT`); inject values
  with `@Value('app.key')` or bind whole sections with
  `@ConfigurationProperties('prefix')`. Missing required keys fail at
  startup, not on the first request.
- **Validation** — `@NotNull`, `@NotBlank`, `@NotEmpty`, `@Min`, `@Max`,
  `@Size`, `@Pattern`, `@Email` and cascading `@Valid` on DTO fields.
  Invalid bodies produce a structured 400:
  `{"error": "validation_failed", "fields": {"title": ["title is required"]}}`.
- **Exception handling** — an `HttpException` hierarchy mapped to JSON
  responses, plus `@ControllerAdvice`/`@ExceptionHandler` to map domain
  exceptions, dispatched by subtype specificity. Unhandled errors become
  opaque 500s (details never leak to clients).

## Documentation

Full documentation lives in [`docs/`](docs/README.md):
[getting started](docs/getting-started.md) ·
[step-by-step tutorial](docs/tutorial.md) ·
[feature guides](docs/README.md#guides) ·
[complete reference](docs/README.md#reference) (annotations, runtime API,
generated code, build diagnostics) ·
[architecture](docs/architecture.md) ·
[troubleshooting & FAQ](docs/troubleshooting.md).

## Quickstart

**1. Depend on Diana:**

```yaml
dependencies:
  diana: ^0.1.0

dev_dependencies:
  build_runner: ^2.12.0
  diana_generator: ^0.1.0
```

**2. Declare the application entrypoint** (`lib/app.dart`):

```dart
import 'package:diana/diana.dart';

@DianaApplication(configFile: 'application.yaml')
class MyApp {}
```

**3. Write components** — a repository, a service, a controller:

```dart
@Repository()
class InMemoryTodoRepository implements TodoRepository { /* ... */ }

@Service()
class TodoService {
  TodoService(this.repo); // TodoRepository auto-binds: one implementation
  final TodoRepository repo;
}
```

Controllers that declare routes need a `part` directive for their generated
adapters:

```dart
part 'todo_controller.diana.dart';

@RestController('/todos')
class TodoController { /* ... */ }
```

**4. Generate and run:**

```bash
dart run build_runner build   # or `watch` during development
dart run bin/server.dart
```

with `bin/server.dart`:

```dart
import 'package:my_app/app.diana_app.dart';

Future<void> main() => runDiana();
```

The generator emits `lib/app.diana_app.dart` containing the wired
`DianaContext`, `buildDianaServer()` and `runDiana()`. In tests, call
`buildDianaServer()` and `server.serve(port: 0)` to get an ephemeral port.

## Packages

| Package | Role |
|---|---|
| [`packages/diana`](packages/diana) | Runtime: server, pipeline, config, validation helpers. Re-exports the annotations. |
| [`packages/diana_annotation`](packages/diana_annotation) | The annotations. Pure constants, no dependencies. |
| [`packages/diana_generator`](packages/diana_generator) | The build_runner builders: metadata extraction, DI graph resolution, code emission. |
| [`examples/todo_api`](examples/todo_api) | Complete example: controllers, DI, middleware, config, validation, advice. |

## How it works

Three builders run in sequence:

1. **`diana_metadata`** scans each library for Diana annotations and writes a
   compact JSON summary to the build cache.
2. **`diana_part`** emits a `.diana.dart` part file per library: route
   adapters (parameter binding → validation → invocation → serialization),
   DTO validators and configuration binders.
3. **`diana_bootstrap`** aggregates all summaries, resolves the dependency
   graph (topological sort; cycles, duplicates, ambiguities and scope
   violations are reported together as build errors) and emits the
   composition root next to your `@DianaApplication`.

## Development (this repo)

Dart ≥ 3.6 (pub workspaces). From the repo root:

```bash
dart pub get
cd examples/todo_api && dart run build_runner build && cd ../..
dart analyze
dart test packages/diana packages/diana_generator examples/todo_api
```

### Hot reload

Run `dart run build_runner watch` in one terminal and
`dart run --enable-vm-service bin/server.dart` in another. relic re-mounts
routes on VM hot reload; handler-body edits apply live. Changes that reshape
the DI graph rewrite the bootstrap file and need a process restart.

## Status / Roadmap

Early but functional MVP. Planned next: request-scoped providers exercised
end-to-end, Diana-native JSON codegen, OpenAPI generation, WebSocket support,
cross-package component scanning, profiles (`application-dev.yaml`).
