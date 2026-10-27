import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:diana/diana.dart';
import 'package:test/test.dart';

/// Request whose body arrives as a chunked byte stream (the adapter path):
/// no Content-Length, so only streaming enforcement can bound it.
DianaRequest streamedRequest(
  String body, {
  Map<String, List<String>> headers = const {},
  DianaRequestLimits limits = const DianaRequestLimits(),
  int chunkSize = 16,
}) {
  final bytes = utf8.encode(body);
  return DianaRequest(
    method: HttpMethod.post,
    uri: Uri.parse('/x'),
    headers: headers,
    bytesReader: () async* {
      for (var i = 0; i < bytes.length; i += chunkSize) {
        final end =
            (i + chunkSize < bytes.length) ? i + chunkSize : bytes.length;
        yield Uint8List.fromList(bytes.sublist(i, end));
      }
    },
    limits: limits,
  );
}

/// Request built with only a string reader (how most unit tests construct
/// DianaRequest) — the limit is checked after the read.
DianaRequest stringRequest(
  String body, {
  Map<String, List<String>> headers = const {},
  DianaRequestLimits limits = const DianaRequestLimits(),
}) =>
    DianaRequest(
      method: HttpMethod.post,
      uri: Uri.parse('/x'),
      headers: headers,
      bodyReader: () async => body,
      limits: limits,
    );

final _tooLarge = throwsA(isA<PayloadTooLargeException>());

void main() {
  const tiny = DianaRequestLimits(maxBodyBytes: 32);

  group('readBodyAsString size limit', () {
    test('oversized streamed body is a 413', () {
      final request = streamedRequest('x' * 100, limits: tiny);
      expect(request.readBodyAsString, _tooLarge);
    });

    test('under-limit streamed body passes and is cached', () async {
      final request = streamedRequest('hello world', limits: tiny);
      expect(await request.readBodyAsString(), 'hello world');
      expect(await request.readBodyAsString(), 'hello world');
    });

    test('oversized string-reader body is a 413', () {
      final request = stringRequest('x' * 100, limits: tiny);
      expect(request.readBodyAsString, _tooLarge);
    });

    test('declared oversize Content-Length rejects without reading', () {
      var read = false;
      final request = DianaRequest(
        method: HttpMethod.post,
        uri: Uri.parse('/x'),
        headers: {
          'content-length': ['1000'],
        },
        bytesReader: () {
          read = true;
          return const Stream<Uint8List>.empty();
        },
        limits: tiny,
      );
      expect(request.readBodyAsString, _tooLarge);
      expect(read, isFalse);
    });

    test('maxBodyBytes <= 0 disables the cap', () async {
      final request = streamedRequest(
        'x' * 100,
        limits: const DianaRequestLimits(maxBodyBytes: 0),
      );
      expect((await request.readBodyAsString()).length, 100);
    });

    test('respects a declared charset', () async {
      final request = DianaRequest(
        method: HttpMethod.post,
        uri: Uri.parse('/x'),
        headers: {
          'content-type': ['text/plain; charset=latin1'],
        },
        bytesReader: () =>
            Stream.value(Uint8List.fromList(latin1.encode('café'))),
      );
      expect(await request.readBodyAsString(), 'café');
    });
  });

  group('decode helpers inherit the limit', () {
    test('oversized JSON body is a 413, not a 400', () {
      final json = '{"data":"${'x' * 100}"}';
      final request = streamedRequest(
        json,
        headers: {
          'content-type': ['application/json'],
        },
        limits: tiny,
      );
      expect(() => decodeJsonMapBody(request), _tooLarge);
    });

    test('under-limit JSON decodes', () async {
      final request = streamedRequest(
        '{"a":1}',
        headers: {
          'content-type': ['application/json'],
        },
        limits: tiny,
      );
      expect(await decodeJsonMapBody(request), {'a': 1});
    });

    test('oversized urlencoded form body is a 413', () {
      final request = streamedRequest(
        'field=${'x' * 100}',
        headers: {
          'content-type': ['application/x-www-form-urlencoded'],
        },
        limits: tiny,
      );
      expect(() => decodeFormBody(request), _tooLarge);
    });
  });

  group('multipart keeps its own key', () {
    String multipartBody(String boundary, String content) => [
          '--$boundary',
          'Content-Disposition: form-data; name="file"; filename="f.txt"',
          'Content-Type: text/plain',
          '',
          content,
          '--$boundary--',
          '',
        ].join('\r\n');

    test('a small maxBodyBytes does not cap multipart uploads', () async {
      final body = multipartBody('XBOUND', 'file content here');
      final request = streamedRequest(
        body,
        headers: {
          'content-type': ['multipart/form-data; boundary=XBOUND'],
        },
        limits: const DianaRequestLimits(maxBodyBytes: 8),
      );
      final form = await decodeFormBody(request);
      expect(utf8.decode(form.file('file')!.bytes), 'file content here');
    });

    test('part headers and boundaries count toward multipartMaxBytes', () {
      // Part content is 17 bytes; the raw body (boundaries + part headers)
      // is far larger, so a limit above the content but below the raw size
      // must still reject.
      final body = multipartBody('XBOUND', 'file content here');
      final request = streamedRequest(
        body,
        headers: {
          'content-type': ['multipart/form-data; boundary=XBOUND'],
        },
        limits: const DianaRequestLimits(multipartMaxBytes: 50),
      );
      expect(() => decodeFormBody(request), _tooLarge);
    });
  });

  group('over a real server', () {
    test('oversized POST body yields HTTP 413', () async {
      final server = DianaServer(
          config: DianaConfig({
        'server.maxBodyBytes': 64,
      }))
        ..register(
          HttpMethod.post,
          '/echo',
          (req) async => DianaResponse.text(await req.readBodyAsString()),
        );
      await server.serve(port: 0, quiet: true);
      addTearDown(server.close);

      final (okStatus, okBody) = await _post(server.port!, '/echo', 'hello');
      expect(okStatus, 200);
      expect(okBody, contains('hello'));

      final (status, body) = await _post(server.port!, '/echo', 'x' * 200);
      expect(status, 413);
      expect(body, contains('payload_too_large'));
    });
  });
}

Future<(int, String)> _post(int port, String path, String body) async {
  final socket = await Socket.connect('127.0.0.1', port);
  socket.write('POST $path HTTP/1.1\r\n'
      'Host: 127.0.0.1\r\n'
      'Content-Type: text/plain\r\n'
      'Content-Length: ${utf8.encode(body).length}\r\n'
      'Connection: close\r\n\r\n'
      '$body');
  final response = await utf8.decodeStream(socket);
  socket.destroy();
  final status = int.parse(response.split(' ')[1]);
  return (status, response);
}
