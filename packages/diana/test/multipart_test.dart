import 'dart:convert';
import 'dart:io';

import 'package:diana/diana.dart';
import 'package:test/test.dart';

DianaRequest formRequest(
  String body, {
  required String contentType,
  DianaRequestLimits limits = const DianaRequestLimits(),
}) =>
    DianaRequest(
      method: HttpMethod.post,
      uri: Uri.parse('/upload'),
      headers: {
        'content-type': [contentType],
      },
      bodyReader: () async => body,
      limits: limits,
    );

String multipartBody(String boundary) => [
      '--$boundary',
      'Content-Disposition: form-data; name="title"',
      '',
      'my upload',
      '--$boundary',
      'Content-Disposition: form-data; name="file"; filename="notes.txt"',
      'Content-Type: text/plain',
      '',
      'file content here',
      '--$boundary--',
      '',
    ].join('\r\n');

void main() {
  group('decodeFormBody', () {
    test('parses multipart fields and files', () async {
      final request = formRequest(
        multipartBody('XBOUND'),
        contentType: 'multipart/form-data; boundary=XBOUND',
      );
      final form = await decodeFormBody(request);
      expect(form.fields, {'title': 'my upload'});
      final file = form.file('file')!;
      expect(file.filename, 'notes.txt');
      expect(file.contentType, 'text/plain');
      expect(utf8.decode(file.bytes), 'file content here');
      expect(form.file('nope'), isNull);
    });

    test('decodes multipart text fields as UTF-8', () async {
      final body = [
        '--XBOUND',
        'Content-Disposition: form-data; name="city"',
        '',
        'caf\u00e9 \u2615',
        '--XBOUND--',
        '',
      ].join('\r\n');
      final form = await decodeFormBody(formRequest(
        body,
        contentType: 'multipart/form-data; boundary=XBOUND',
      ));
      // Latin-1 decoding would yield mojibake ('caf\u00c3\u00a9 ...').
      expect(form.fields, {'city': 'caf\u00e9 \u2615'});
    });

    test('parses urlencoded bodies as fields', () async {
      final form = await decodeFormBody(formRequest(
        'a=1&b=hello%20world',
        contentType: 'application/x-www-form-urlencoded',
      ));
      expect(form.fields, {'a': '1', 'b': 'hello world'});
      expect(form.files, isEmpty);
    });

    test('rejects other content types with 415', () {
      expect(
        () =>
            decodeFormBody(formRequest('{}', contentType: 'application/json')),
        throwsA(isA<UnsupportedMediaTypeException>()),
      );
    });

    test('rejects oversized multipart bodies with 413', () {
      final request = formRequest(
        multipartBody('XBOUND'),
        contentType: 'multipart/form-data; boundary=XBOUND',
        limits: const DianaRequestLimits(multipartMaxBytes: 8),
      );
      expect(
        () => decodeFormBody(request),
        throwsA(isA<PayloadTooLargeException>()),
      );
    });

    test('missing boundary is a 400', () {
      expect(
        () => decodeFormBody(
            formRequest('x', contentType: 'multipart/form-data')),
        throwsA(isA<BadRequestException>()),
      );
    });
  });

  group('acceptsMime', () {
    test('wildcards, exact matches and q=0 exclusions', () {
      expect(acceptsMime('*/*', 'application/json'), isTrue);
      expect(acceptsMime('application/*', 'application/json'), isTrue);
      expect(acceptsMime('application/json', 'application/json'), isTrue);
      expect(acceptsMime('text/html', 'application/json'), isFalse);
      expect(acceptsMime('application/json;q=0', 'application/json'), isFalse);
      expect(acceptsMime('text/html, */*;q=0.8', 'application/json'), isTrue);
    });
  });

  group('Accept guard over DianaServer', () {
    test('incompatible Accept yields 406; */* passes', () async {
      final server = DianaServer()
        ..register(
            HttpMethod.get, '/data', (req) => DianaResponse.json({'ok': true}));
      await server.serve(port: 0, quiet: true);
      addTearDown(server.close);

      Future<int> statusFor(String accept) async {
        final (status, _) = await _get(server.port!, '/data', accept);
        return status;
      }

      expect(await statusFor('text/html'), 406);
      expect(await statusFor('application/json'), 200);
      expect(await statusFor('text/html, */*;q=0.8'), 200);
    });
  });
}

Future<(int, String)> _get(int port, String path, String accept) async {
  final socket = await Socket.connect('127.0.0.1', port);
  socket.write('GET $path HTTP/1.1\r\n'
      'Host: 127.0.0.1\r\n'
      'Accept: $accept\r\n'
      'Connection: close\r\n\r\n');
  final response = await utf8.decodeStream(socket);
  socket.destroy();
  final status = int.parse(response.split(' ')[1]);
  return (status, response);
}
