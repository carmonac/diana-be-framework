/// Pluggable body formats (Spring: `HttpMessageConverter`).
///
/// A [BodyCodec] translates between a wire format and the intermediate
/// representation Diana's DTO codecs already consume (`Map`/`List`/scalars).
/// Codecs are ordinary injectables discovered through the DI graph; JSON is
/// built in. Routes opt into other formats with `@Consumes`/`@Produces`.
library;

import 'dart:convert';

import 'content.dart';
import 'exceptions.dart';
import 'http/request.dart';
import 'http/response.dart';

/// Translates one wire format to/from `Map<String, dynamic>`/`List`/scalars.
///
/// Implementations are registered by annotating an injectable class
/// (`@Component()`) that implements/extends this interface; the generated
/// server discovers them through the DI graph.
abstract interface class BodyCodec {
  /// MIME types this codec handles. The first entry is the canonical type
  /// used on responses.
  List<String> get mimeTypes;

  /// Decodes a request body. Returns a `Map<String, dynamic>`, `List` or
  /// scalar. Throws [FormatException] on malformed input.
  Object? decode(String body);

  /// Encodes a `Map`/`List`/scalar payload into the wire format.
  String encode(Object? value);
}

/// The built-in JSON codec (also accepts `…+json` content types).
class JsonBodyCodec implements BodyCodec {
  const JsonBodyCodec();

  @override
  List<String> get mimeTypes => const ['application/json'];

  @override
  Object? decode(String body) => jsonDecode(body);

  @override
  String encode(Object? value) => jsonEncode(value);
}

/// Looks up codecs by MIME type. Always contains [JsonBodyCodec].
class BodyCodecRegistry {
  final List<BodyCodec> _codecs;

  const BodyCodecRegistry([List<BodyCodec> extra = const []])
      : _codecs = extra;

  /// The codec for [mime] (parameters like `; charset=` are ignored), or
  /// `null` when no codec handles it.
  BodyCodec? forMime(String mime) {
    final normalized = mime.split(';').first.trim().toLowerCase();
    for (final codec in _codecs) {
      if (codec.mimeTypes.contains(normalized)) return codec;
    }
    if (normalized == 'application/json' || normalized.endsWith('+json')) {
      return const JsonBodyCodec();
    }
    return null;
  }
}

/// Decodes the request body as an object using the codec matching its
/// content type, restricted to [consumes].
///
/// 415 when the content type isn't in [consumes] or has no registered
/// codec; 400 for malformed input or a non-object payload.
Future<Map<String, dynamic>> decodeMapBody(
  DianaRequest request, {
  required List<String> consumes,
}) async {
  final decoded = await _decodeWithCodec(request, consumes);
  if (decoded is! Map) {
    throw const BadRequestException('Expected an object body.');
  }
  return decoded.cast<String, dynamic>();
}

/// Decodes the request body as an array using the codec matching its
/// content type, restricted to [consumes].
Future<List<dynamic>> decodeListBody(
  DianaRequest request, {
  required List<String> consumes,
}) async {
  final decoded = await _decodeWithCodec(request, consumes);
  if (decoded is! List) {
    throw const BadRequestException('Expected an array body.');
  }
  return decoded;
}

Future<Object?> _decodeWithCodec(
  DianaRequest request,
  List<String> consumes,
) async {
  final contentType = request.header('content-type') ?? consumes.first;
  final mime = contentType.split(';').first.trim().toLowerCase();
  final accepted = consumes
      .map((c) => c.trim().toLowerCase())
      .any((c) => c == mime || (c == 'application/json' && mime.endsWith('+json')));
  if (!accepted) {
    throw UnsupportedMediaTypeException(
      "Expected one of ${consumes.join(', ')}, got '$mime'.",
    );
  }
  final codec = request.codecs.forMime(mime);
  if (codec == null) {
    throw UnsupportedMediaTypeException(
      "No body codec registered for '$mime'. Register an injectable "
      'implementing BodyCodec.',
    );
  }
  final text = await request.readBodyAsString();
  if (text.isEmpty) {
    throw const BadRequestException('Missing request body.');
  }
  try {
    return codec.decode(text);
  } on FormatException {
    throw BadRequestException('Malformed $mime body.');
  }
}

/// Encodes [payload] with the first codec of [produces] the request's
/// `Accept` header allows (server preference order). 406 when nothing in
/// [produces] is acceptable, 500-shaped error when a produced type has no
/// codec (a build-time-declared mime should always have one at runtime).
DianaResponse negotiatedResponse(
  DianaRequest request,
  Object? payload, {
  required List<String> produces,
  int statusCode = 200,
}) {
  final accept = request.header('accept');
  String? chosen;
  for (final mime in produces) {
    if (accept == null || acceptsMime(accept, mime)) {
      chosen = mime;
      break;
    }
  }
  if (chosen == null) {
    throw NotAcceptableException(
      "None of ${produces.join(', ')} is acceptable for '$accept'.",
    );
  }
  final codec = request.codecs.forMime(chosen);
  if (codec == null) {
    throw StateError(
      "No body codec registered for produced type '$chosen'.",
    );
  }
  return DianaResponse(
    statusCode: statusCode,
    bodyText: codec.encode(payload),
    mimeType: chosen,
  );
}
