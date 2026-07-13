import 'package:diana/diana.dart';

import 'database.dart';

/// A [HealthIndicator] that reports database connectivity by running a
/// trivial query. Register it as a provider (`@Component`) and it is picked
/// up by Diana's `/actuator/health` endpoint like any other indicator.
///
/// ```dart
/// @Component()
/// class DbHealth extends DatabaseHealthIndicator {
///   DbHealth(super.db);
/// }
/// ```
class DatabaseHealthIndicator implements HealthIndicator {
  final Database _db;

  DatabaseHealthIndicator(this._db);

  @override
  String get name => 'database';

  @override
  Future<HealthStatus> health() async {
    try {
      await _db.raw('SELECT 1');
      return const HealthStatus.up();
    } catch (e) {
      return HealthStatus.down({'error': '$e'});
    }
  }
}
