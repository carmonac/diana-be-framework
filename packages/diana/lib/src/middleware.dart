import 'dart:async';

import 'http/request.dart';
import 'http/response.dart';

/// A request handler: the composed unit of Diana's pipeline.
typedef DianaHandler = FutureOr<DianaResponse> Function(DianaRequest request);

/// Continuation passed to [Middleware.handle].
typedef Next = FutureOr<DianaResponse> Function(DianaRequest request);

/// Spring-style interceptor around request handling.
///
/// Implementations call `next(request)` to continue the chain, or return a
/// response directly to short-circuit (e.g. a 401):
///
/// ```dart
/// @GlobalMiddleware(order: 0)
/// class LoggingMiddleware implements Middleware {
///   @override
///   Future<DianaResponse> handle(DianaRequest req, Next next) async {
///     final watch = Stopwatch()..start();
///     final res = await next(req);
///     print('${req.method.name} ${req.path} -> '
///         '${res.statusCode} (${watch.elapsedMilliseconds}ms)');
///     return res;
///   }
/// }
/// ```
abstract interface class Middleware {
  FutureOr<DianaResponse> handle(DianaRequest request, Next next);
}
