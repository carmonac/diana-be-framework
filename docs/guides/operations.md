# Operations: HTTPS, isolates, profiles

## HTTPS

Configure certificate and key paths; the server switches to TLS:

```yaml
server:
  ssl:
    certPath: certs/fullchain.pem
    keyPath: certs/privkey.pem
    # keyPassword: optional
```

Both paths are required together (startup error otherwise). The startup log
switches to `https://`. Terminating TLS at a reverse proxy and serving
plain HTTP behind it is equally supported — just omit `server.ssl.*`.

## Multi-isolate serving (experimental)

```yaml
server:
  isolates: 4
```

`runDiana()` (through `DianaRuntime.run`) spawns `n - 1` worker isolates.
**Each worker runs the full bootstrap** — its own `DianaContext`, its own
`initialize()` — and binds the same port with shared sockets; the OS
distributes connections. The main isolate owns the signal handlers and
coordinates worker shutdown (workers close and dispose before the main
isolate does). Worker failure is contained: a worker whose dispose throws
is reported on stderr (shutdown still completes), a worker that hangs is
killed after `DianaRuntime.workerShutdownTimeout` (default 15s), and a
worker isolate that dies from an uncaught error is logged and skipped by
the event relay and by shutdown.

Startup is coordinated and fail-closed: workers bootstrap and run
`initialize()` when spawned, but no isolate accepts connections until every
worker exists and the main isolate has initialized — early traffic can
neither reach an isolate whose `@PostConstruct` hasn't run nor trigger a
broadcast that misses a not-yet-spawned sibling. If any isolate fails to
start (or the main `initialize()` throws), the already-spawned workers are
shut down before the error propagates — a failed startup never leaves
orphan isolates serving.

Constraints:

- Everything captured by the bootstrap must be sendable across isolates.
  The generated bootstrap captures only `DianaConfig` (immutable primitives)
  and the `overrides` value — `const DianaOverrides()` is fine, live mock
  instances generally are not.
- State is **per isolate**: in-memory repositories and caches are
  independent copies. Share state through external systems.
- `@Scheduled` tasks run **once per process**: only the main isolate
  starts them, so schedules never multiply with `server.isolates`. A task
  that genuinely needs to run in every isolate (e.g. refreshing an
  isolate-local cache) opts in with `@Scheduled(perIsolate: true)`. See
  [Observability](observability.md#scheduled-tasks).
- **Application events** bridge isolates: `publisher.broadcast(event)`
  delivers the event to every isolate exactly once (main relays worker
  broadcasts to the siblings). See
  [Application events](events.md#publish-vs-broadcast).
- Multi-**process** coordination (several replicas behind a load balancer)
  is out of scope today — schedules still run once per replica; a
  distributed-lock option (ShedLock-style, via `diana_data`) is on the
  roadmap.
- Labeled experimental; `server.isolates: 1` (the default) uses none of the
  isolate machinery.

## Profiles

Spring-style configuration profiles:

```
application.yaml            # base
application-dev.yaml        # overlay when 'dev' is active
application-prod.yaml       # overlay when 'prod' is active
```

Activate via the `DIANA_PROFILE` environment variable (comma-separated,
later profiles win) or the `diana.profile` key in the base file —
`DIANA_PROFILE` **replaces** the key entirely when set:

```bash
DIANA_PROFILE=prod,eu dart run bin/server.dart
```

Precedence (lowest → highest): base file → profile overlays in listed
order → environment variables. A profile without a file is skipped.
`config.activeProfiles` exposes the active list at runtime.

## Deployment checklist

- Configuration is env-overridable by design: `server.port` ← `SERVER_PORT`,
  etc. — see the [config keys reference](../reference/config-keys.md).
- Missing required keys (`@Value` without default, non-nullable
  `@ConfigurationProperties`) fail at **startup**.
- SIGTERM triggers graceful shutdown (drain → `@PreDestroy`) — Kubernetes
  default termination works out of the box.
- `/actuator/health` (when `management.enabled`) returns 503 while any
  `HealthIndicator` is down — wire it to readiness probes.
