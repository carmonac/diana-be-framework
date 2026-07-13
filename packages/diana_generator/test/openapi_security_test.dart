import 'package:diana_generator/src/model/summary.dart';
import 'package:diana_generator/src/openapi/openapi_builder.dart';
import 'package:test/test.dart';

RouteInfo _route(String method, String path, {SecurityInfo? security}) =>
    RouteInfo(
      httpMethod: method,
      path: path,
      methodName: 'op_$path',
      adapterName: r'$diana$C$op',
      security: security,
      api: const RouteApi(returnShape: 'text'),
    );

LibrarySummary _summary(ControllerInfo controller) => LibrarySummary(
      libraryUri: 'package:a/c.dart',
      controllers: [controller],
    );

void main() {
  test('secured routes get per-operation security and a bearer scheme', () {
    final doc = buildOpenApiDocument([
      _summary(ControllerInfo(
        type: const TypeRef(libraryUri: 'package:a/c.dart', name: 'C'),
        basePath: '/admin',
        security: const SecurityInfo(), // controller-wide @Secured
        routes: [
          _route('GET', '/stats'),
          // Method @RolesAllowed still projects the same generic scheme.
          _route('GET', '/audit', security: const SecurityInfo(roles: ['a'])),
        ],
      )),
    ]);

    final components = doc['components'] as Map<String, Object?>;
    expect(components['securitySchemes'], {
      'bearerAuth': {'type': 'http', 'scheme': 'bearer'},
    });
    final paths = doc['paths'] as Map<String, Object?>;
    final stats = (paths['/admin/stats'] as Map)['get'] as Map;
    expect(stats['security'], [
      {'bearerAuth': <Object?>[]},
    ]);
  });

  test('auth-free apps emit no security keys (byte identity)', () {
    final doc = buildOpenApiDocument([
      _summary(ControllerInfo(
        type: const TypeRef(libraryUri: 'package:a/c.dart', name: 'C'),
        basePath: '/x',
        routes: [_route('GET', '/hello')],
      )),
    ]);
    expect(doc.containsKey('components'), isFalse,
        reason: 'no schemas and no security ⇒ no components block');
    final op = ((doc['paths'] as Map)['/x/hello'] as Map)['get'] as Map;
    expect(op.containsKey('security'), isFalse);
  });
}
