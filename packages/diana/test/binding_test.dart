import 'package:diana/diana.dart';
import 'package:test/test.dart';

DianaRequest req({
  Map<String, String> path = const {},
  String query = '',
  Map<String, List<String>> headers = const {},
  String body = '',
}) =>
    DianaRequest(
      method: HttpMethod.get,
      uri: Uri.parse('/x${query.isEmpty ? '' : '?$query'}'),
      pathParameters: path,
      headers: headers,
      bodyReader: () async => body,
    );

void main() {
  group('bindPathParam', () {
    test('converts to int, double, num, bool and String', () {
      final r = req(path: {
        'i': '42',
        'd': '3.5',
        'n': '7',
        'b': 'true',
        's': 'hi',
      });
      expect(bindPathParam<int>(r, 'i'), 42);
      expect(bindPathParam<double>(r, 'd'), 3.5);
      expect(bindPathParam<num>(r, 'n'), 7);
      expect(bindPathParam<bool>(r, 'b'), isTrue);
      expect(bindPathParam<String>(r, 's'), 'hi');
    });

    test('throws BadRequest with a precise message on parse failure', () {
      expect(
        () => bindPathParam<int>(req(path: {'id': 'abc'}), 'id'),
        throwsA(isA<BadRequestException>().having((e) => e.message, 'message',
            "Path parameter 'id' must be int, got 'abc'.")),
      );
    });
  });

  group('bindQueryParam', () {
    test('applies the default when absent', () {
      expect(bindQueryParam<int>(req(), 'limit', defaultValue: '20'), 20);
    });

    test('nullable type makes the parameter optional', () {
      expect(bindQueryParam<int?>(req(), 'limit'), isNull);
      expect(bindQueryParam<int?>(req(query: 'limit=5'), 'limit'), 5);
    });

    test('missing required parameter is a 400', () {
      expect(
        () => bindQueryParam<int>(req(), 'limit'),
        throwsA(isA<BadRequestException>().having((e) => e.message, 'message',
            "Missing required Query parameter 'limit'.")),
      );
    });

    test('bool accepts 1/0/true/false case-insensitively', () {
      expect(bindQueryParam<bool>(req(query: 'a=1'), 'a'), isTrue);
      expect(bindQueryParam<bool>(req(query: 'a=FALSE'), 'a'), isFalse);
    });
  });

  group('bindHeader', () {
    test('reads case-insensitively and converts', () {
      final r = req(headers: {
        'X-Retries': ['3'],
      });
      expect(bindHeader<int>(r, 'x-retries'), 3);
      expect(bindHeader<String?>(r, 'x-missing'), isNull);
    });
  });

  group('decodeJsonMapBody', () {
    test('decodes a JSON object', () async {
      final r = req(
        headers: {
          'content-type': ['application/json'],
        },
        body: '{"a": 1}',
      );
      expect(await decodeJsonMapBody(r), {'a': 1});
    });

    test('accepts +json content types and missing content type', () async {
      final r1 = req(
        headers: {
          'content-type': ['application/vnd.api+json'],
        },
        body: '{}',
      );
      expect(await decodeJsonMapBody(r1), isEmpty);
      expect(await decodeJsonMapBody(req(body: '{}')), isEmpty);
    });

    test('rejects non-JSON content types with 415', () {
      final r = req(
        headers: {
          'content-type': ['text/plain'],
        },
        body: '{}',
      );
      expect(
        () => decodeJsonMapBody(r),
        throwsA(isA<UnsupportedMediaTypeException>()),
      );
    });

    test('rejects malformed, empty and non-object bodies with 400', () {
      expect(() => decodeJsonMapBody(req(body: '{oops')),
          throwsA(isA<BadRequestException>()));
      expect(() => decodeJsonMapBody(req()),
          throwsA(isA<BadRequestException>()));
      expect(() => decodeJsonMapBody(req(body: '[1]')),
          throwsA(isA<BadRequestException>()));
    });
  });

  group('decodeJsonListBody', () {
    test('decodes arrays and rejects objects', () async {
      expect(await decodeJsonListBody(req(body: '[1, 2]')), [1, 2]);
      expect(() => decodeJsonListBody(req(body: '{}')),
          throwsA(isA<BadRequestException>()));
    });
  });
}
