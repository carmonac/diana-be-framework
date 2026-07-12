import 'dart:async';

import 'adapter/relic_adapter.dart';
import 'config.dart';
import 'http/method.dart';
import 'middleware.dart';
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

  final RelicAdapter _adapter = RelicAdapter();

  DianaServer({
    this.config = const DianaConfig.empty(),
    this.globalMiddleware = const [],
    this.exceptionMapper,
    void Function(Object error, StackTrace stackTrace)? onUnhandled,
  }) : onUnhandled = onUnhandled ?? _defaultOnUnhandled;

  /// Registers a route. [middleware] is the controller-level plus
  /// route-level chain, in that order; global middleware wrap around it.
  void register(
    HttpMethod method,
    String path,
    DianaHandler handler, {
    List<Middleware> middleware = const [],
  }) {
    final chain = composeMiddleware(
      [...globalMiddleware, ...middleware],
      handler,
    );
    final guarded = withErrorBoundary(
      chain,
      mapper: exceptionMapper,
      onUnhandled: onUnhandled,
    );
    _adapter.register(method, path, guarded);
  }

  /// Registers a WebSocket endpoint at [path]. [factory] produces the
  /// handler per connection: a constant closure over a singleton for shared
  /// handlers, or a call to a transient factory for per-connection state.
  ///
  /// The HTTP middleware chain and exception boundary do not apply to
  /// WebSocket traffic; errors reach the handler's `onError`.
  void registerWebSocket(String path, WebSocketHandlerFactory factory) {
    _adapter.registerWebSocket(path, factory);
  }

  /// Starts the server on `server.host`/`server.port` from [config]
  /// (defaults: `0.0.0.0:8080`). [port] overrides the configured port —
  /// pass 0 in tests to get an ephemeral one.
  Future<void> serve({int? port, bool quiet = false}) async {
    final host = config.get<String>('server.host', defaultValue: '0.0.0.0');
    await _adapter.serve(
      host: host,
      port: port ?? config.get<int>('server.port', defaultValue: 8080),
    );
    if (!quiet) {
      // ignore: avoid_print
      print('[diana] Listening on http://$host:${_adapter.port}');
    }
  }

  /// The bound port, or `null` before [serve].
  int? get port => _adapter.port;

  Future<void> close() => _adapter.close();

  static void _defaultOnUnhandled(Object error, StackTrace stackTrace) {
    // ignore: avoid_print
    print('[diana] Unhandled error: $error\n$stackTrace');
  }
}
