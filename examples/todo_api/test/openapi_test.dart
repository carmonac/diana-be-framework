import 'dart:convert';
import 'dart:io';

import 'package:diana/diana.dart';
import 'package:test/test.dart';
import 'package:todo_api/app.diana_app.dart';

void main() {
  late DianaServer server;
  late int port;

  setUpAll(() async {
    server = await buildDianaServer(
      config: DianaConfig({
        'app.info.name': 'test',
        'app.info.version': '0.0.0',
        'server.openapi.enabled': true,
        'server.openapi.title': 'Todo API',
        'server.openapi.version': '1.2.3',
      }),
    );
    await server.serve(port: 0, quiet: true);
    port = server.port!;
  });

  tearDownAll(() => server.close());

  test('GET /openapi.json serves the spec with patched info', () async {
    final client = HttpClient();
    try {
      final res = await (await client
              .getUrl(Uri.parse('http://127.0.0.1:$port/openapi.json')))
          .close();
      expect(res.statusCode, 200);
      expect(res.headers.contentType?.mimeType, 'application/json');
      final doc = jsonDecode(await res.transform(utf8.decoder).join())
          as Map<String, dynamic>;

      expect(doc['openapi'], '3.0.3');
      expect(doc['info'], {'title': 'Todo API', 'version': '1.2.3'});

      // Cross-check: every REST route of the app appears in the spec.
      final paths = doc['paths'] as Map<String, dynamic>;
      expect(paths.keys, containsAll(<String>[
        '/todos',
        '/todos/{id}',
        '/info',
        '/audit',
        '/uploads',
        '/uploads/echo',
      ]));
      expect((paths['/todos'] as Map).keys, containsAll(['get', 'post']));
      expect(
          (paths['/todos/{id}'] as Map).keys, containsAll(['get', 'delete']));

      // Parameter and body metadata survive.
      final create = paths['/todos']['post'] as Map<String, dynamic>;
      expect(
        create['requestBody']['content']['application/json']['schema'],
        {r'$ref': '#/components/schemas/CreateTodoRequest'},
      );
      expect(create['responses'].keys, ['201']);

      // Validation constraints map into the schema.
      final schema = doc['components']['schemas']['CreateTodoRequest']
          as Map<String, dynamic>;
      expect(schema['required'], ['title']);
      expect(schema['properties']['title'],
          {'type': 'string', 'maxLength': 120, 'minLength': 1});
      expect(schema['properties']['priority'],
          {'type': 'integer', 'minimum': 1, 'maximum': 5});
    } finally {
      client.close();
    }
  });

  test('the endpoint is absent when server.openapi.enabled is false',
      () async {
    final disabled = await buildDianaServer(
      config: DianaConfig({
        'app.info.name': 'test',
        'app.info.version': '0.0.0',
      }),
    );
    await disabled.serve(port: 0, quiet: true);
    addTearDown(disabled.close);

    final client = HttpClient();
    try {
      final res = await (await client.getUrl(
              Uri.parse('http://127.0.0.1:${disabled.port}/openapi.json')))
          .close();
      expect(res.statusCode, 404);
      await res.drain<void>();
    } finally {
      client.close();
    }
  });
}
