# Diana Documentation

Diana is a Spring-inspired, annotation-driven backend framework for Dart.
Everything — dependency injection, routing, middleware wiring, validation —
is resolved **at compile time** by a code generator. There is no reflection
and no runtime container: configuration mistakes are build errors, and
startup is instant.

## Where to start

| If you want to… | Read |
|---|---|
| Install Diana and serve your first request in 5 minutes | [Getting started](getting-started.md) |
| Build a complete API step by step | [Tutorial: build a bookstore API](tutorial.md) |
| Understand one feature in depth | The [guides](#guides) |
| Look up an annotation, class or error message | The [reference](#reference) |
| Understand how the generator works inside | [Architecture](architecture.md) |
| Fix a build or runtime problem | [Troubleshooting & FAQ](troubleshooting.md) |

## Guides

Task-oriented explanations of each feature:

- [Dependency injection](guides/dependency-injection.md) — providers,
  scopes, interface binding, qualifiers, the generated context
- [Controllers and routing](guides/controllers.md) — routes, parameter
  binding, request bodies, return types, status codes
- [Middleware](guides/middleware.md) — the `Middleware` interface, global
  and per-route chains, ordering, short-circuiting
- [Configuration](guides/configuration.md) — `application.yaml`,
  environment overrides, `@Value`, `@ConfigurationProperties`
- [Validation](guides/validation.md) — constraint annotations, cascading,
  the error response format
- [Error handling](guides/error-handling.md) — the `HttpException`
  hierarchy, `@ControllerAdvice`, the exception pipeline
- [WebSockets](guides/websockets.md) — `@WebSocketController`, the
  handler lifecycle, sessions, broadcast patterns, handshake interceptors
- [Application lifecycle](guides/lifecycle.md) — `@PostConstruct`/
  `@PreDestroy`, graceful shutdown, `DianaApp`, test overrides
- [Application events](guides/events.md) — `@EventListener`, the
  injectable `DianaEventPublisher`, cross-isolate `broadcast`
- [CORS and static files](guides/cors-and-static.md) — `@CrossOrigin`,
  preflight, static serving and SPA fallback
- [Content negotiation](guides/content-negotiation.md) — `BodyCodec`,
  `@Consumes`/`@Produces`, the built-in XML codec
- [Server-Sent Events](guides/server-sent-events.md) — `Stream` returns,
  heartbeats, disconnect handling
- [gRPC](guides/grpc.md) — `@GrpcService`, `package:diana_grpc`, serving
  gRPC next to HTTP
- [Authentication & authorization](guides/auth.md) — `diana_auth`,
  pluggable strategies (JWT/Basic/API key), `@Secured`/`@RolesAllowed`,
  `@Principal`
- [Persistence](guides/persistence.md) — `diana_data`, injectable
  `Database` over knex_dart, `@Transactional`, migrations
- **[Aspects](guides/aspects.md)** — `@Timed`, `@Cacheable`, `@Retryable`,
  `@CircuitBreaker` on service methods, composed at compile time
- [Observability](guides/observability.md) — `diana_observability`
  (Prometheus metrics, OpenTelemetry tracing, liveness/readiness),
  `/actuator/health`/`/info`, `@Scheduled` tasks
- [OpenAPI](guides/openapi.md) — the build-time generated spec and
  `/openapi.json`
- [Operations](guides/operations.md) — HTTPS, multi-isolate serving,
  configuration profiles
- [JSON serialization](guides/json.md) — the `fromJson`/`toJson`
  convention, json_serializable interop
- [Testing](guides/testing.md) — unit tests, wiring tests, end-to-end HTTP
  tests

## Reference

Complete API documentation — every public symbol and every diagnostic:

- [Annotations](reference/annotations.md) — all annotations with fields,
  defaults, targets and examples
- [Runtime API](reference/runtime.md) — every public class and function in
  `package:diana` (and `package:diana_grpc`)
- [Generated code](reference/generated-code.md) — what the generator emits,
  naming conventions, `part` directives
- [Build diagnostics](reference/build-diagnostics.md) — every build error
  Diana can report and how to fix it
- [Configuration keys](reference/config-keys.md) — every `server.*`,
  `management.*`, `grpc.*` and profile key Diana reads

## Requirements

- Dart SDK **3.6 or later**
- `build_runner` (code generation)

## Versioning and stability

Diana is currently `0.11.0`. APIs may change before `1.0.0`. The
[roadmap](../README.md#status--roadmap) lists what's planned.
