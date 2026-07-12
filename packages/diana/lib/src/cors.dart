/// CORS policy evaluation and preflight handling.
///
/// Wiring lives in `DianaServer` (global policy from config, per-route
/// policies from `@CrossOrigin`, automatic OPTIONS preflight routes); the
/// semantics live here, unit-tested once.
library;

import 'config.dart';
import 'http/method.dart';
import 'http/response.dart';
import 'middleware.dart';

class CorsPolicy {
  /// Allowed origins; `['*']` allows any.
  final List<String> allowedOrigins;

  /// Allowed methods for preflight; `null` means "the methods actually
  /// registered on the path".
  final List<String>? allowedMethods;

  /// Allowed request headers; `['*']` echoes whatever the preflight asks.
  final List<String> allowedHeaders;

  /// Response headers exposed to browser scripts.
  final List<String> exposedHeaders;

  final bool allowCredentials;
  final int maxAgeSeconds;

  const CorsPolicy({
    this.allowedOrigins = const ['*'],
    this.allowedMethods,
    this.allowedHeaders = const ['*'],
    this.exposedHeaders = const [],
    this.allowCredentials = false,
    this.maxAgeSeconds = 3600,
  });

  /// Global policy from `server.cors.*`; `null` when `server.cors.enabled`
  /// is false or unset.
  static CorsPolicy? fromConfig(DianaConfig config) {
    if (!config.get<bool>('server.cors.enabled', defaultValue: false)) {
      return null;
    }
    return CorsPolicy(
      allowedOrigins: config.get<List<String>>('server.cors.allowedOrigins',
          defaultValue: const ['*']),
      allowedMethods: config.get<List<String>?>('server.cors.allowedMethods'),
      allowedHeaders: config.get<List<String>>('server.cors.allowedHeaders',
          defaultValue: const ['*']),
      exposedHeaders: config.get<List<String>>('server.cors.exposedHeaders',
          defaultValue: const []),
      allowCredentials:
          config.get<bool>('server.cors.allowCredentials', defaultValue: false),
      maxAgeSeconds: config.get<int>('server.cors.maxAge', defaultValue: 3600),
    );
  }

  /// The `Access-Control-Allow-Origin` value for [origin], or `null` when
  /// the origin is not allowed (⇒ no CORS headers at all).
  String? allowOriginFor(String? origin) {
    if (origin == null) return null;
    if (allowedOrigins.contains('*')) {
      // With credentials, `*` is invalid — echo the origin instead.
      return allowCredentials ? origin : '*';
    }
    return allowedOrigins.contains(origin) ? origin : null;
  }
}

/// Wraps [inner] to add CORS headers to actual (non-preflight) responses.
DianaHandler withCors(CorsPolicy policy, DianaHandler inner) {
  return (request) async {
    final response = await inner(request);
    final allow = policy.allowOriginFor(request.header('origin'));
    if (allow == null) return response;
    return response.copyWith(headers: {
      ...response.headers,
      'access-control-allow-origin': allow,
      'vary': 'Origin',
      if (policy.allowCredentials) 'access-control-allow-credentials': 'true',
      if (policy.exposedHeaders.isNotEmpty)
        'access-control-expose-headers': policy.exposedHeaders.join(', '),
    });
  };
}

/// Builds the OPTIONS preflight handler for one path, given the CORS-enabled
/// methods registered on it.
DianaHandler corsPreflightHandler(Map<HttpMethod, CorsPolicy> policies) {
  return (request) {
    final requestedRaw = request.header('access-control-request-method');
    HttpMethod? requested;
    if (requestedRaw != null) {
      try {
        requested = HttpMethod.parse(requestedRaw);
      } on ArgumentError {
        requested = null;
      }
    }
    final policy = requested == null ? null : policies[requested];
    final allow = policy?.allowOriginFor(request.header('origin'));
    if (policy == null || allow == null) {
      // Not a valid CORS preflight for this path: 204 without CORS headers
      // (the browser will reject the cross-origin call).
      return const DianaResponse.noContent();
    }
    final methods = policy.allowedMethods ??
        [for (final m in policies.keys) m.name.toUpperCase()];
    final requestedHeaders = request.header('access-control-request-headers');
    final allowHeaders = policy.allowedHeaders.contains('*')
        ? (policy.allowCredentials ? requestedHeaders : '*')
        : policy.allowedHeaders.join(', ');
    return DianaResponse.noContent(headers: {
      'access-control-allow-origin': allow,
      'vary': 'Origin',
      'access-control-allow-methods': methods.join(', '),
      if (allowHeaders != null && allowHeaders.isNotEmpty)
        'access-control-allow-headers': allowHeaders,
      'access-control-max-age': '${policy.maxAgeSeconds}',
      if (policy.allowCredentials) 'access-control-allow-credentials': 'true',
    });
  };
}
