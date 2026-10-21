# diana_observability

Observability for the [Diana framework](https://github.com/carmonac/diana-be-framework):
in-package Prometheus metrics, OpenTelemetry tracing and Kubernetes-style
liveness/readiness probes. Register one `DianaObservability` subclass and
the generator wires instrumentation into the server, scheduler, event bus
and database — no per-route code.

```yaml
dependencies:
  diana: ^0.15.0
  diana_observability: ^0.15.0
```

Read the [observability guide](https://carmonac.github.io/diana-be-framework/guides/observability/).
