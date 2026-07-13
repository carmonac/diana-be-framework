import 'dart:convert';
import 'dart:io';

import 'package:diana/diana.dart';
import 'package:test/test.dart';
import 'package:todo_api/app.diana_app.dart';

late DianaServer server;
late int port;

Future<(int, dynamic)> call(
  String method,
  String path, {
  Object? body,
  Map<String, String> headers = const {},
}) async {
  final client = HttpClient();
  try {
    final request =
        await client.openUrl(method, Uri.parse('http://127.0.0.1:$port$path'));
    headers.forEach(request.headers.add);
    if (body != null) {
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(body));
    }
    final response = await request.close();
    final text = await response.transform(utf8.decoder).join();
    return (response.statusCode, text.isEmpty ? null : jsonDecode(text));
  } finally {
    client.close();
  }
}

Future<String> login(String username, String password) async {
  final (status, body) = await call('POST', '/auth/login',
      body: {'username': username, 'password': password});
  expect(status, 200);
  return body['token'] as String;
}

void main() {
  setUpAll(() async {
    server = await buildDianaServer();
    await server.serve(port: 0, quiet: true);
    port = server.port!;
  });
  tearDownAll(() => server.close());

  test('login mints a JWT accepted by @Secured routes', () async {
    final token = await login('ada', 'password');
    final (status, body) = await call('GET', '/auth/me',
        headers: {'authorization': 'Bearer $token'});
    expect(status, 200);
    expect(body, {
      'name': 'ada',
      'roles': ['admin'],
    });
  });

  test('login rejects bad credentials', () async {
    final (status, body) =
        await call('POST', '/auth/login', body: {'username': 'ada', 'password': 'nope'});
    expect(status, 401);
    expect(body, containsPair('error', 'unauthorized'));
  });

  test('@Secured route is 401 for anonymous requests', () async {
    final (status, body) = await call('GET', '/auth/me');
    expect(status, 401);
    expect(body, containsPair('error', 'unauthorized'));
  });

  test('an invalid bearer token is a 401 with a WWW-Authenticate challenge',
      () async {
    final client = HttpClient();
    try {
      final req = await client
          .getUrl(Uri.parse('http://127.0.0.1:$port/auth/me'));
      req.headers.add('authorization', 'Bearer not.a.jwt');
      final res = await req.close();
      expect(res.statusCode, 401);
      expect(res.headers.value('www-authenticate'), contains('Bearer'));
      await res.drain<void>();
    } finally {
      client.close();
    }
  });

  test('@RolesAllowed(admin): non-admin gets 403, admin succeeds', () async {
    final userToken = await login('bob', 'password');
    final (created, todo) =
        await call('POST', '/todos', body: {'title': 'delete me'});
    expect(created, 201);

    // Authenticated but only the 'user' role → 403.
    final (forbidden, body) = await call('DELETE', '/todos/${todo['id']}',
        headers: {'authorization': 'Bearer $userToken'});
    expect(forbidden, 403);
    expect(body, containsPair('error', 'forbidden'));

    // The admin JWT succeeds.
    final adminToken = await login('ada', 'password');
    final (ok, _) = await call('DELETE', '/todos/${todo['id']}',
        headers: {'authorization': 'Bearer $adminToken'});
    expect(ok, 204);
  });

  test('the API-key scheme still authorizes admin routes', () async {
    final (created, todo) =
        await call('POST', '/todos', body: {'title': 'via key'});
    expect(created, 201);
    final (ok, _) = await call('DELETE', '/todos/${todo['id']}',
        headers: {'x-api-key': 'secret'});
    expect(ok, 204);
  });
}
