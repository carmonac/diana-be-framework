/// STOMP 1.2 frame codec — byte-level parser and serializer, dependency
/// free. Operates on UTF-8 octets: `content-length` counts octets and a
/// body may contain NUL when it is present; without it the body runs to
/// the first NUL. Header escaping (`\\`, `\n`, `\r`, `\c`) applies to
/// every frame except `CONNECT`/`STOMP`/`CONNECTED`, per the spec.
library;

import 'dart:convert';

/// One STOMP frame: canonical upper-case [command], first-occurrence-wins
/// unescaped [headers], and the UTF-8 [body].
class StompFrame {
  final String command;
  final Map<String, String> headers;
  final String body;

  const StompFrame(this.command, [this.headers = const {}, this.body = '']);

  @override
  String toString() => 'StompFrame($command, $headers, ${body.length}b)';
}

/// Thrown for malformed input; the message becomes the ERROR frame's
/// `message:` header.
class StompParseException implements Exception {
  final String message;
  const StompParseException(this.message);

  @override
  String toString() => 'StompParseException: $message';
}

/// A bare EOL — the STOMP heartbeat unit.
const String stompHeartbeat = '\n';

const Set<String> _clientCommands = {
  'CONNECT',
  'STOMP',
  'SEND',
  'SUBSCRIBE',
  'UNSUBSCRIBE',
  'ACK',
  'NACK',
  'BEGIN',
  'COMMIT',
  'ABORT',
  'DISCONNECT',
};
const Set<String> _serverCommands = {
  'CONNECTED',
  'MESSAGE',
  'RECEIPT',
  'ERROR'
};

/// Frames whose headers are NOT escaped (spec: CONNECT and CONNECTED; the
/// 1.2 `STOMP` connect frame is treated like CONNECT).
const Set<String> _unescapedCommands = {'CONNECT', 'STOMP', 'CONNECTED'};

/// Commands allowed to carry a body.
const Set<String> _bodyCommands = {'SEND', 'MESSAGE', 'ERROR'};

/// Parses one WebSocket text message into zero or more frames (heartbeat
/// EOLs between and around frames are consumed silently).
List<StompFrame> parseStompText(String text) =>
    parseStompChunk(utf8.encode(text));

/// Byte-level variant of [parseStompText] (also used for binary WS frames).
List<StompFrame> parseStompChunk(List<int> bytes) {
  final frames = <StompFrame>[];
  var pos = 0;

  bool atEol(int p) =>
      p < bytes.length &&
      (bytes[p] == 0x0A ||
          (bytes[p] == 0x0D && p + 1 < bytes.length && bytes[p + 1] == 0x0A));
  int skipEol(int p) => bytes[p] == 0x0D ? p + 2 : p + 1;

  while (pos < bytes.length) {
    // Consume heartbeat EOLs.
    while (pos < bytes.length && atEol(pos)) {
      pos = skipEol(pos);
    }
    if (pos >= bytes.length) break;

    // Command line.
    final commandEnd = _findEol(bytes, pos);
    if (commandEnd == null) {
      throw const StompParseException('malformed frame: incomplete frame');
    }
    final command = _decodeUtf8(bytes.sublist(pos, commandEnd.start));
    if (!_clientCommands.contains(command) &&
        !_serverCommands.contains(command)) {
      throw StompParseException('malformed frame: unknown command "$command"');
    }
    pos = commandEnd.next;
    final escaped = !_unescapedCommands.contains(command);

    // Headers until the empty line.
    final headers = <String, String>{};
    while (true) {
      if (atEol(pos)) {
        pos = skipEol(pos);
        break; // empty line — headers done
      }
      final lineEnd = _findEol(bytes, pos);
      if (lineEnd == null) {
        throw const StompParseException('malformed frame: incomplete frame');
      }
      final line = _decodeUtf8(bytes.sublist(pos, lineEnd.start));
      final colon = line.indexOf(':');
      if (colon == -1) {
        throw const StompParseException(
            'malformed frame: header line without ":"');
      }
      final key = escaped
          ? _unescapeHeader(line.substring(0, colon))
          : line.substring(0, colon);
      final value = escaped
          ? _unescapeHeader(line.substring(colon + 1))
          : line.substring(colon + 1);
      headers.putIfAbsent(key, () => value); // first occurrence wins
      pos = lineEnd.next;
    }

    // Body.
    List<int> bodyBytes;
    final lengthHeader = headers['content-length'];
    if (lengthHeader != null) {
      final length = int.tryParse(lengthHeader);
      if (length == null || length < 0) {
        throw const StompParseException(
            'malformed frame: content-length is not an integer');
      }
      if (pos + length > bytes.length) {
        throw const StompParseException('malformed frame: incomplete frame');
      }
      bodyBytes = bytes.sublist(pos, pos + length);
      pos += length;
      if (pos >= bytes.length || bytes[pos] != 0x00) {
        throw const StompParseException(
            'malformed frame: no NULL terminator after content-length body');
      }
      pos++; // the NUL
    } else {
      final nul = bytes.indexOf(0x00, pos);
      if (nul == -1) {
        throw const StompParseException(
            'malformed frame: missing NULL terminator');
      }
      bodyBytes = bytes.sublist(pos, nul);
      pos = nul + 1;
    }
    final body = _decodeUtf8(bodyBytes);
    if (body.isNotEmpty && !_bodyCommands.contains(command)) {
      throw StompParseException(
          'malformed frame: body not allowed for $command');
    }

    frames.add(StompFrame(command, Map.unmodifiable(headers), body));
  }
  return frames;
}

