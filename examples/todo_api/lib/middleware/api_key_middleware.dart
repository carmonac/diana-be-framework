import 'package:diana/diana.dart';

/// Route-level guard applied with `@UseMiddleware`: requires an X-Api-Key
/// header matching the configured `app.apiKey`. Middleware participate in
/// dependency injection (including `@Value`) like any other component.
@Component()
class ApiKeyMiddleware implements Middleware {
  final String expected;

  ApiKeyMiddleware(@Value('app.apiKey', defaultValue: 'secret') this.expected);

  @override
  Future<DianaResponse> handle(DianaRequest request, Next next) async {
    if (request.header('x-api-key') != expected) {
      return DianaResponse.json(
        {'error': 'unauthorized', 'message': 'Missing or invalid API key.'},
        statusCode: 401,
      );
    }
    return await next(request);
  }
}
