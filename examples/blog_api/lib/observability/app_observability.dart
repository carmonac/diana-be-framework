import 'package:diana/diana.dart';
import 'package:diana_observability/diana_observability.dart';

/// Enables Prometheus metrics at `/actuator/metrics` and (when
/// `observability.tracing.endpoint` is configured) OpenTelemetry tracing.
///
/// The generator discovers this provider and wires automatic HTTP, database,
/// scheduler and event instrumentation into the app. Services can inject it
/// to record their own metrics via `meters`.
@Component()
class AppObservability extends DianaObservability {
  AppObservability(
      @Value('observability.tracing.endpoint', defaultValue: '') String endpoint)
      : super(
          tracing: endpoint.isEmpty
              ? null
              : TracingOptions(endpoint: endpoint, serviceName: 'blog_api'),
        );

  @PreDestroy()
  void shutdown() => close();
}
