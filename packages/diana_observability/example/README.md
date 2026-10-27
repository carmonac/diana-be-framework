# diana_observability example

```yaml
dependencies:
  diana: ^0.15.0
  diana_observability: ^0.15.0
```

Register one `DianaObservability` subclass. The generator discovers it and
instruments the server, scheduler, event bus and database automatically;
Prometheus metrics are served at `GET /actuator/metrics`:

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
  void shutdown() => close(); // flush the tracer on graceful shutdown
}
```

Application metrics use the same registry:

```dart
@Service()
class OrderService {
  OrderService(this._obs);
  final AppObservability _obs;
  late final _placed = _obs.meters.counter('orders_placed_total', 'Orders.');

  void place() => _placed.inc();
}
```

See the [observability guide](https://carmonac.github.io/diana-be-framework/guides/observability/).
