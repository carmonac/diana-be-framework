import 'package:diana/diana.dart';
import 'package:diana_data/diana_data.dart';

/// Wires diana_data's database health check into `/actuator/health` — it is
/// discovered like any other `HealthIndicator` provider.
@Component()
class DbHealth extends DatabaseHealthIndicator {
  DbHealth(super.db);
}
