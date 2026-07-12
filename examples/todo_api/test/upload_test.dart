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

  test('POST /uploads accepts multipart form data', () async {
    const boundary = 'DIANATESTBOUNDARY';
    final body = [
      '--$boundary',
      'Content-Disposition: form-data; name="description"',
      '',
      'proof of concept',
      '--$boundary',
      'Content-Disposition: form-data; name="doc"; filename="a.txt"',
      'Content-Type: text/plain',
      '',
      'hello diana',
      '--$boundary--',
      '',
    ].join('\r\n');

    final client = HttpClient();
    try {
      final request =
          await client.postUrl(Uri.parse('http://127.0.0.1:$port/uploads'));
      request.headers
          .set('content-type', 'multipart/form-data; boundary=$boundary');
      request.write(body);
      final response = await request.close();
      final decoded =
          jsonDecode(await response.transform(utf8.decoder).join());
      expect(response.statusCode, 201);
      expect(decoded['fields'], {'description': 'proof of concept'});
      expect(decoded['files'], [
        {
          'name': 'doc',
          'filename': 'a.txt',
          'contentType': 'text/plain',
          'size': 11,
        },
      ]);
    } finally {
      client.close();
    }
  });

  test('POST /uploads/echo takes a raw text body of any content type',
      () async {
    final client = HttpClient();
    try {
      final request = await client
          .postUrl(Uri.parse('http://127.0.0.1:$port/uploads/echo'));
      request.headers.set('content-type', 'text/plain');
      request.write('shout this');
      final response = await request.close();
      expect(response.statusCode, 200);
      expect(await response.transform(utf8.decoder).join(), 'SHOUT THIS');
    } finally {
      client.close();
    }
  });
}
