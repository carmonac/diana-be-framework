# diana_annotation

Annotations for the [Diana framework](../../README.md): DI
(`@Service`, `@Repository`, `@Component`, `@Injectable`, `@Named`), web
(`@RestController`, `@Get`…`@Patch`, `@PathParam`, `@QueryParam`, `@Header`,
`@Body`, `@ResponseStatus`), middleware (`@GlobalMiddleware`,
`@UseMiddleware`), configuration (`@Value`, `@ConfigurationProperties`),
exception handling (`@ControllerAdvice`, `@ExceptionHandler`), validation
(`@NotNull`, `@NotBlank`, `@Min`, `@Max`, `@Size`, `@Pattern`, `@Email`,
`@Valid`, …) and the `@DianaApplication` entrypoint.

Pure `const` classes with no runtime behaviour and no dependencies (besides
`meta`). Consumed by both the runtime (`diana`, which re-exports it) and the
code generator (`diana_generator`).
