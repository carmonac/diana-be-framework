import 'dart:convert';
import 'dart:io';

import 'package:diana/diana.dart';
import 'package:test/test.dart';

void main() {
  late Directory dir;
  late DianaServer server;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('diana_static');
    File('${dir.path}/hello.txt').writeAsStringSync('hello static');
    File('${dir.path}/index.html').writeAsStringSync('<h1>home</h1>');
    Directory('${dir.path}/css').createSync();
    File('${dir.path}/css/site.css').writeAsStringSync('body {}');
  });

  tearDown(() async {
    await server.close();
    dir.deleteSync(recursive: true);
  });

  Future<(int, String, String?)> get(String path) async {
    final client = HttpClient();
    try {
      final res = await (await client
              .getUrl(Uri.parse('http://127.0.0.1:${server.port}$path')))
          .close();
      final body = await res.transform(utf8.decoder).join();
      return (res.statusCode, body, res.headers.value('cache-control'));
    } finally {
      client.close();
    }
  }

  test('serves files, nested paths, index and 404s under the prefix',
      () async {
    server = DianaServer(
      config: DianaConfig({
        'server.static.enabled': true,
        'server.static.dir': dir.path,
        'server.static.prefix': '/static',
        'server.static.cacheMaxAge': 60,
      }),
    )..register(HttpMethod.get, '/api/ping',
        (req) => const DianaResponse.text('pong'));
    await server.serve(port: 0, quiet: true);

    final (fileStatus, fileBody, cache) = await get('/static/hello.txt');
    expect(fileStatus, 200);
    expect(fileBody, 'hello static');
    expect(cache, contains('max-age=60'));

    final (nested, css, _) = await get('/static/css/site.css');
    expect(nested, 200);
    expect(css, 'body {}');

    final (rootStatus, rootBody, _) = await get('/static');
    expect(rootStatus, 200);
    expect(rootBody, '<h1>home</h1>');

    final (missing, _, _) = await get('/static/nope.js');
    expect(missing, 404);

    // Path traversal is blocked by the engine's static handler.
    final (traversal, _, _) = await get('/static/..%2F..%2Fetc%2Fpasswd');
    expect(traversal, anyOf(404, 400));

    // API routes coexist with the static mount.
    final (api, pong, _) = await get('/api/ping');
    expect(api, 200);
    expect(pong, 'pong');
  });

  test('SPA fallback serves index.html on any miss', () async {
    server = DianaServer(
      config: DianaConfig({
        'server.static.enabled': true,
        'server.static.dir': dir.path,
        'server.static.prefix': '/app',
        'server.static.spa': true,
      }),
    );
    await server.serve(port: 0, quiet: true);

    final (status, body, _) = await get('/app/some/client/route');
    expect(status, 200);
    expect(body, '<h1>home</h1>');
  });
}
