# Application events

Diana's analog of Spring's `ApplicationEventPublisher`: publish plain Dart
objects as events, and any singleton provider can react to them by
annotating a method with `@EventListener`. Listener wiring is resolved at
compile time — the generated context registers every listener before your
application initializes.

## Declaring a listener

Any singleton provider (service, component, controller, middleware, …)
can listen. The method takes exactly one parameter — the event type — and
returns `void` or `Future<void>`:

```dart
class TodoCreated {
  final int id;
  final String title;
  const TodoCreated(this.id, this.title);
}

@Component()
class TodoAuditListener {
  @EventListener()
  void onTodoCreated(TodoCreated event) => log(event.title);
}
```

Matching is by type, **subtypes included** (Spring semantics): a listener
on `OrderEvent` also receives `OrderCreated extends OrderEvent`.
Request-scoped and transient providers cannot listen (build error) — a
listener must have a stable instance for the application's lifetime.

## Publishing

Inject `DianaEventPublisher` (the interface, not the bus) into any
provider:

```dart
@Service()
class TodoService {
  final DianaEventPublisher publisher;
  TodoService(this.publisher);

  Future<TodoDto> create(CreateTodoRequest request) async {
    final todo = repo.save(request.title);
    await publisher.publish(TodoCreated(todo.id, todo.title));
    return todo;
  }
}
```

`publish` is **synchronous in the Spring sense**: it runs every matching
listener — in registration order, awaiting each one — before it returns,
so events participate in the request flow. A listener throwing propagates
to the publisher and skips the remaining listeners; an uncaught error
therefore surfaces exactly like any other exception in the calling route
(exception pipeline, `@ControllerAdvice`, …).

Registration order is deterministic: providers in dependency
(topological) order, methods in declaration order within a class.

## `publish` vs `broadcast`

| | Local listeners | Other isolates |
|---|---|---|
| `publish(event)` | awaited, errors propagate | not delivered |
| `broadcast(event)` | awaited, errors propagate | delivered fire-and-forget |

With a single isolate (the default), `broadcast` behaves exactly like
`publish`. With `server.isolates > 1`, `broadcast` also relays the event
to every other isolate over the runtime's control plane; each isolate's
listeners then run against their own providers. This is the built-in
answer to multi-isolate coordination — see
[operations](operations.md#multi-isolate-serving-experimental).

Cross-isolate rules:

- **Events must be plain data.** The event object crosses the isolate
  boundary as-is; anything holding a `ReceivePort`, socket or other
  native resource fails fast with
  `ArgumentError: Diana broadcast failed: event of type X is not sendable
  across isolates. …` — before any local listener runs.
- **Remote delivery is fire-and-forget**: the publisher never observes
  remote listener errors (they go to the bus's `onError`, which logs by
  default), and there is no cross-isolate ordering guarantee.
- Delivery is exactly-once per isolate (hub-and-spoke relay through the
  main isolate; no loops).
- During a worker's own `initialize()` the bridge is not wired yet, so a
  `broadcast` from startup code delivers locally only.

## Lifecycle timing

Listeners are registered in the generated `DianaContext` **constructor**,
before `initialize()` runs — so publishing from a `@PostConstruct` hook is
fully supported and delivered. Publishing from a provider **constructor**
is discouraged: providers are `late final`, and an event fired mid-graph
construction can force a circular initialization
(`LateInitializationError`). Move that publish to `@PostConstruct`.

Registration itself is lazy: a listener provider is only constructed when
the first matching event fires (or when `initialize()` builds it, whichever
comes first).

## Testing

The bus is plain Dart — no server needed:

```dart
final ctx = buildDianaContext(config: DianaConfig({...}));
await ctx.eventBus.publish(const TodoCreated(1, 'unit test'));
expect(ctx.todoAuditListener.seen, ['unit test']);
```

Or construct a `DianaEventBus` directly in unit tests and register
handlers with `bus.on<MyEvent>(...)`. For publisher-side tests, inject a
fake `DianaEventPublisher` through `DianaOverrides` as usual.

## See also

- [Application lifecycle](lifecycle.md) — `@PostConstruct`, initialization order
- [Operations](operations.md#multi-isolate-serving-experimental) — multi-isolate serving
- [Runtime API](../reference/runtime.md) — `DianaEventPublisher`, `DianaEventBus`
- [Build diagnostics](../reference/build-diagnostics.md) — the exact errors
