# Changelog

## 0.13.0

- New annotation: `@Table(name)` — maps a `@Json` entity to a database
  table for query repositories.

## 0.12.0

- `@Scheduled` gains a `cron` parameter (6-field expression or a macro).

## 0.11.0

- Version bump only (kept in lockstep with the workspace).

## 0.10.0

- New method-level aspect annotations: `@Timed`, `@Cacheable`,
  `@Retryable`, `@CircuitBreaker`.

## 0.9.0

- Version bump only (kept in lockstep with the workspace).

## 0.8.1

- Version bump only (kept in lockstep with the workspace).

## 0.8.0

- Version bump only (kept in lockstep with the workspace).

## 0.7.0

- `@Scheduled` gains `perIsolate` (default `false`) — opt a task into
  running in every isolate under multi-isolate serving.

## 0.6.0

- New annotation: `@Transactional` (method/class) for the `diana_data`
  package.

## 0.5.0

- New annotations: `@Secured`, `@RolesAllowed` (controllers/routes/gRPC
  services) and `@Principal` (route parameters) for the `diana_auth`
  package.

## 0.4.0

- New annotation: `@EventListener` (method-level) — registers an
  application-event listener on a singleton provider.

## 0.3.0

- New annotations: `@Consumes`/`@Produces` (content negotiation, method
  overrides controller) and `@GrpcService` (registers a protoc-generated
  service with `DianaGrpcServer` from `package:diana_grpc`).

## 0.2.0

- New annotations: `@PostConstruct`, `@PreDestroy`, `@CrossOrigin`,
  `@Scheduled`, `@Json`, `@JsonField`.

## 0.1.0

- Initial release: DI (`@Service`, `@Repository`, `@Component`,
  `@Configuration`, `@Bean`, `@Named`, `@Value`, scopes), web
  (`@RestController`, HTTP methods, parameter binding, `@Body`,
  `@ResponseStatus`), middleware, validation constraints, configuration
  (`@ConfigurationProperties`), `@ControllerAdvice`/`@ExceptionHandler`,
  WebSockets (`@WebSocketController` and events).
