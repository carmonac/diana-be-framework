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
isolate does).

Constraints:

- Everything captured by the bootstrap must be sendable across isolates.
  The generated bootstrap captures only `DianaConfig` (immutable primitives)
  and the `overrides` value — `const DianaOverrides()` is fine, live mock
  instances generally are not.
- State is **per isolate**: in-memory repositories, caches and `@Scheduled`
  tasks run once *per isolate*. Share state through external systems.
- The exception is **application events**: `publisher.broadcast(event)`
  delivers the event to every isolate exactly once (main relays worker
  broadcasts to the siblings), so isolates can react to each other —
  contrast with `@Scheduled`, which simply runs everywhere. See
  [Application events](events.md#publish-vs-broadcast).
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
