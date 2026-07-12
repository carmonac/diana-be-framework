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
    final request = await client.openUrl(
      method,
      Uri.parse('http://127.0.0.1:$port$path'),
    );
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

void main() {
  setUpAll(() async {
    server = await buildDianaServer();
    await server.serve(port: 0);
    port = server.port!;
  });

  tearDownAll(() => server.close());

  test('GET /todos returns the seeded list', () async {
    final (status, body) = await call('GET', '/todos');
    expect(status, 200);
    expect(body, [
      {'id': 1, 'title': 'learn diana', 'done': false},
    ]);
  });

  test('GET /todos respects the limit query param default and override',
      () async {
    final (_, all) = await call('GET', '/todos?limit=0');
    expect(all, isEmpty);
  });

  test('GET /todos/:id binds the path param', () async {
    final (status, body) = await call('GET', '/todos/1');
    expect(status, 200);
    expect(body, containsPair('title', 'learn diana'));
  });

  test('GET /todos/:id with a non-numeric id is a 400', () async {
    final (status, body) = await call('GET', '/todos/abc');
    expect(status, 400);
    expect(body, containsPair('error', 'bad_request'));
    expect(body['message'], contains("'id' must be int"));
  });

  test('GET /todos/:id for a missing todo hits the @ControllerAdvice',
      () async {
    final (status, body) = await call('GET', '/todos/999');
    expect(status, 404);
    expect(body, {
      'error': 'todo_not_found',
      'id': 999,
      'path': '/todos/999',
    });
  });

  test('POST /todos creates and returns 201', () async {
    final (status, body) =
        await call('POST', '/todos', body: {'title': 'write tests'});
    expect(status, 201);
    expect(body, containsPair('title', 'write tests'));

    final (getStatus, fetched) = await call('GET', '/todos/${body['id']}');
    expect(getStatus, 200);
    expect(fetched, body);
  });

  test('POST /todos with a non-JSON content type is a 415', () async {
    final client = HttpClient();
    try {
      final request =
          await client.postUrl(Uri.parse('http://127.0.0.1:$port/todos'));
      request.headers.contentType = ContentType.text;
      request.write('hello');
      final response = await request.close();
      expect(response.statusCode, 415);
      await response.drain<void>();
    } finally {
      client.close();
    }
  });

  test('POST /todos with malformed JSON is a 400', () async {
    final client = HttpClient();
    try {
      final request =
          await client.postUrl(Uri.parse('http://127.0.0.1:$port/todos'));
      request.headers.contentType = ContentType.json;
      request.write('{not json');
      final response = await request.close();
      expect(response.statusCode, 400);
      await response.drain<void>();
    } finally {
      client.close();
    }
  });

  test('POST /todos with invalid data returns a structured 400', () async {
    final (status, body) = await call(
      'POST',
      '/todos',
      body: {'title': '   ', 'priority': 9},
    );
    expect(status, 400);
    expect(body['error'], 'validation_failed');
    expect(body['fields'], {
      'title': ['title is required'],
      'priority': ['must be at most 5'],
    });
  });

  test('DELETE /todos/:id without an API key is blocked by middleware',
      () async {
    final (status, body) = await call('DELETE', '/todos/1');
    expect(status, 401);
    expect(body, containsPair('error', 'unauthorized'));
    // The guard short-circuited before the handler: the todo still exists.
    final (stillThere, _) = await call('GET', '/todos/1');
    expect(stillThere, 200);
  });

  test('DELETE /todos/:id returns 204 and removes the todo', () async {
    final (_, created) =
        await call('POST', '/todos', body: {'title': 'temp'});
    final id = created['id'];
    final (status, body) = await call('DELETE', '/todos/$id',
        headers: {'x-api-key': 'secret'});
    expect(status, 204);
    expect(body, isNull);
    final (missing, _) = await call('GET', '/todos/$id');
    expect(missing, 404);
  });

  test('GET /info serves @ConfigurationProperties from application.yaml',
      () async {
    final (status, body) = await call('GET', '/info');
    expect(status, 200);
    expect(body, {'name': 'todo_api', 'version': '1.0.0'});
  });

  test('global middleware stamps every response', () async {
    final client = HttpClient();
    try {
      final request =
          await client.getUrl(Uri.parse('http://127.0.0.1:$port/todos'));
      final response = await request.close();
      expect(response.headers.value('x-handled-by'), 'diana');
      await response.drain<void>();
    } finally {
      client.close();
    }
  });
}
