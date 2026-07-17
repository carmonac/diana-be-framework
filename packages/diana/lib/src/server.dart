import 'dart:async';

import 'adapter/relic_adapter.dart';
import 'codec.dart';
import 'config.dart';
import 'content.dart';
import 'cors.dart';
import 'http/method.dart';
import 'http/request.dart';
import 'http/response.dart';
import 'middleware.dart';
import 'observer.dart';
import 'pipeline.dart';
import 'websocket.dart';

/// Diana's HTTP server: routes registered by generated code, composed with
/// middleware and the exception boundary, served over the HTTP engine.
///
/// Applications don't construct this directly — the generated
/// `buildDianaServer()` does.
class DianaServer {
  final DianaConfig config;

  /// Applied to every route, already sorted by `@GlobalMiddleware(order:)`.
  final List<Middleware> globalMiddleware;

  /// Generated `@ControllerAdvice` chain, if any.
  final ExceptionMapper? exceptionMapper;

  /// Receives unhandled (non-[HttpException]) errors. Defaults to printing
  /// to stderr.
  final void Function(Object error, StackTrace stackTrace) onUnhandled;

  /// Additional body codecs (JSON is always available).
  final List<BodyCodec> bodyCodecs;

  /// Observes requests, unmatched paths, scheduled runs, etc. `null` in
  /// apps without an observability provider (zero overhead).
  final DianaObserver? observer;

  late final RelicAdapter _adapter = RelicAdapter(
    limits: DianaRequestLimits(
      maxBodyBytes: config.get<int>('server.maxBodyBytes',
          defaultValue: 10 * 1024 * 1024),
      multipartMaxBytes: config.get<int>('server.multipart.maxSize',
          defaultValue: 10 * 1024 * 1024),
      sseHeartbeatSeconds:
          config.get<int>('server.sse.heartbeatSeconds', defaultValue: 15),
    ),
    codecs: BodyCodecRegistry(bodyCodecs),
    onUnmatched: observer?.observeUnmatched,
  );

  /// Global CORS policy from `server.cors.*`, if enabled.
  late final CorsPolicy? _globalCors = CorsPolicy.fromConfig(config);

  /// CORS-enabled methods per path, for automatic preflight routes.
  final Map<String, Map<HttpMethod, CorsPolicy>> _corsByPath = {};

  /// Every (path, method) the user registered, to avoid clobbering a
  /// hand-written OPTIONS route with the automatic preflight.
  final Map<String, Set<HttpMethod>> _registered = {};

  DianaServer({
    this.config = const DianaConfig.empty(),
    this.globalMiddleware = const [],
    this.exceptionMapper,
    this.bodyCodecs = const [],
    this.observer,
    void Function(Object error, StackTrace stackTrace)? onUnhandled,
  }) : onUnhandled = onUnhandled ?? _defaultOnUnhandled;

  /// Registers a route. [middleware] is the controller-level plus
  /// route-level chain, in that order; global middleware wrap around it.
  ///
  /// [cors] (from `@CrossOrigin`) replaces the global `server.cors.*`
  /// policy for this route; either enables CORS headers and the automatic
  /// OPTIONS preflight on the path.
  void register(
    HttpMethod method,
    String path,
    DianaHandler handler, {
    List<Middleware> middleware = const [],
    CorsPolicy? cors,
  }) {
    var chain = composeMiddleware(
      [...globalMiddleware, ...middleware],
      handler,
    );
    chain = _withAcceptGuard(chain);
    final effectiveCors = cors ?? _globalCors;
    if (effectiveCors != null) {
      chain = withCors(effectiveCors, chain);
      (_corsByPath[path] ??= {})[method] = effectiveCors;
    }
    final guarded = withErrorBoundary(
      chain,
      mapper: exceptionMapper,
      onUnhandled: onUnhandled,
    );
    // Observed outside the error boundary: sees the final status (incl.
    // 4xx/5xx) and the route template, and never an exception.
    final observed = observer == null
        ? guarded
        : (DianaRequest req) => observer!.observeHttp(method, path, req, guarded);
    (_registered[path] ??= {}).add(method);
    _adapter.register(method, path, observed);
  }

  /// Sentinel returned by the innermost WS handshake handler: identity
  /// signals "proceed with the upgrade".
  static const DianaResponse _upgradeMarker = DianaResponse(statusCode: 101);

