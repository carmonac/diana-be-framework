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

  Future<(int, String, String?)> post(
    String path,
    String body, {
    required String contentType,
    String? accept,
  }) async {
    final client = HttpClient();
    try {
      final request =
          await client.postUrl(Uri.parse('http://127.0.0.1:$port$path'));
      request.headers.set('content-type', contentType);
      if (accept != null) request.headers.set('accept', accept);
      request.write(body);
      final response = await request.close();
      final text = await response.transform(utf8.decoder).join();
      return (
        response.statusCode,
        text,
        response.headers.contentType?.mimeType,
      );
    } finally {
      client.close();
    }
  }

  const xmlBody = '<request><title>from xml</title>'
      '<priority>2</priority></request>';

  test('XML body decodes into the DTO and negotiates an XML response',
      () async {
    final (status, body, mime) = await post(
      '/todos/xml',
      xmlBody,
      contentType: 'application/xml',
      accept: 'application/xml',
    );
    expect(status, 201);
    expect(mime, 'application/xml');
    expect(body, contains('<title>from xml</title>'));
    expect(body, startsWith('<response>'));
  });

  test('Accept: application/json negotiates JSON from the same route',
      () async {
    final (status, body, mime) = await post(
      '/todos/xml',
      xmlBody,
      contentType: 'application/xml',
      accept: 'application/json',
    );
    expect(status, 201);
    expect(mime, 'application/json');
    expect(jsonDecode(body), containsPair('title', 'from xml'));
  });

  test('validation still applies to XML bodies', () async {
    final (status, body, _) = await post(
      '/todos/xml',
      '<request><title>   </title><priority>9</priority></request>',
      contentType: 'application/xml',
      accept: 'application/json',
    );
    expect(status, 400);
    expect(jsonDecode(body)['error'], 'validation_failed');
  });

  test('unlisted content type is a 415; unacceptable Accept is a 406',
      () async {
    final (unsupported, _, _) = await post(
      '/todos/xml',
      '{"title": "x"}',
      contentType: 'application/json',
    );
    expect(unsupported, 415);

    final (notAcceptable, _, _) = await post(
      '/todos/xml',
      xmlBody,
      contentType: 'application/xml',
      accept: 'text/html',
    );
    expect(notAcceptable, 406);
  });
}
