# Observability: metrics, tracing, health, scheduled tasks

Diana ships production observability in the optional
[`diana_observability`](../../packages/diana_observability) package:
in-package Prometheus metrics, OpenTelemetry tracing and Kubernetes-style
liveness/readiness probes. Health, info and `@Scheduled` are built into the
core and need no package.

## Metrics and tracing (`diana_observability`)

Add the package and register **one** `DianaObservability` subclass — the
generator discovers it and wires automatic instrumentation into the server,
scheduler, event bus and database (no per-route code):

```yaml
# pubspec.yaml
dependencies:
  diana: ^0.12.0
  diana_observability: ^0.12.0
```

```dart
import 'package:diana/diana.dart';
import 'package:diana_observability/diana_observability.dart';

@Component()
class AppObservability extends DianaObservability {
  AppObservability(
      @Value('observability.tracing.endpoint', defaultValue: '') String endpoint)
      : super(
          tracing: endpoint.isEmpty
              ? null
              : TracingOptions(endpoint: endpoint, serviceName: 'my-api'));

  @PreDestroy()
  void shutdown() => close();   // flush the tracer on graceful shutdown
}
```

### GET /actuator/metrics

Served (when `management.enabled`) in the Prometheus 0.0.4 text format.
Automatic series, all labelled by **route template** rather than concrete
path so cardinality stays bounded:

| Metric | Labels | Meaning |
|---|---|---|
| `diana_http_requests_total` | `method,route,status` | HTTP request count |
| `diana_http_request_duration_seconds` | `method,route` | latency histogram |
| `diana_http_unmatched_total` | — | 404s (no path label) |
| `diana_db_queries_total` | `operation` | DB operations (`diana_data`) |
| `diana_db_query_duration_seconds` | `operation` | DB latency histogram |
| `diana_scheduled_runs_total` | `task,result` | `@Scheduled` runs |
| `diana_events_dispatched_total` | `type` | event dispatches |
| `diana_process_resident_memory_bytes` | — | RSS gauge |

The metrics see the **final** status — including 4xx/5xx produced by the
error boundary — because instrumentation wraps the whole route pipeline.

**Application metrics.** Inject the provider (or any core-neutral surface it
exposes) and use its registry:

```dart
@Service()
class OrderService {
  OrderService(this._obs);
  final AppObservability _obs;
  late final _placed = _obs.meters.counter('orders_placed_total', 'Orders.');

  void place() => _placed.inc();
}
```

#`@Timed` service methods (see [aspects](aspects.md)) add
`diana_method_duration_seconds{method}` and
`diana_method_calls_total{method,result}` automatically.

## Tracing

When `observability.tracing.endpoint` is set, every request opens a
server span (continuing an inbound W3C `traceparent`) and each database
operation a child span, exported to an OTLP collector. Leave the endpoint
empty to disable tracing (metrics still work). Tracing is Beta upstream
(`package:opentelemetry`); spans and OTLP export are functional, richer
semantic conventions are evolving.

| Key | Meaning |
|---|---|
| `observability.tracing.endpoint` | OTLP collector URL (empty ⇒ tracing off) |
| `observability.tracing.serviceName` | `service.name` resource attribute |

## Liveness and readiness (core)

`management.enabled` also exposes two Kubernetes-style probes, split from
`/actuator/health`:

- **`GET /actuator/health/liveness`** — a trivial `200 UP`: the process is
  running. Wire it to the k8s *livenessProbe* (a failure restarts the pod);
  it deliberately does not consult dependencies.
- **`GET /actuator/health/readiness`** — aggregates the same
  `HealthIndicator`s as `/actuator/health` (503 when any is down). Wire it
  to the *readinessProbe* (a failure stops traffic without a restart).

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
