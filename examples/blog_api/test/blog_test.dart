import 'dart:convert';
import 'dart:io';

import 'package:blog_api/app.diana_app.dart';
import 'package:diana/diana.dart';
import 'package:test/test.dart';

late DianaApp appInstance;
late int port;

Future<(int, dynamic)> call(String method, String path, {Object? body}) async {
  final client = HttpClient();
  try {
    final req =
        await client.openUrl(method, Uri.parse('http://127.0.0.1:$port$path'));
    if (body != null) {
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode(body));
    }
    final res = await req.close();
    final text = await res.transform(utf8.decoder).join();
    return (res.statusCode, text.isEmpty ? null : jsonDecode(text));
  } finally {
    client.close();
  }
}

DianaConfig config() => DianaConfig({
      'server.port': 0,
      'management.enabled': true,
      'db.file': ':memory:',
      'db.migrations.dir': 'migrations',
    });

void main() {
  setUp(() async {
    // Fresh in-memory database per test.
    appInstance = await buildDianaApp(config: config());
    await appInstance.initialize();
    await appInstance.server.serve(quiet: true);
    port = appInstance.server.port!;
  });
  tearDown(() async {
    await appInstance.server.close();
    await appInstance.dispose();
  });

  test('migrations ran: the posts table is queryable and starts empty',
      () async {
    final (status, body) = await call('GET', '/posts');
    expect(status, 200);
    expect(body, isEmpty);
  });

  test('a @Transactional method commits both inserts', () async {
    final (status, body) = await call('POST', '/posts', body: {
      'first': {'title': 'a', 'body': 'aa'},
      'second': {'title': 'b', 'body': 'bb'},
    });
    expect(status, 201);
    expect(body, hasLength(2));

    final (_, all) = await call('GET', '/posts');
    expect(all, hasLength(2));
  });

  test('a throwing @Transactional method rolls back its insert', () async {
    final (status, _) =
        await call('POST', '/posts/fail', body: {'title': 'x', 'body': 'xx'});
    expect(status, 409);

    // The insert before the throw must have been undone.
    final (_, all) = await call('GET', '/posts');
    expect(all, isEmpty, reason: 'the transaction rolled back');
  });

  test('the database health indicator reports up', () async {
    final (status, body) = await call('GET', '/actuator/health');
    expect(status, 200);
    expect(body['components']['database']['status'], 'UP');
  });
}
