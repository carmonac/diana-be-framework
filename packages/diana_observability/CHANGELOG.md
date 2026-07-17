# Changelog

## 0.11.0

- Version bump only (kept in lockstep with the workspace).

## 0.10.0

- Implements `observeTimedMethod`: `diana_method_duration_seconds{method}`,
  `diana_method_calls_total{method,result}` and a `method.<name>` child
  span per `@Timed` invocation.

## 0.9.0

- Version bump only (kept in lockstep with the workspace).

## 0.8.1

- Version bump only (kept in lockstep with the workspace).

## 0.8.0

- Initial release: observability for Diana.
- In-package Prometheus metrics (`Counter`/`Gauge`/`Histogram`/
  `MeterRegistry`, 0.0.4 text format) with automatic HTTP/database/
  scheduler/event series and process RSS.
- `DianaObservability` provider implementing `DianaObserver`; served at
  `/actuator/metrics`.
- Optional OpenTelemetry tracing (`TracingOptions`): server span per request
  (W3C `traceparent`), child spans per DB operation, OTLP/console export.
- The only Diana package depending on `package:opentelemetry`.
