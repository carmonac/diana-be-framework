import 'dart:async';

import 'exceptions.dart';
import 'http/request.dart';
import 'http/response.dart';
import 'middleware.dart';

/// Maps an exception to a response, or `null` to fall through to Diana's
/// built-in handling. Implemented by generated `@ControllerAdvice` chains.
typedef ExceptionMapper = FutureOr<DianaResponse?> Function(
  Object error,
  StackTrace stackTrace,
  DianaRequest request,
);

/// Folds [middleware] around [handler], outermost first: the first element
/// sees the request first and the response last.
DianaHandler composeMiddleware(
  List<Middleware> middleware,
  DianaHandler handler,
) {
  var composed = handler;
  for (final m in middleware.reversed) {
    final next = composed;
    composed = (request) => m.handle(request, next);
  }
  return composed;
}

/// Wraps [handler] in Diana's exception boundary.
///
/// Order of precedence: [ValidationException] → structured 400;
/// [mapper] (generated advice chain); [HttpException] → its status code;
/// anything else → opaque 500 (details go to [onUnhandled], never the
/// client).
DianaHandler withErrorBoundary(
  DianaHandler handler, {
  ExceptionMapper? mapper,
  void Function(Object error, StackTrace stackTrace)? onUnhandled,
}) {
  return (request) async {
    try {
      return await handler(request);
    } on ValidationException catch (e) {
      return DianaResponse.json(
        {'error': 'validation_failed', 'fields': e.fieldMap},
        statusCode: 400,
      );
    } catch (e, st) {
      final mapped = await mapper?.call(e, st, request);
      if (mapped != null) return mapped;
      if (e is HttpException) {
        return DianaResponse.json(
          {'error': e.reason, 'message': e.message},
          statusCode: e.statusCode,
        );
      }
      onUnhandled?.call(e, st);
      return DianaResponse.json(
        {'error': 'internal_server_error'},
        statusCode: 500,
      );
    }
  };
}
