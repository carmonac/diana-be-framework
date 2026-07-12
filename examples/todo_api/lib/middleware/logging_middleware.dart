import 'package:diana/diana.dart';

/// Global middleware: times every request and stamps a response header so
/// its effect is observable from the outside.
@GlobalMiddleware(order: 0)
class LoggingMiddleware implements Middleware {
  @override
  Future<DianaResponse> handle(DianaRequest request, Next next) async {
    final watch = Stopwatch()..start();
    final response = await next(request);
    print('[todo_api] ${request.method.name.toUpperCase()} ${request.path} '
        '-> ${response.statusCode} (${watch.elapsedMilliseconds}ms)');
    return response.copyWith(headers: {
      ...response.headers,
      'x-handled-by': 'diana',
    });
  }
}
