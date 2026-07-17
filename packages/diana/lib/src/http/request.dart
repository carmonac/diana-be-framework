import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../codec.dart';
import '../exceptions.dart';
import 'method.dart';

/// Per-request limits, configured on the server and consulted by binding
/// helpers (generated code never touches configuration).
class DianaRequestLimits {
  /// Maximum accepted request body size in bytes for non-multipart bodies
  /// (JSON, urlencoded forms, raw `@Body String`, custom codecs). Zero or
  /// negative disables the cap.
  final int maxBodyBytes;

  /// Maximum accepted multipart body size in bytes.
  final int multipartMaxBytes;

  /// SSE keep-alive comment interval in seconds (0 disables).
  final int sseHeartbeatSeconds;

  const DianaRequestLimits({
    this.maxBodyBytes = 10 * 1024 * 1024,
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

  /// Limits enforced by binding helpers (body size, multipart size, ...).
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
  ///
  /// A body larger than the applicable byte limit (see [_bodyLimit]) is a
  /// 413 [PayloadTooLargeException], enforced while streaming — an
  /// oversized body is never fully buffered.
  Future<String> readBodyAsString() => _cachedBody ??= _readBodyAsString();

  /// Reads the request body as a byte stream (single subscription — used by
  /// multipart decoding; prefer [readBodyAsString] for text). Enforces the
  /// same size limit as [readBodyAsString].
  Stream<Uint8List> readBodyAsBytes() {
    final reader = _bytesReader;
    if (reader != null) return _limited(reader);
    // Fall back to the string reader (tests constructing DianaRequest
    // directly usually provide only bodyReader); it enforces the limit.
    return Stream.fromFuture(
      readBodyAsString().then((s) => Uint8List.fromList(utf8.encode(s))),
    );
  }

  Future<String> _readBodyAsString() async {
    final reader = _bytesReader;
    if (reader == null) {
      // Direct construction with only a string reader: the body is already
      // buffered, so the check runs after the fact. UTF-16 code units never
      // exceed the UTF-8 byte count, so this never rejects an in-limit body.
      _checkDeclaredLength();
      final body = await _bodyReader();
      final limit = _bodyLimit;
      if (limit != null && body.length > limit) throw _tooLarge(limit);
      return body;
    }
    final builder = BytesBuilder(copy: false);
    await for (final chunk in _limited(reader)) {
      builder.add(chunk);
    }
    return _charset().decode(builder.takeBytes());
  }

  /// Wraps a body byte stream with size enforcement: rejects a declared
  /// oversize `Content-Length` before opening the source, and counts
  /// streamed bytes so chunked bodies without one are bounded too.
  Stream<Uint8List> _limited(Stream<Uint8List> Function() source) async* {
    final limit = _bodyLimit;
    if (limit == null) {
      yield* source();
      return;
    }
    _checkDeclaredLength();
    var total = 0;
    await for (final chunk in source()) {
      total += chunk.length;
      if (total > limit) throw _tooLarge(limit);
      yield chunk;
    }
  }

  /// The byte cap for this request's body: [DianaRequestLimits.multipartMaxBytes]
  /// for `multipart/form-data`, [DianaRequestLimits.maxBodyBytes] otherwise;
  /// `null` when the applicable limit is disabled (zero or negative).
  int? get _bodyLimit {
    final mime =
        (header('content-type') ?? '').split(';').first.trim().toLowerCase();
    final limit = mime == 'multipart/form-data'
        ? limits.multipartMaxBytes
        : limits.maxBodyBytes;
    return limit > 0 ? limit : null;
  }

  void _checkDeclaredLength() {
    final limit = _bodyLimit;
    if (limit == null) return;
    final declared = int.tryParse(header('content-length') ?? '');
    if (declared != null && declared > limit) throw _tooLarge(limit);
  }

  PayloadTooLargeException _tooLarge(int limit) => PayloadTooLargeException(
      'Request body exceeds the configured limit of $limit bytes.');

  /// The charset declared in `Content-Type`, defaulting to UTF-8.
  Encoding _charset() {
    final contentType = header('content-type') ?? '';
    for (final param in contentType.split(';').skip(1)) {
      final trimmed = param.trim().toLowerCase();
      if (trimmed.startsWith('charset=')) {
        final name = trimmed.substring('charset='.length).replaceAll('"', '');
        return Encoding.getByName(name) ?? utf8;
      }
    }
    return utf8;
  }
}
