/// Observability for the Diana backend framework.
///
/// Provides in-package Prometheus metrics (`/actuator/metrics`), optional
/// OpenTelemetry tracing, and an injectable [MeterRegistry] for application
/// metrics. Subclass [DianaObservability], register it as a `@Component`,
/// and the generator wires automatic HTTP/DB/scheduler/event instrumentation
/// plus the metrics endpoint.
///
/// This is the only package in the Diana workspace that depends on
/// `package:opentelemetry` (enforced by a boundary test).
library;

export 'src/metrics/metrics.dart'
    show Counter, Gauge, Histogram, MeterRegistry;
export 'src/observability.dart'
    show DianaObservability, metricsEndpointHandler;
export 'src/tracing/tracer.dart' show TracingOptions;
