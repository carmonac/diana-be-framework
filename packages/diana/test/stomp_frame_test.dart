import 'dart:convert';

import 'package:diana/diana.dart';
import 'package:test/test.dart';

StompFrame one(String text) {
  final frames = parseStompText(text);
  expect(frames, hasLength(1));
  return frames.single;
}

void expectParseError(String text, String message) {
  expect(
    () => parseStompText(text),
    throwsA(isA<StompParseException>()
        .having((e) => e.message, 'message', message)),
  );
}

void main() {
  group('parse — valid', () {
    test('CONNECT headers are not unescaped', () {
      // A literal backslash-n in a CONNECT header stays literal.
      final frame = one('CONNECT\naccept-version:1.2\nhost:a\\nb\n\n\x00');
      expect(frame.command, 'CONNECT');
      expect(frame.headers['accept-version'], '1.2');
      expect(frame.headers['host'], r'a\nb');
    });

    test('SEND headers are unescaped', () {
      final frame =
          one('SEND\ndestination:/a\nx:line1\\nline2\\ccolon\n\nhi\x00');
      expect(frame.headers['x'], 'line1\nline2:colon');
      expect(frame.body, 'hi');
    });

    test('repeated header keys: first wins', () {
      final frame = one('SEND\ndestination:/a\ndestination:/b\n\n\x00');
      expect(frame.headers['destination'], '/a');
    });

    test('CRLF line endings', () {
      final frame = one('SUBSCRIBE\r\nid:0\r\ndestination:/t\r\n\r\n\x00');
      expect(frame.command, 'SUBSCRIBE');
      expect(frame.headers, {'id': '0', 'destination': '/t'});
    });

    test('content-length body may contain NUL', () {
      final frame = one('SEND\ndestination:/a\ncontent-length:3\n\na\x00b\x00');
      expect(frame.body, 'a\x00b');
    });

    test('body runs to the first NUL without content-length', () {
      expect(one('SEND\ndestination:/a\n\nhello\x00').body, 'hello');
    });

    test('a heartbeat-only chunk yields no frames', () {
      expect(parseStompText('\n'), isEmpty);
      expect(parseStompText('\r\n'), isEmpty);
    });

    test('multiple frames and interleaved heartbeats in one chunk', () {
      final frames = parseStompText(
          '\nSUBSCRIBE\nid:0\ndestination:/t\n\n\x00\n\nSEND\n'
          'destination:/t\n\nhi\x00\n');
      expect(frames, hasLength(2));
      expect(frames[0].command, 'SUBSCRIBE');
      expect(frames[1].command, 'SEND');
      expect(frames[1].body, 'hi');
    });
  });

  group('parse — errors', () {
    test('unknown command', () {
      expectParseError('WOBBLE\n\n\x00',
          'malformed frame: unknown command "WOBBLE"');
    });

    test('header line without a colon', () {
      expectParseError('SEND\nbroken\n\n\x00',
          'malformed frame: header line without ":"');
    });

    test('invalid escape sequence', () {
      expectParseError('SEND\ndestination:/a\nx:bad\\q\n\n\x00',
          r'malformed frame: invalid escape sequence "\q" in header');
    });

    test('content-length not an integer', () {
      expectParseError('SEND\ndestination:/a\ncontent-length:xx\n\n\x00',
          'malformed frame: content-length is not an integer');
    });

    test('no NUL after a content-length body', () {
      expectParseError('SEND\ndestination:/a\ncontent-length:2\n\nabc\x00',
          'malformed frame: no NULL terminator after content-length body');
    });

    test('missing NUL terminator', () {
      expectParseError('SEND\ndestination:/a\n\nhello',
          'malformed frame: missing NULL terminator');
    });

    test('non-UTF-8 body bytes', () {
      final bytes = [
        ...utf8.encode('SEND\ndestination:/a\n\n'),
        0xFF, 0xFE,
        0x00,
      ];
      expect(
        () => parseStompChunk(bytes),
        throwsA(isA<StompParseException>().having((e) => e.message, 'm',
            'malformed frame: body is not valid UTF-8')),
      );
    });

    test('body not allowed on non-body commands', () {
      expectParseError('SUBSCRIBE\nid:0\ndestination:/t\n\noops\x00',
          'malformed frame: body not allowed for SUBSCRIBE');
    });
  });

  group('serialize', () {
    test('MESSAGE headers are escaped', () {
      final text = serializeStompFrame(const StompFrame(
        'MESSAGE',
        {'destination': '/t', 'x': 'a\nb:c'},
        'hi',
      ));
      expect(text, contains('x:a\\nb\\cc\n'));
      expect(text.endsWith('\x00'), isTrue);
    });

    test('CONNECTED headers are not escaped', () {
      final text = serializeStompFrame(const StompFrame(
        'CONNECTED',
        {'version': '1.2', 'heart-beat': '10000,10000'},
      ));
      expect(text, 'CONNECTED\nversion:1.2\nheart-beat:10000,10000\n\n\x00');
    });

    test('parse ∘ serialize round-trips a SEND with a multibyte body', () {
      const original = StompFrame(
        'SEND',
        {'destination': '/t', 'content-type': 'text/plain'},
        'café ☕',
      );
      final frame = one(serializeStompFrame(original));
      expect(frame.command, 'SEND');
      expect(frame.headers['destination'], '/t');
      expect(frame.body, 'café ☕');
    });
  });

  group('json payload helpers', () {
    test('decodes an object, rejects non-objects and malformed JSON', () {
      expect(stompJsonMap('{"a":1}'), {'a': 1});
      expect(() => stompJsonMap('[1,2]'),
          throwsA(isA<StompPayloadException>()));
      expect(() => stompJsonMap('not json'),
          throwsA(isA<StompPayloadException>()));
    });

    test('encodes a map', () {
      expect(stompJsonBody({'a': 1}), '{"a":1}');
    });
  });
}
