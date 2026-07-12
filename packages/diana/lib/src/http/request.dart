import 'dart:async';

import 'method.dart';

/// Diana's view of an incoming HTTP request.
///
/// Wraps the underlying HTTP engine's request; handlers and middleware only
/// ever see this type. The raw body can be read repeatedly — the first read
/// is cached.
class DianaRequest {
  final HttpMethod method;

  /// The requested URI (path + query).
  final Uri uri;

  /// Path parameters extracted by the router, keyed by name (`:id` → `id`).
  final Map<String, String> pathParameters;

  /// Request-scoped attribute bag for middleware → handler communication.
  final Map<String, Object?> attributes = {};

  final Map<String, List<String>> _headers;
  final Future<String> Function() _bodyReader;
  Future<String>? _cachedBody;

  DianaRequest({
    required this.method,
    required this.uri,
    this.pathParameters = const {},
    Map<String, List<String>> headers = const {},
    Future<String> Function()? bodyReader,
  })  : _headers = {
          for (final e in headers.entries) e.key.toLowerCase(): e.value,
        },
        _bodyReader = bodyReader ?? (() async => '');

  /// Path component of the request, always starting with `/`.
  String get path => uri.path.isEmpty ? '/' : uri.path;

  /// Single-valued query parameters.
  Map<String, String> get queryParameters => uri.queryParameters;

  /// Multi-valued query parameters.
  Map<String, List<String>> get queryParametersAll => uri.queryParametersAll;

  /// First value of [name] (case-insensitive), or `null` when absent.
  String? header(String name) {
    final values = _headers[name.toLowerCase()];
    return (values == null || values.isEmpty) ? null : values.first;
  }

  /// All values of [name] (case-insensitive).
  List<String> headerAll(String name) =>
      _headers[name.toLowerCase()] ?? const [];

  /// Reads the request body as a string. Subsequent calls return the cached
  /// result, so middleware and parameter binding can both read it.
  Future<String> readBodyAsString() => _cachedBody ??= _bodyReader();
}
