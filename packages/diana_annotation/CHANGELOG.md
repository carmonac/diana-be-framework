# Changelog

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