  /// Registers a WebSocket endpoint at [path]. [factory] produces the
  /// handler per connection: a constant closure over a singleton for shared
  /// handlers, or a call to a transient factory for per-connection state.
  ///
  /// [middleware] (from `@UseMiddleware` on the `@WebSocketController`) run
  /// as handshake interceptors: short-circuiting (e.g. a 401) blocks the
  /// upgrade, and `request.attributes` they set are copied into
  /// `WebSocketSession.attributes`. Global middleware do NOT apply to
  /// handshakes. After the upgrade, socket errors reach the handler's
  /// `onError`.
  void registerWebSocket(
    String path,
    WebSocketHandlerFactory factory, {
    List<Middleware> middleware = const [],
  }) {
    DianaHandler? handshake;
    if (middleware.isNotEmpty) {
      handshake = withErrorBoundary(
        composeMiddleware(middleware, (req) => _upgradeMarker),
        mapper: exceptionMapper,
        onUnhandled: onUnhandled,
      );
    }
    _adapter.registerWebSocket(
      path,
      factory,
      handshake: handshake,
      upgradeMarker: _upgradeMarker,
    );
  }

  /// Starts the server on `server.host`/`server.port` from [config]
  /// (defaults: `0.0.0.0:8080`). [port] overrides the configured port —
  /// pass 0 in tests to get an ephemeral one.
  ///
  /// HTTPS is enabled when `server.ssl.certPath` and `server.ssl.keyPath`
  /// are configured (`server.ssl.keyPassword` optional). [shared] allows
  /// multiple isolates to bind the same port.
  Future<void> serve({int? port, bool quiet = false, bool shared = false}) async {
    // Static file serving from `server.static.*`.
    if (config.get<bool>('server.static.enabled', defaultValue: false)) {
      _adapter.registerStatic(
        directory: config.get<String>('server.static.dir',
            defaultValue: 'public'),
        prefix: config.get<String>('server.static.prefix',
            defaultValue: '/static'),
        indexFile: config.get<String>('server.static.index',
            defaultValue: 'index.html'),
        spaFallback:
            config.get<bool>('server.static.spa', defaultValue: false),
        cacheMaxAgeSeconds:
            config.get<int>('server.static.cacheMaxAge', defaultValue: 3600),
      );
    }

    // Automatic CORS preflight routes for paths that need them and have no
    // user-registered OPTIONS handler.
    for (final entry in _corsByPath.entries) {
      final hasUserOptions =
          _registered[entry.key]?.contains(HttpMethod.options) ?? false;
      if (!hasUserOptions) {
        _adapter.register(
          HttpMethod.options,
          entry.key,
          corsPreflightHandler(entry.value),
        );
      }
    }

    final host = config.get<String>('server.host', defaultValue: '0.0.0.0');
    final certPath = config.get<String?>('server.ssl.certPath');
    await _adapter.serve(
      host: host,
      port: port ?? config.get<int>('server.port', defaultValue: 8080),
      sslCertPath: certPath,
      sslKeyPath: config.get<String?>('server.ssl.keyPath'),
      sslKeyPassword: config.get<String?>('server.ssl.keyPassword'),
      shared: shared,
    );
    if (!quiet) {
      final scheme = certPath == null ? 'http' : 'https';
      // ignore: avoid_print
      print('[diana] Listening on $scheme://$host:${_adapter.port}');
    }
  }

  /// The bound port, or `null` before [serve].
  int? get port => _adapter.port;

  Future<void> close() => _adapter.close();

  /// Rejects requests whose `Accept` header excludes the produced MIME type
  /// (406). `*/*` always passes, so browsers are unaffected.
  DianaHandler _withAcceptGuard(DianaHandler inner) {
    return (request) async {
      final response = await inner(request);
      final accept = request.header('accept');
      final mime = response.mimeType;
      if (accept == null || mime == null || acceptsMime(accept, mime)) {
        return response;
      }
      return DianaResponse(statusCode: 406);
    };
  }

  static void _defaultOnUnhandled(Object error, StackTrace stackTrace) {
    // ignore: avoid_print
    print('[diana] Unhandled error: $error\n$stackTrace');
  }
}
