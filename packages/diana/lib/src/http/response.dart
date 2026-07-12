import 'dart:async';
import 'dart:convert';

/// Diana's HTTP response.
///
/// Route methods usually return DTOs and let the generated adapter build the
/// response; return a [DianaResponse] directly for full control.
class DianaResponse {
  final int statusCode;

  /// Additional response headers. Content type is carried by [mimeType].
  final Map<String, String> headers;

  /// Response body as text, or `null` for [bodyBytes]/empty responses.
  final String? bodyText;

  /// Response body as raw bytes, or `null`.
  final List<int>? bodyBytes;

  /// Streaming response body (chunked), or `null`. Used by Server-Sent
  /// Events and other long-lived responses.
  final Stream<List<int>>? bodyStream;

  /// MIME type of the body, e.g. `application/json`.
  final String? mimeType;

  const DianaResponse({
    this.statusCode = 200,
    this.headers = const {},
    this.bodyText,
    this.bodyBytes,
    this.bodyStream,
    this.mimeType,
  });

  /// Streaming (chunked) response.
  const DianaResponse.stream(
    Stream<List<int>> body, {
    int statusCode = 200,
    String mimeType = 'application/octet-stream',
    Map<String, String> headers = const {},
  }) : this(
          statusCode: statusCode,
          headers: headers,
          bodyStream: body,
          mimeType: mimeType,
        );

  /// JSON response: [data] is encoded with `jsonEncode`.
  DianaResponse.json(
    Object? data, {
    int statusCode = 200,
    Map<String, String> headers = const {},
  }) : this(
          statusCode: statusCode,
          headers: headers,
          bodyText: jsonEncode(data),
          mimeType: 'application/json',
        );

  /// Plain-text response.
  const DianaResponse.text(
    String body, {
    int statusCode = 200,
    Map<String, String> headers = const {},
  }) : this(
          statusCode: statusCode,
          headers: headers,
          bodyText: body,
          mimeType: 'text/plain',
        );

  /// 204 No Content.
  const DianaResponse.noContent({Map<String, String> headers = const {}})
      : this(statusCode: 204, headers: headers);

  /// Binary response.
  const DianaResponse.bytes(
    List<int> body, {
    int statusCode = 200,
    String mimeType = 'application/octet-stream',
    Map<String, String> headers = const {},
  }) : this(
          statusCode: statusCode,
          headers: headers,
          bodyBytes: body,
          mimeType: mimeType,
        );

  DianaResponse copyWith({
    int? statusCode,
    Map<String, String>? headers,
  }) =>
      DianaResponse(
        statusCode: statusCode ?? this.statusCode,
        headers: headers ?? this.headers,
        bodyText: bodyText,
        bodyBytes: bodyBytes,
        bodyStream: bodyStream,
        mimeType: mimeType,
      );
}
