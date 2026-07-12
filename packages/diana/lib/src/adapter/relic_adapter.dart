/// The single boundary between Diana and the relic HTTP engine.
///
/// Nothing outside this file may import `package:relic`; a test enforces it.
/// If relic's API changes, this file is the only one that follows.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:relic/relic.dart' as relic;
import 'package:web_socket/web_socket.dart' as ws_events;

import '../http/method.dart';
import '../http/request.dart';
import '../http/response.dart';
import '../middleware.dart';
import '../websocket.dart';

/// Mounts Diana handlers onto a relic router and manages the server
/// lifecycle. Relic contributes routing (trie router, path parameters) and
/// the HTTP server; Diana owns the pipeline on top.
class RelicAdapter {
  final relic.RelicApp _app = relic.RelicApp();
  relic.RelicServer? _server;

  RelicAdapter() {
    _app.fallback = (req) => relic.Response.notFound(
          body: relic.Body.fromString(
            '{"error":"not_found","message":"No route matches this path."}',
            mimeType: relic.MimeType.json,
          ),
        );
  }

  void register(HttpMethod method, String path, DianaHandler handler) {
    _app.add(_toRelicMethod(method), path, _wrap(handler));
  }

  /// Registers a WebSocket endpoint. The handshake is a GET on [path]; a
  /// fresh handler is obtained from [factory] per connection.
  void registerWebSocket(String path, WebSocketHandlerFactory factory) {
    _app.add(relic.Method.get, path, (relic.Request req) async {
      final handler = await factory();
      final uri = req.url;
      final pathParameters = {
        for (final e in req.rawPathParameters.entries)
          _symbolName(e.key): e.value,
      };
      return relic.WebSocketUpgrade((socket) {
        final session = _RelicWebSocketSession(
          id: 'ws-${_nextSessionId++}',
          uri: uri,
          pathParameters: pathParameters,
          socket: socket,
        );
        unawaited(_runWebSocket(handler, session, socket));
      });
    });
  }

  static int _nextSessionId = 1;

  static Future<void> _runWebSocket(
    WebSocketHandler handler,
    _RelicWebSocketSession session,
    relic.RelicWebSocket socket,
  ) async {
    int? closeCode;
    String? closeReason;
    try {
      await handler.onOpen(session);
      await for (final event in socket.events) {
        switch (event) {
          case ws_events.TextDataReceived(:final text):
            await handler.onMessage(session, TextMessage(text));
          case ws_events.BinaryDataReceived(:final data):
            await handler.onMessage(session, BinaryMessage(data));
          case ws_events.CloseReceived(:final code, :final reason):
            closeCode = code;
            closeReason = reason;
        }
      }
    } catch (error, stackTrace) {
      try {
        await handler.onError(session, error, stackTrace);
      } finally {
        await socket.tryClose(1011);
      }
    } finally {
      await handler.onClose(session, closeCode, closeReason);
    }
  }

  /// Binds the server. A [port] of 0 lets the OS pick one; read it back from
  /// [port] afterwards.
  Future<void> serve({required String host, required int port}) async {
    _server = await _app.serve(address: _parseHost(host), port: port);
  }

  /// The bound port, or `null` before [serve].
  int? get port => _server?.port;

  Future<void> close() async {
    await _app.close();
    _server = null;
  }

  relic.Handler _wrap(DianaHandler handler) {
    return (relic.Request req) async {
      final response = await handler(_toDianaRequest(req));
      return _toRelicResponse(response);
    };
  }

  DianaRequest _toDianaRequest(relic.Request req) => DianaRequest(
        method: HttpMethod.parse(req.method.name),
        uri: req.url,
        pathParameters: {
          for (final e in req.rawPathParameters.entries)
            _symbolName(e.key): e.value,
        },
        headers: {
          for (final e in req.headers.entries) e.key: e.value.toList(),
        },
        bodyReader: req.readAsString,
      );

  relic.Response _toRelicResponse(DianaResponse response) {
    final mime = response.mimeType;
    relic.Body body;
    if (response.bodyText != null) {
      body = relic.Body.fromString(
        response.bodyText!,
        mimeType: _parseMime(mime ?? 'text/plain'),
      );
    } else if (response.bodyBytes != null) {
      body = relic.Body.fromData(
        Uint8List.fromList(response.bodyBytes!),
        mimeType: _parseMime(mime ?? 'application/octet-stream'),
      );
    } else {
      body = relic.Body.empty();
    }
    return relic.Response(
      response.statusCode,
      body: body,
      headers: response.headers.isEmpty
          ? null
          : relic.Headers.fromMap({
              for (final e in response.headers.entries) e.key: [e.value],
            }),
    );
  }

  static relic.Method _toRelicMethod(HttpMethod method) =>
      relic.Method.values.firstWhere((m) => m.name == method.name);

  static relic.MimeType _parseMime(String value) {
    final parts = value.split('/');
    return parts.length == 2
        ? relic.MimeType(parts[0], parts[1])
        : relic.MimeType('application', 'octet-stream');
  }

  static String _symbolName(Symbol symbol) {
    final raw = symbol.toString(); // Symbol("name")
    return raw.substring(8, raw.length - 2);
  }

  static InternetAddress _parseHost(String host) => switch (host) {
        '0.0.0.0' || 'any' => InternetAddress.anyIPv4,
        'localhost' || '127.0.0.1' => InternetAddress.loopbackIPv4,
        '::' => InternetAddress.anyIPv6,
        '::1' => InternetAddress.loopbackIPv6,
        _ => InternetAddress(host),
      };
}

class _RelicWebSocketSession implements WebSocketSession {
  @override
  final String id;

  @override
  final Uri uri;

  @override
  final Map<String, String> pathParameters;

  @override
  final Map<String, Object?> attributes = {};

  final relic.RelicWebSocket _socket;

  _RelicWebSocketSession({
    required this.id,
    required this.uri,
    required this.pathParameters,
    required relic.RelicWebSocket socket,
  }) : _socket = socket;

  @override
  Map<String, String> get queryParameters => uri.queryParameters;

  @override
  bool get isOpen => !_socket.isClosed;

  @override
  bool sendText(String text) => _socket.trySendText(text);

  @override
  bool sendBytes(Uint8List data) => _socket.trySendBytes(data);

  @override
  Future<void> close([int? code, String? reason]) async {
    await _socket.tryClose(code, reason);
  }
}
