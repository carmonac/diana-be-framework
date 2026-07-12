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
      }),
    );
    await server.serve(port: 0, quiet: true);
    port = server.port!;
  });

  tearDownAll(() => server.close());

  Future<(String, String?)> readAll(String path) async {
    final client = HttpClient();
    try {
      final res = await (await client
              .getUrl(Uri.parse('http://127.0.0.1:$port$path')))
          .close();
      final body = await res.transform(utf8.decoder).join();
      return (body, res.headers.contentType?.mimeType);
    } finally {
      client.close();
    }
  }

  test('Stream<ServerSentEvent> routes emit spec-framed events', () async {
    final (body, mime) = await readAll('/events/ticks');
    expect(mime, 'text/event-stream');
    expect(body, contains('id: 1\nevent: tick\ndata: tick 1\n\n'));
    expect(body, contains('id: 3\nevent: tick\ndata: tick 3\n\n'));
  });

  test('Stream<TodoDto> routes JSON-encode each event', () async {
    final (body, mime) = await readAll('/events/todos');
    expect(mime, 'text/event-stream');
    expect(body,
        contains('data: {"id":1,"title":"learn diana","done":false}\n\n'));
    expect(body,
        contains('data: {"id":2,"title":"stream events","done":false}\n\n'));
  });
}
