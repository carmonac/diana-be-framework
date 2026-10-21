# Diana

A Spring-inspired, annotation-driven backend framework for Dart.

**📖 Documentation: <https://carmonac.github.io/diana-be-framework/>**

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
- **WebSockets** — Spring-style `@WebSocketController('/ws/path')` on a
  `WebSocketHandler` implementation: lifecycle callbacks
  (`onOpen`/`onMessage`/`onError`/`onClose`), typed sessions with path
  parameters and attributes, shared or per-connection handler instances,
  and `@UseMiddleware` handshake interceptors.
- **Lifecycle & operations** — `@PostConstruct`/`@PreDestroy` hooks,
  graceful shutdown on SIGINT/SIGTERM, `DianaOverrides` for tests
  (`@MockBean`-style), configuration profiles
  (`application-{profile}.yaml`), HTTPS, experimental multi-isolate
  serving.
- **Native JSON** — `@Json`/`@JsonField` generate the codecs; DTOs carry
  zero serialization boilerplate (hand-written and json_serializable DTOs
  keep working).
- **Web essentials** — CORS (`@CrossOrigin` + config, automatic
  preflight), static file serving with SPA fallback, multipart uploads
  (`@Body() FormData`) with size limits, raw text bodies, `Accept`-based
  406 guard.
- **Platform** — build-time OpenAPI 3 document served at `/openapi.json`,
  actuator-style `/actuator/health` (via `HealthIndicator`) and
  `/actuator/info`, `@Scheduled` fixed-rate/fixed-delay/cron tasks.
- **Content negotiation** — pluggable `BodyCodec` formats discovered
  through DI (XML included: `@Component() class AppXmlCodec extends
  XmlCodec {}`), with Spring-style `@Consumes`/`@Produces` on controllers
  or routes (415/406 semantics, projected into OpenAPI).
- **Server-Sent Events** — return `Stream<ServerSentEvent>` (or
  `Stream<Dto>`) from a route: spec-compliant `text/event-stream` with
  keep-alive heartbeats, unbuffered writes and disconnect cleanup.
- **gRPC** — `@GrpcService()` on your protoc-generated service: it joins
  the DI graph and is served next to HTTP (own port, shared lifecycle) via
  the optional [`diana_grpc`](packages/diana_grpc) package.
- **STOMP messaging** — STOMP 1.2 over WebSockets: `@MessageMapping`/
  `@SendTo` handlers, an in-memory topic broker, an injectable
  `StompPublisher`, ack/transaction/heartbeat support, and cross-isolate
  topic delivery — all in `package:diana`, no extra dependency.
- **Application events** — Spring-style `@EventListener` methods and an
  injectable `DianaEventPublisher`: awaited local dispatch with subtype
  matching, plus `broadcast()` to deliver an event to every isolate when
  serving multi-isolate.
- **Security** — the optional [`diana_auth`](packages/diana_auth) package:
  pluggable authenticator strategies (JWT Bearer with in-package HS256 and
  RS256/JWKS — pure-Dart RSA verification, IdP key rotation handled,
  HTTP Basic, API key), `@Secured`/`@RolesAllowed` guards (401/403) and
  `@Principal` binding, enforced across HTTP, WebSocket handshakes and
  gRPC.
- **Observability** — the optional
  [`diana_observability`](packages/diana_observability) package: in-package
  Prometheus metrics at `/actuator/metrics` (HTTP, database, scheduler and
  event series, labelled by route template), OpenTelemetry tracing, an
  injectable `MeterRegistry`, and Kubernetes-style liveness/readiness
  probes.
- **Aspects** — `@Timed`, `@Cacheable` (in-memory TTL+LRU by default, or a
  pluggable `DianaCacheStore` for shared backends), `@Retryable` and
  `@CircuitBreaker` on service methods, composed with `@Transactional` at
  compile time through generated proxies — Spring AOP without reflection.
- **Persistence** — the optional [`diana_data`](packages/diana_data) package:
  an injectable `Database` query executor over
  [knex_dart](https://pub.dev/packages/knex_dart), Spring-style
  `@Transactional` methods with ambient (savepoint-nesting) transactions,
  **Spring-Data-style query methods** (abstract repositories whose
  `findByTitleContainsOrderByIdDesc(...)` methods are generated from their
  names), opt-in SQL migrations and a database health check —
  driver-agnostic (you pick Postgres/SQLite/…).

## Documentation

Full documentation is published at
<https://carmonac.github.io/diana-be-framework/> and its sources live in
[`docs/`](docs/README.md):
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
  diana: ^0.15.0

dev_dependencies:
  build_runner: ^2.12.0
  diana_generator: ^0.15.0
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
`DianaContext`, `buildDianaApp()`, `buildDianaServer()` and `runDiana()`
(which adds lifecycle + graceful shutdown). In tests, call
`buildDianaServer()` and `server.serve(port: 0)` for an ephemeral port, and
pass `overrides:` to swap providers.

## Packages

| Package | Role |
|---|---|
| [`packages/diana`](packages/diana) | Runtime: server, pipeline, config, validation helpers. Re-exports the annotations. |
| [`packages/diana_annotation`](packages/diana_annotation) | The annotations. Pure constants, no dependencies. |
| [`packages/diana_generator`](packages/diana_generator) | The build_runner builders: metadata extraction, DI graph resolution, code emission. |
| [`packages/diana_grpc`](packages/diana_grpc) | Optional gRPC runtime (`DianaGrpcServer`) — the only package depending on `package:grpc`. |
| [`packages/diana_auth`](packages/diana_auth) | Optional security: authenticator strategies, guards, JWT — the only package depending on `package:crypto`. |
| [`packages/diana_data`](packages/diana_data) | Optional persistence: injectable query executor, `@Transactional`, migrations — the only package depending on `knex_dart`. |
| [`packages/diana_observability`](packages/diana_observability) | Optional observability: Prometheus metrics, OpenTelemetry tracing, liveness/readiness — the only package depending on `package:opentelemetry`. |
| [`examples/todo_api`](examples/todo_api) | Complete example: controllers, DI, middleware, config, validation, advice, XML, SSE, events, auth. |
| [`examples/greeter_grpc`](examples/greeter_grpc) | gRPC + HTTP side by side from one DI graph. |
| [`examples/blog_api`](examples/blog_api) | Persistence with diana_data over SQLite: migrations, repository, transactions. |

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
tool/verify.sh   # pub get, builds, analyze, all test suites, determinism
```

### Hot reload

Run `dart run build_runner watch` in one terminal and
`dart run --enable-vm-service bin/server.dart` in another. relic re-mounts
routes on VM hot reload; handler-body edits apply live. Changes that reshape
the DI graph rewrite the bootstrap file and need a process restart.

## Status / Roadmap

v0.15: the Spring-parity feature set above — including content negotiation
(XML), Server-Sent Events, gRPC, application events with a cross-isolate
bridge, authentication/authorization (`diana_auth`, HS256 + RS256/JWKS),
persistence with `@Transactional` and Spring-Data-style query methods
(`diana_data`), observability (`diana_observability`: Prometheus metrics +
OpenTelemetry tracing), compile-time aspects (`@Timed`/`@Cacheable`/
`@Retryable`/`@CircuitBreaker`, with a pluggable `DianaCacheStore`), cron
scheduling, and STOMP messaging over WebSockets — fully tested. The
original roadmap is complete; next steps are driven by real-world usage.

## License

Diana is released under the [MIT License](LICENSE).
