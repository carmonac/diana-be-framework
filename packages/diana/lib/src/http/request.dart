import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../codec.dart';
import 'method.dart';

/// Per-request limits, configured on the server and consulted by binding
/// helpers (generated code never touches configuration).
class DianaRequestLimits {
  /// Maximum accepted multipart body size in bytes.
  final int multipartMaxBytes;

  /// SSE keep-alive comment interval in seconds (0 disables).
  final int sseHeartbeatSeconds;

  const DianaRequestLimits({
    this.multipartMaxBytes = 10 * 1024 * 1024,
    this.sseHeartbeatSeconds = 15,
  });
}

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

  /// Limits enforced by binding helpers (multipart size, ...).
  final DianaRequestLimits limits;

  /// Body codecs available to this request (JSON always included).
  final BodyCodecRegistry codecs;

  final Map<String, List<String>> _headers;
  final Future<String> Function() _bodyReader;
  final Stream<Uint8List> Function()? _bytesReader;
  Future<String>? _cachedBody;

  DianaRequest({
    required this.method,
    required this.uri,
    this.pathParameters = const {},
    Map<String, List<String>> headers = const {},
    Future<String> Function()? bodyReader,
    Stream<Uint8List> Function()? bytesReader,
    this.limits = const DianaRequestLimits(),
    this.codecs = const BodyCodecRegistry(),
  })  : _headers = {
          for (final e in headers.entries) e.key.toLowerCase(): e.value,
        },
        _bodyReader = bodyReader ?? (() async => ''),
        _bytesReader = bytesReader;

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

  /// Reads the request body as a byte stream (single subscription — used by
  /// multipart decoding; prefer [readBodyAsString] for text).
  Stream<Uint8List> readBodyAsBytes() {
    final reader = _bytesReader;
    if (reader != null) return reader();
    // Fall back to the string reader (tests constructing DianaRequest
    // directly usually provide only bodyReader).
    return Stream.fromFuture(
      readBodyAsString().then((s) => Uint8List.fromList(utf8.encode(s))),
    );
  }
}
