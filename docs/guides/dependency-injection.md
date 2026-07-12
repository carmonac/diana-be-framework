# Dependency injection

Diana's DI is resolved **entirely at build time**. The generator reads your
annotated classes, resolves the full dependency graph, and emits a
`DianaContext` class whose typed fields *are* the container. Missing
providers, ambiguous bindings, dependency cycles and scope violations are
build errors with precise locations — they cannot reach production.

## Declaring providers

Annotate a class with any of the injectable annotations:

```dart
@Service()            // business logic
class TodoService { ... }

@Repository()         // data access
class InMemoryTodoRepository implements TodoRepository { ... }

@Component()          // anything else
class Clock { ... }

@Injectable(scope: Scope.transient)   // the general form
class UuidFactory { ... }
```

`@Service`, `@Repository` and `@Component` are semantic aliases of
`@Injectable` — they accept the same parameters (`scope`, `as`, `name`) and
behave identically. Pick whichever communicates intent.

Controllers (`@RestController`), middleware (`@GlobalMiddleware`), advices
(`@ControllerAdvice`) and configuration classes
(`@ConfigurationProperties`) are **also providers** and join the same
graph.

### Requirements for provider classes

- Public (not `_Private`) — generated wiring references them across
  libraries.
- Concrete (not `abstract`).
- No type parameters (`class Repo<T>` is rejected; provide a concrete
  subclass).
- A public **unnamed generative constructor** — Diana instantiates through
  it. Every constructor parameter (positional or named) is resolved from
  the graph, except `@Value` parameters, which come from
  [configuration](configuration.md).
- One role annotation per class (`@Service` + `@RestController` on the same
  class is a build error).

## How dependencies resolve

For each constructor parameter, Diana looks up a provider **by exact type**
(generic type arguments included — `CrudRepository<Todo>` only matches a
provider bound to `CrudRepository<Todo>`). Matching happens in two tiers:

1. **Strong bindings** — the provider's own class, plus the type named by
   `as:` if given.
2. **Auto-binding candidates** — every supertype the provider implements or
   extends (transitively, excluding `dart:*` types).

Strong bindings win over candidates. Within a tier:

- exactly one match → resolved;
- more than one match → build error listing every candidate and where each
  is declared;
- none → *missing provider* build error naming the parameter and class that
  needed it.

### Interface auto-binding

If exactly one provider implements an interface, depending on the interface
just works:

```dart
abstract interface class TodoRepository { ... }

@Repository()
class InMemoryTodoRepository implements TodoRepository { ... }

@Service()
class TodoService {
  TodoService(this.repo);        // gets InMemoryTodoRepository
  final TodoRepository repo;
}
```

### Choosing among several implementations

When two classes implement the same interface, disambiguate with either:

**`as:`** — declare one of them *the* binding for that type:

```dart
@Repository(as: TodoRepository)
class PostgresTodoRepository implements TodoRepository { ... }

@Repository()                    // still injectable by its own type
class InMemoryTodoRepository implements TodoRepository { ... }
```

The `as:` type must actually be implemented/extended by the class, and two
providers must not claim the same type with `as:`.

**Qualifiers** — name the providers and select by name at the injection
point:

```dart
@Component(name: 'smtp')
class SmtpSender implements MailSender { ... }

@Component(name: 'log')
class LogSender implements MailSender { ... }

@Service()
class Notifier {
  Notifier(@Named('smtp') this.sender);
  final MailSender sender;
}
```

A qualified provider is **only** visible through `@Named` — it does not
participate in unqualified resolution.

## Scopes

```dart
enum Scope { singleton, request, transient }
```

| Scope | Lifetime | Generated as |
|---|---|---|
| `singleton` *(default)* | one instance for the application | `late final` field on `DianaContext` |
| `request` | one instance per HTTP request | `late final` field on `DianaRequestScope` |
| `transient` | new instance per injection point | factory method (`createX()`) |

Rules, enforced at build time:

- Nothing reachable from a singleton may be request-scoped (a singleton
  outlives every request). A controller that depends on request-scoped
  providers must itself be request-scoped:
  `@RestController('/x', Scope.request)`.
- A transient that (transitively) depends on a request-scoped provider is
  itself treated as request-bound.
- Middleware must be singletons.

Note that a **transient** is created once per *injection point*: a
singleton that receives a transient keeps that one instance. Transients
shine when injected into request-scoped providers or when you call the
generated factory yourself.

## Injecting configuration values

`@Value` parameters are resolved from [configuration](configuration.md),
not from the graph:

```dart
@Service()
class Greeter {
  Greeter(@Value('app.greeting', defaultValue: 'hello') this.greeting);
  final String greeting;
}
```

## What gets generated

For this graph:

```dart
@Repository()
class InMemoryTodoRepository implements TodoRepository {}

@Service()
class TodoService {
  TodoService(this.repo);
  final TodoRepository repo;
}
```

the generator emits (simplified — real output uses import prefixes):

```dart
class DianaContext {
  DianaContext(this.config);
  final DianaConfig config;

  late final InMemoryTodoRepository inMemoryTodoRepository =
      InMemoryTodoRepository();

  late final TodoService todoService = TodoService(inMemoryTodoRepository);
}
```

Fields appear in topological (dependency) order; `late final` makes
construction lazy while the build-time cycle check guarantees safety.
Deterministic output: rebuilding unchanged sources is byte-identical.

You can construct the graph yourself in tests with the generated
`buildDianaContext({DianaConfig? config})` — see [Testing](testing.md).

## Errors you might see

Every failure mode has a dedicated diagnostic — duplicates, ambiguity,
missing providers, cycles (with the full path printed), scope violations.
They are all collected and reported together in a single build failure. See
the [build diagnostics reference](../reference/build-diagnostics.md).

## Current limitations

- Providers must be non-generic classes (generic *dependencies* like
  `CrudRepository<Todo>` are fine — matched structurally).
- All providers must live in the same package as the `@DianaApplication`
  (cross-package component scanning is on the roadmap).
- Named constructors and factory constructors are not used for injection.
