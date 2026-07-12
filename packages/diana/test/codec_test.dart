import 'package:diana/diana.dart';
import 'package:test/test.dart';

class CsvCodec implements BodyCodec {
  @override
  List<String> get mimeTypes => const ['text/csv'];

  @override
  Object? decode(String body) =>
      [for (final line in body.trim().split('\n')) line.split(',')];

  @override
  String encode(Object? value) =>
      [for (final row in value as List) (row as List).join(',')].join('\n');
}

DianaRequest request({
  String? contentType,
  String? accept,
  String body = '',
  BodyCodecRegistry codecs = const BodyCodecRegistry(),
}) =>
    DianaRequest(
      method: HttpMethod.post,
      uri: Uri.parse('/x'),
      headers: {
        if (contentType != null) 'content-type': [contentType],
        if (accept != null) 'accept': [accept],
      },
      bodyReader: () async => body,
      codecs: codecs,
    );

void main() {
  group('BodyCodecRegistry', () {
    test('JSON is always available, including +json suffixes and params', () {
      const registry = BodyCodecRegistry();
      expect(registry.forMime('application/json'), isA<JsonBodyCodec>());
      expect(registry.forMime('application/vnd.api+json'),
          isA<JsonBodyCodec>());
      expect(registry.forMime('application/json; charset=utf-8'),
          isA<JsonBodyCodec>());
      expect(registry.forMime('text/csv'), isNull);
    });

    test('extra codecs take precedence and are matched by mime', () {
      final registry = BodyCodecRegistry([CsvCodec()]);
      expect(registry.forMime('text/csv'), isA<CsvCodec>());
      expect(registry.forMime('application/json'), isA<JsonBodyCodec>());
    });
  });

  group('decodeMapBody', () {
    test('decodes with the matching codec', () async {
      final req = request(
        contentType: 'application/json',
        body: '{"a": 1}',
      );
      expect(await decodeMapBody(req, consumes: const ['application/json']),
          {'a': 1});
    });

    test('415 when content type is not in consumes', () {
      final req = request(contentType: 'text/csv', body: 'a,b');
      expect(
        () => decodeMapBody(req, consumes: const ['application/json']),
        throwsA(isA<UnsupportedMediaTypeException>().having(
          (e) => e.message,
          'message',
          "Expected one of application/json, got 'text/csv'.",
        )),
      );
    });

    test('415 when no codec is registered for an allowed type', () {
      final req = request(contentType: 'application/xml', body: '<a/>');
      expect(
        () => decodeMapBody(req, consumes: const ['application/xml']),
        throwsA(isA<UnsupportedMediaTypeException>().having(
          (e) => e.message,
          'message',
          contains("No body codec registered for 'application/xml'"),
        )),
      );
    });

    test('400 on malformed input and non-object payloads', () {
      final malformed =
          request(contentType: 'application/json', body: '{oops');
      expect(
        () => decodeMapBody(malformed, consumes: const ['application/json']),
        throwsA(isA<BadRequestException>().having((e) => e.message, 'message',
            'Malformed application/json body.')),
      );
      final list = request(contentType: 'application/json', body: '[1]');
      expect(
        () => decodeMapBody(list, consumes: const ['application/json']),
        throwsA(isA<BadRequestException>().having(
            (e) => e.message, 'message', 'Expected an object body.')),
      );
    });
  });

  group('negotiatedResponse', () {
    test('picks the first produced type the client accepts', () {
      final req = request(
        accept: 'text/csv',
        codecs: BodyCodecRegistry([CsvCodec()]),
      );
      final response = negotiatedResponse(
        req,
        [
          ['a', 'b'],
        ],
        produces: const ['application/json', 'text/csv'],
      );
      expect(response.mimeType, 'text/csv');
      expect(response.bodyText, 'a,b');
    });

    test('server preference order wins on */*', () {
      final req = request(
        accept: '*/*',
        codecs: BodyCodecRegistry([CsvCodec()]),
      );
      final response = negotiatedResponse(req, {'a': 1},
          produces: const ['application/json', 'text/csv']);
      expect(response.mimeType, 'application/json');
      expect(response.bodyText, '{"a":1}');
    });

    test('406 when nothing produced is acceptable', () {
      final req = request(accept: 'text/html');
      expect(
        () => negotiatedResponse(req, {},
            produces: const ['application/json']),
        throwsA(isA<NotAcceptableException>()),
      );
    });

    test('missing Accept means anything goes', () {
      final response = negotiatedResponse(request(), {'a': 1},
          produces: const ['application/json'], statusCode: 201);
      expect(response.statusCode, 201);
      expect(response.mimeType, 'application/json');
    });
  });
}
