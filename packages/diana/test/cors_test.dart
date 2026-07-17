import 'dart:io';

import 'package:diana/diana.dart';
import 'package:test/test.dart';

void main() {
  group('CorsPolicy.allowOriginFor', () {
    test('wildcard without credentials is *', () {
      const policy = CorsPolicy();
      expect(policy.allowOriginFor('https://a.com'), '*');
      expect(policy.allowOriginFor(null), isNull);
    });

    test('wildcard with credentials echoes the origin', () {
      const policy = CorsPolicy(allowCredentials: true);
      expect(policy.allowOriginFor('https://a.com'), 'https://a.com');
    });

    test('explicit list matches exactly', () {
      const policy = CorsPolicy(allowedOrigins: ['https://a.com']);
      expect(policy.allowOriginFor('https://a.com'), 'https://a.com');
      expect(policy.allowOriginFor('https://evil.com'), isNull);
    });
  });

  group('CorsPolicy.fromConfig', () {
    test('disabled by default, reads keys when enabled', () {
      expect(CorsPolicy.fromConfig(const DianaConfig.empty()), isNull);
      final policy = CorsPolicy.fromConfig(DianaConfig({
        'server.cors.enabled': true,
        'server.cors.allowedOrigins': ['https://a.com'],
        'server.cors.allowCredentials': true,
        'server.cors.maxAge': 60,
      }))!;
      expect(policy.allowedOrigins, ['https://a.com']);
      expect(policy.allowCredentials, isTrue);
      expect(policy.maxAgeSeconds, 60);
    });
  });

  group('cache safety', () {
    test('denied or absent origins still get Vary: Origin (cache safety)',
        () async {
      const policy = CorsPolicy(allowedOrigins: ['https://ok.example']);
      final handler =
          withCors(policy, (req) async => const DianaResponse.text('hi'));

      final denied = await handler(DianaRequest(
        method: HttpMethod.get,
        uri: Uri.parse('/x'),
        headers: {
          'origin': ['https://evil.example'],
        },
      ));
      expect(denied.headers['access-control-allow-origin'], isNull);
      expect(denied.headers['vary'], 'Origin');

      final sameOrigin = await handler(
          DianaRequest(method: HttpMethod.get, uri: Uri.parse('/x')));
      expect(sameOrigin.headers['vary'], 'Origin');

      final preflight = corsPreflightHandler(const {});
      final deniedPreflight = await preflight(DianaRequest(
        method: HttpMethod.options,
        uri: Uri.parse('/x'),
        headers: {
          'origin': ['https://evil.example'],
          'access-control-request-method': ['DELETE'],
        },
      ));
      expect(deniedPreflight.headers['vary'], 'Origin');
    });
  });

  group('end-to-end over DianaServer', () {
    late DianaServer server;

    tearDown(() => server.close());

    Future<HttpClientResponse> send(
      String method,
      String path, {
      Map<String, String> headers = const {},
    }) async {
      final client = HttpClient();
      final request = await client.openUrl(
          method, Uri.parse('http://127.0.0.1:${server.port}$path'));
      headers.forEach(request.headers.set);
      final response = await request.close();
      client.close();
      return response;
    }

    test('actual responses get CORS headers; preflight is automatic',
        () async {
      server = DianaServer(
        config: DianaConfig({
          'server.cors.enabled': true,
          'server.cors.allowedOrigins': ['https://app.example'],
        }),
      )..register(HttpMethod.get, '/data',
          (req) => DianaResponse.json({'ok': true}));
      await server.serve(port: 0, quiet: true);

      final actual =
          await send('GET', '/data', headers: {'origin': 'https://app.example'});
      expect(actual.headers.value('access-control-allow-origin'),
          'https://app.example');
      expect(actual.headers.value('vary'), 'Origin');
      await actual.drain<void>();

      final denied =
          await send('GET', '/data', headers: {'origin': 'https://evil.com'});
      expect(denied.headers.value('access-control-allow-origin'), isNull);
      await denied.drain<void>();

      final preflight = await send('OPTIONS', '/data', headers: {
        'origin': 'https://app.example',
        'access-control-request-method': 'GET',
      });
      expect(preflight.statusCode, 204);
      expect(preflight.headers.value('access-control-allow-origin'),
          'https://app.example');
      expect(preflight.headers.value('access-control-allow-methods'),
          contains('GET'));
      expect(preflight.headers.value('access-control-max-age'), '3600');
      await preflight.drain<void>();

      final badPreflight = await send('OPTIONS', '/data', headers: {
        'origin': 'https://evil.com',
        'access-control-request-method': 'GET',
      });
      expect(badPreflight.statusCode, 204);
      expect(
          badPreflight.headers.value('access-control-allow-origin'), isNull);
      await badPreflight.drain<void>();
    });

    test('per-route policy works with global CORS disabled', () async {
      server = DianaServer()
        ..register(
          HttpMethod.get,
          '/open',
          (req) => const DianaResponse.text('ok'),
          cors: const CorsPolicy(),
        )
        ..register(HttpMethod.get, '/plain',
            (req) => const DianaResponse.text('ok'));
      await server.serve(port: 0, quiet: true);

      final open =
          await send('GET', '/open', headers: {'origin': 'https://a.com'});
      expect(open.headers.value('access-control-allow-origin'), '*');
      await open.drain<void>();

      final plain =
          await send('GET', '/plain', headers: {'origin': 'https://a.com'});
      expect(plain.headers.value('access-control-allow-origin'), isNull);
      await plain.drain<void>();
    });
  });
}