/// Serializes [frame] to wire text. Headers of `CONNECTED` (and the other
/// connect-family frames) are emitted unescaped, everything else escaped.
String serializeStompFrame(StompFrame frame) {
  final escaped = !_unescapedCommands.contains(frame.command);
  final buffer = StringBuffer()
    ..write(frame.command)
    ..write('\n');
  frame.headers.forEach((key, value) {
    buffer
      ..write(escaped ? _escapeHeader(key) : key)
      ..write(':')
      ..write(escaped ? _escapeHeader(value) : value)
      ..write('\n');
  });
  buffer
    ..write('\n')
    ..write(frame.body)
    ..write('\x00');
  return buffer.toString();
}

/// Decodes a JSON object body for a `@MessageMapping` DTO payload.
Map<String, dynamic> stompJsonMap(String body) {
  final Object? decoded;
  try {
    decoded = jsonDecode(body);
  } on FormatException catch (e) {
    throw StompPayloadException('malformed JSON payload: ${e.message}');
  }
  if (decoded is! Map) {
    throw const StompPayloadException('expected a JSON object payload');
  }
  return decoded.cast<String, dynamic>();
}

/// Encodes a `@MessageMapping` DTO reply body.
String stompJsonBody(Map<String, dynamic> json) => jsonEncode(json);

/// Thrown when a `@MessageMapping` payload cannot be decoded; surfaces as
/// an ERROR frame to the offending client.
class StompPayloadException implements Exception {
  final String message;
  const StompPayloadException(this.message);

  @override
  String toString() => 'StompPayloadException: $message';
}

// ---- helpers ----

/// (start = index of the EOL, next = index after it), or null when no EOL
/// remains.
({int start, int next})? _findEol(List<int> bytes, int from) {
  for (var i = from; i < bytes.length; i++) {
    if (bytes[i] == 0x0A) return (start: i, next: i + 1);
    if (bytes[i] == 0x0D) {
      if (i + 1 < bytes.length && bytes[i + 1] == 0x0A) {
        return (start: i, next: i + 2);
      }
    }
  }
  return null;
}

String _decodeUtf8(List<int> bytes) {
  try {
    return utf8.decode(bytes);
  } on FormatException {
    throw const StompParseException('malformed frame: body is not valid UTF-8');
  }
}

String _unescapeHeader(String value) {
  if (!value.contains(r'\')) return value;
  final buffer = StringBuffer();
  for (var i = 0; i < value.length; i++) {
    final c = value[i];
    if (c != r'\') {
      buffer.write(c);
      continue;
    }
    i++;
    if (i >= value.length) {
      throw const StompParseException(
          r'malformed frame: invalid escape sequence "\" in header');
    }
    switch (value[i]) {
      case 'n':
        buffer.write('\n');
      case 'r':
        buffer.write('\r');
      case 'c':
        buffer.write(':');
      case r'\':
        buffer.write(r'\');
      default:
        throw StompParseException(
            'malformed frame: invalid escape sequence "\\${value[i]}" in '
            'header');
    }
  }
  return buffer.toString();
}

String _escapeHeader(String value) => value
    .replaceAll(r'\', r'\\')
    .replaceAll('\r', r'\r')
    .replaceAll('\n', r'\n')
    .replaceAll(':', r'\c');
