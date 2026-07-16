# Observability: health, info, scheduled tasks

## Actuator endpoints

Enable with:

```yaml
management:
  enabled: true    # default false; runtime flag, no rebuild needed
```

### GET /actuator/health

Aggregates every injectable implementing `HealthIndicator`:

```dart
@Component()
class DbHealthIndicator implements HealthIndicator {
  DbHealthIndicator(this.db);       // normal DI
  final Db db;

  @override
  String get name => 'database';

  @override
  Future<HealthStatus> health() async =>
      await db.ping() ? const HealthStatus.up()
                      : const HealthStatus.down({'reason': 'no ping'});
}
```

```json
200 {"status":"UP","components":{"database":{"status":"UP"}}}
503 {"status":"DOWN","components":{...}}          // any indicator down
```

Indicator exceptions count as down (with the error in `details`).
Indicators are discovered through the DI graph and must be **singletons**
(build error otherwise). Zero indicators ⇒ plain `UP` — wire the endpoint
to readiness probes either way.

### GET /actuator/info

Serves the `info.*` configuration section, re-nested:

```yaml
info:
  app:
    description: todo example
  team: diana
```

```json
{"app": {"description": "todo example"}, "team": "diana"}
```

Like all config, overridable via env (`INFO_TEAM=...`).

## Scheduled tasks

`@Scheduled` runs a method on a fixed schedule, integrated with the
[application lifecycle](lifecycle.md): tasks start after `initialize()`
(so `@PostConstruct` has run) and stop during `dispose()` (awaiting the
in-flight run).

```dart
@Component()
class CleanupJob {
  @Scheduled(fixedRate: 60000)          // every 60s, tick-based
  Future<void> sweep() async { ... }

  @Scheduled(fixedDelay: 5000, initialDelay: 1000)
  void heartbeat() { ... }              // 5s after each completed run
}
```

Semantics:

- Exactly **one** of `fixedRate`/`fixedDelay` (milliseconds; build error
  otherwise). `initialDelay` delays the first run.
- `fixedRate` **skips a tick** while the previous run is still in flight —
  no unbounded queueing. `fixedDelay` re-arms after completion.
- Method rules: public instance method, no parameters, `void`/`Future<void>`,
  singleton provider (all build-verified).
- Task errors are reported (stderr by default) and never stop the schedule.
- No cron expressions yet.

With multi-isolate serving, tasks run **once per process** (only the main isolate starts them); pass `perIsolate: true` for tasks that must run in every isolate.
