/// Runtime helpers targeted by generated route adapters.
///
/// The generated code stays one line per parameter; the conversion semantics
/// (and their error messages) live here, unit-tested once.
library;

import 'dart:convert';

import 'exceptions.dart';
import 'http/request.dart';

Type _typeOf<T>() => T;

/// Binds a path parameter. Path parameters always exist when the route
/// matched, so [T] should be non-nullable.
T bindPathParam<T>(DianaRequest request, String name) => _convert<T>(
      request.pathParameters[name],
      kind: 'Path parameter',
      name: name,
    );

/// Binds a query parameter. Nullable [T] makes it optional; [defaultValue]
/// (as written in the query string) is used when absent.
T bindQueryParam<T>(DianaRequest request, String name,
        {String? defaultValue}) =>
    _convert<T>(
      request.queryParameters[name] ?? defaultValue,
      kind: 'Query parameter',
      name: name,
    );

/// Binds a request header (case-insensitive). Nullable [T] makes it
/// optional.
T bindHeader<T>(DianaRequest request, String name) => _convert<T>(
      request.header(name),
      kind: 'Header',
      name: name,
    );

T _convert<T>(String? raw, {required String kind, required String name}) {
  if (raw == null) {
    if (null is T) return null as T;
    throw BadRequestException("Missing required $kind '$name'.");
  }
  final Object? parsed;
  if (T == String || T == _typeOf<String?>()) {
    parsed = raw;
  } else if (T == int || T == _typeOf<int?>()) {
    parsed = int.tryParse(raw);
  } else if (T == double || T == _typeOf<double?>()) {
    parsed = double.tryParse(raw);
  } else if (T == num || T == _typeOf<num?>()) {
    parsed = num.tryParse(raw);
  } else if (T == bool || T == _typeOf<bool?>()) {
    parsed = switch (raw.toLowerCase()) {
      'true' || '1' => true,
      'false' || '0' => false,
      _ => null,
    };
  } else {
    throw StateError('Unsupported bindable type $T.');
  }
  if (parsed == null) {
    throw BadRequestException(
      "$kind '$name' must be ${_baseName<T>()}, got '$raw'.",
    );
  }
  return parsed as T;
}

String _baseName<T>() => T.toString().replaceFirst('?', '');

/// Decodes the request body as a JSON object.
///
/// Throws [UnsupportedMediaTypeException] (415) when the content type is not
/// JSON, and [BadRequestException] (400) for empty, malformed or non-object
/// bodies.
Future<Map<String, dynamic>> decodeJsonMapBody(DianaRequest request) async {
  final decoded = await _decodeJsonBody(request);
  if (decoded is! Map) {
    throw const BadRequestException('Expected a JSON object body.');
  }
  return decoded.cast<String, dynamic>();
}

/// Decodes the request body as a JSON array.
Future<List<dynamic>> decodeJsonListBody(DianaRequest request) async {
  final decoded = await _decodeJsonBody(request);
  if (decoded is! List) {
    throw const BadRequestException('Expected a JSON array body.');
  }
  return decoded;
}

/// Runs a DTO decode ([decode] wraps `fromJson`/generated codecs) and turns
/// shape mismatches (`TypeError`, `FormatException`, enum `ArgumentError`)
/// into 400s instead of 500s.
T decodeDto<T>(T Function() decode) {
  try {
    return decode();
  } on HttpException {
    rethrow;
  } catch (e) {
    if (e is TypeError || e is FormatException || e is ArgumentError) {
      throw BadRequestException(
          'JSON body does not match the expected shape: $e');
    }
    rethrow;
  }
}

Future<Object?> _decodeJsonBody(DianaRequest request) async {
  final contentType = request.header('content-type');
  if (contentType != null) {
    final mime = contentType.split(';').first.trim().toLowerCase();
    final isJson = mime == 'application/json' || mime.endsWith('+json');
    if (!isJson) {
      throw UnsupportedMediaTypeException(
        "Expected content type 'application/json', got '$mime'.",
      );
    }
  }
  final text = await request.readBodyAsString();
  if (text.isEmpty) {
    throw const BadRequestException('Missing JSON body.');
  }
  try {
    return jsonDecode(text);
  } on FormatException {
    throw const BadRequestException('Malformed JSON body.');
  }
}
