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

import '../codec.dart';
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

  /// Limits stamped onto every [DianaRequest].
  final DianaRequestLimits limits;

  /// Body codecs stamped onto every [DianaRequest].
  final BodyCodecRegistry codecs;

  /// Invoked once per request that matched no route (a 404).
  final void Function()? onUnmatched;

  RelicAdapter({
    this.limits = const DianaRequestLimits(),
    this.codecs = const BodyCodecRegistry(),
    this.onUnmatched,
  }) {
    _app.fallback = (req) {
      onUnmatched?.call();
      return relic.Response.notFound(
        body: relic.Body.fromString(
          '{"error":"not_found","message":"No route matches this path."}',
          mimeType: relic.MimeType.json,
        ),
      );
    };
  }

  void register(HttpMethod method, String path, DianaHandler handler) {
    _app.add(_toRelicMethod(method), path, _wrap(handler));
  }

  /// Mounts a static-file directory under [prefix], using the engine's
  /// hardened static handler (ETag, Range, conditional requests,
  /// path-traversal protection).
  ///
  /// Directory hits (and, with [spaFallback], any miss under the prefix)
  /// serve `[directory]/[indexFile]` when it exists.
  void registerStatic({
    required String directory,
    required String prefix,
    String indexFile = 'index.html',
    bool spaFallback = false,
    int cacheMaxAgeSeconds = 3600,
  }) {
    final index = File('$directory${Platform.pathSeparator}$indexFile');

    FutureOr<relic.Result> serveIndex(relic.Request req) {
      if (!index.existsSync()) return relic.Response.notFound();
      final isRoot = req.remainingPath.segments.isEmpty;
      if (!isRoot && !spaFallback) return relic.Response.notFound();
      final handler = relic.StaticHandler.file(
        index,
        cacheControl: (_, __) =>
            relic.CacheControlHeader(maxAge: cacheMaxAgeSeconds),
      );
      return handler.call(req);
    }

    _app.injectAt(
      prefix,
      relic.StaticHandler.directory(
        Directory(directory),
        defaultHandler: serveIndex,
        cacheControl: (_, __) =>
            relic.CacheControlHeader(maxAge: cacheMaxAgeSeconds),
      ),
    );
  }

  /// Registers a WebSocket endpoint. The handshake is a GET on [path]; a
  /// fresh handler is obtained from [factory] per connection.
  ///
  /// When [handshake] is provided it runs on the handshake request first:
  /// returning [upgradeMarker] (compared by identity) proceeds with the
  /// upgrade — and the request's attributes are copied into the session —
  /// while any other response blocks it.
  void registerWebSocket(
    String path,
    WebSocketHandlerFactory factory, {
    DianaHandler? handshake,
    DianaResponse? upgradeMarker,
  }) {
    _app.add(relic.Method.get, path, (relic.Request req) async {
      final dianaRequest = _toDianaRequest(req);
      if (handshake != null) {
        final result = await handshake(dianaRequest);
        if (!identical(result, upgradeMarker)) {
          return _toRelicResponse(result);
        }
      }
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
        )..attributes.addAll(dianaRequest.attributes);
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
  /// [port] afterwards. Providing [sslCertPath]/[sslKeyPath] serves HTTPS;
  /// [shared] allows several isolates to bind the same address/port.
  Future<void> serve({
    required String host,
    required int port,
    String? sslCertPath,
    String? sslKeyPath,
    String? sslKeyPassword,
    bool shared = false,
  }) async {
    SecurityContext? security;
    if (sslCertPath != null || sslKeyPath != null) {
      if (sslCertPath == null || sslKeyPath == null) {
        throw ArgumentError(
          'Both server.ssl.certPath and server.ssl.keyPath must be set to '
          'enable HTTPS.',
        );
      }
      security = SecurityContext()
        ..useCertificateChain(sslCertPath)
        ..usePrivateKey(sslKeyPath, password: sslKeyPassword);
    }
    _server = await _app.serve(
      address: _parseHost(host),
      port: port,
      securityContext: security,
      shared: shared,
    );
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
      if (response.bodyStream != null) return _hijackStream(response);
      return _toRelicResponse(response);
    };
  }

  /// Streaming responses (SSE) bypass the engine's buffered response path:
  /// dart:io's `HttpResponse` buffers small writes, which would hold events
  /// back indefinitely. Hijacking the socket lets every chunk flush
  /// immediately (manual HTTP/1.1 + chunked framing), and the socket's
  /// close is the disconnect signal that cancels the source stream.
  /// Reason phrases for the manually framed status line (empty for codes
  /// not listed — RFC 7230 allows an empty reason-phrase).
  static const Map<int, String> _reasonPhrases = {
    200: 'OK', 201: 'Created', 202: 'Accepted', 204: 'No Content',
    206: 'Partial Content', 301: 'Moved Permanently', 302: 'Found',
    304: 'Not Modified', 400: 'Bad Request', 401: 'Unauthorized',
    403: 'Forbidden', 404: 'Not Found', 405: 'Method Not Allowed',
    406: 'Not Acceptable', 409: 'Conflict', 413: 'Payload Too Large',
    415: 'Unsupported Media Type', 429: 'Too Many Requests',
    500: 'Internal Server Error', 502: 'Bad Gateway',
    503: 'Service Unavailable',
  };

  /// Strips CR/LF so app-supplied values cannot inject extra header lines
  /// into the manually framed response head.
  static String _headerSafe(String value) =>
      value.replaceAll(RegExp('[\r\n]+'), ' ');

  relic.Hijack _hijackStream(DianaResponse response) {
    return relic.Hijack((channel) {
      final sink = channel.sink;
      final head = StringBuffer()
        ..write('HTTP/1.1 ${response.statusCode} '
            '${_reasonPhrases[response.statusCode] ?? ''}\r\n')
        ..write('content-type: '
            '${_headerSafe(response.mimeType ?? 'application/octet-stream')}\r\n')
        ..write('transfer-encoding: chunked\r\n')
        ..write('connection: close\r\n');
      for (final entry in response.headers.entries) {
        head.write(
            '${_headerSafe(entry.key)}: ${_headerSafe(entry.value)}\r\n');
      }
      head.write('\r\n');
      sink.add(head.toString().codeUnits);

      var finished = false;
      late final StreamSubscription<List<int>> subscription;

      void finish({bool trailer = false}) {
        if (finished) return;
        finished = true;
        if (trailer) sink.add('0\r\n\r\n'.codeUnits);
        sink.close();
      }

      subscription = response.bodyStream!.listen(
        (chunk) {
          // A zero-length chunk would frame as `0\r\n\r\n` — the HTTP/1.1
          // terminator — truncating the stream mid-body.
          if (chunk.isEmpty) return;
          sink.add('${chunk.length.toRadixString(16)}\r\n'.codeUnits);
          sink.add(chunk);
          sink.add('\r\n'.codeUnits);
        },
        onError: (Object _) {
          unawaited(subscription.cancel());
          finish();
        },
        onDone: () => finish(trailer: true),
      );

      // The read side closing (or erroring) means the client went away:
      // cancel the handler's stream so producers stop.
      channel.stream.listen(
        (_) {},
        onDone: () {
          unawaited(subscription.cancel());
          finish();
        },
        onError: (Object _) {
          unawaited(subscription.cancel());
          finish();
        },
      );
    });
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
        bytesReader: req.read,
        limits: limits,
        codecs: codecs,
      );

  relic.Response _toRelicResponse(DianaResponse response) {
    final mime = response.mimeType;
    relic.Body body;
    if (response.bodyStream != null) {
      body = relic.Body.fromDataStream(
        response.bodyStream!
            .map((chunk) => chunk is Uint8List ? chunk : Uint8List.fromList(chunk)),
        mimeType: _parseMime(mime ?? 'application/octet-stream'),
      );
    } else if (response.bodyText != null) {
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
