/// Actuator-style health and info endpoints.
///
/// When `management.enabled` is true, the generated server registers
/// `GET /actuator/health` (aggregating every injectable implementing
/// [HealthIndicator]) and `GET /actuator/info` (serving the `info.*`
/// configuration section).
library;

import 'dart:async';

import 'config.dart';
import 'http/response.dart';
import 'middleware.dart';

/// Contributes a component to `/actuator/health`. Implementations are
/// discovered through the DI graph and must be singletons.
abstract interface class HealthIndicator {
  /// Component name in the aggregated response.
  String get name;

  Future<HealthStatus> health();
}

class HealthStatus {
  final bool up;
  final Map<String, Object?> details;

  const HealthStatus.up([this.details = const {}]) : up = true;
  const HealthStatus.down([this.details = const {}]) : up = false;

  String get status => up ? 'UP' : 'DOWN';
}

/// Aggregating `/actuator/health` handler: overall `DOWN` (HTTP 503) when
/// any indicator is down; indicator exceptions count as down.
DianaHandler healthEndpointHandler(List<HealthIndicator> indicators) {
  return (request) async {
    var allUp = true;
    final components = <String, Object?>{};
    for (final indicator in indicators) {
      HealthStatus status;
      try {
        status = await indicator.health();
      } catch (e) {
        status = HealthStatus.down({'error': '$e'});
      }
      if (!status.up) allUp = false;
      components[indicator.name] = {
        'status': status.status,
        if (status.details.isNotEmpty) 'details': status.details,
      };
    }
    return DianaResponse.json(
      {
        'status': allUp ? 'UP' : 'DOWN',
        if (components.isNotEmpty) 'components': components,
      },
      statusCode: allUp ? 200 : 503,
    );
  };
}

/// `/actuator/health/liveness` handler: a trivial `200 UP` — the process
/// is running and serving. Kubernetes restarts the pod when this fails, so
/// it deliberately does not consult dependencies.
DianaHandler livenessEndpointHandler() {
  return (request) => DianaResponse.json({'status': 'UP'});
}

/// `/actuator/health/readiness` handler: aggregates [indicators] like
/// `/actuator/health` (503 when any is down). Kubernetes stops routing
/// traffic to the pod when this fails, without restarting it.
DianaHandler readinessEndpointHandler(List<HealthIndicator> indicators) =>
    healthEndpointHandler(indicators);

/// `/actuator/info` handler: serves the `info.*` configuration section,
/// re-nested (`info.build.rev` → `{"build": {"rev": ...}}`).
DianaHandler infoEndpointHandler(DianaConfig config) {
  return (request) {
    final nested = <String, Object?>{};
    for (final entry in config.section('info').entries) {
      var node = nested;
      final segments = entry.key.split('.');
      for (final segment in segments.take(segments.length - 1)) {
        node = (node[segment] ??= <String, Object?>{}) as Map<String, Object?>;
      }
      node[segments.last] = entry.value;
    }
    return DianaResponse.json(nested);
  };
}
