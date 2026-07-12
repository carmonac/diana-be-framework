/// WebSocket support, modeled after Spring's `WebSocketHandler` /
/// `WebSocketSession` pair.
///
/// Implement [WebSocketHandler] (or extend [BaseWebSocketHandler] to
/// override only what you need), annotate the class with
/// `@WebSocketController('/ws/path')`, and Diana wires the upgrade, the
/// lifecycle callbacks and dependency injection.
library;

import 'dart:async';
import 'dart:typed_data';

/// A message received from the peer.
sealed class WebSocketMessage {}

/// A text frame.
final class TextMessage extends WebSocketMessage {
  final String text;
  TextMessage(this.text);
}

/// A binary frame.
final class BinaryMessage extends WebSocketMessage {
  final Uint8List data;
  BinaryMessage(this.data);
}

/// One live WebSocket connection (Spring: `WebSocketSession`).
///
/// Sessions are handed to every [WebSocketHandler] callback. Sending on a
/// closed session is safe: `sendText`/`sendBytes` return `false` instead of
/// throwing.
abstract interface class WebSocketSession {
  /// Unique id of this connection (per server run).
  String get id;

  /// The URI the client connected to (path + query).
  Uri get uri;

  /// Path parameters extracted from the route (`/ws/rooms/:room`).
  Map<String, String> get pathParameters;

  /// Single-valued query parameters of the handshake request.
  Map<String, String> get queryParameters;

  /// Per-connection attribute bag, alive for the whole session.
  Map<String, Object?> get attributes;

  /// Whether the connection is still open. May briefly report `true` after
  /// an undetected peer disconnect.
  bool get isOpen;

  /// Sends a text frame. Returns `false` when the connection is known to be
  /// closed.
  bool sendText(String text);

  /// Sends a binary frame. Returns `false` when the connection is known to
  /// be closed.
  bool sendBytes(Uint8List data);

  /// Closes the connection. [code] must be 1000 or in 3000–4999; [reason]
  /// at most 123 UTF-8 bytes. Closing an already-closed session is a no-op.
  Future<void> close([int? code, String? reason]);
}

/// Lifecycle of a WebSocket endpoint (Spring: `WebSocketHandler`).
///
/// Annotate implementations with `@WebSocketController('/path')`:
///
/// ```dart
/// @WebSocketController('/ws/echo')
/// class EchoHandler extends BaseWebSocketHandler {
///   @override
///   void onMessage(WebSocketSession session, WebSocketMessage message) {
///     if (message is TextMessage) session.sendText(message.text);
///   }
/// }
/// ```
abstract interface class WebSocketHandler {
  /// The connection was established.
  FutureOr<void> onOpen(WebSocketSession session);

  /// A text or binary frame arrived.
  FutureOr<void> onMessage(WebSocketSession session, WebSocketMessage message);

  /// A transport error occurred. The connection is closed afterwards.
  FutureOr<void> onError(
    WebSocketSession session,
    Object error,
    StackTrace stackTrace,
  );

  /// The connection closed (by either side). [code]/[reason] are the close
  /// frame's, when available.
  FutureOr<void> onClose(WebSocketSession session, int? code, String? reason);
}

/// Convenience base class with no-op implementations of every callback.
abstract class BaseWebSocketHandler implements WebSocketHandler {
  const BaseWebSocketHandler();

  @override
  FutureOr<void> onOpen(WebSocketSession session) {}

  @override
  FutureOr<void> onMessage(
      WebSocketSession session, WebSocketMessage message) {}

  @override
  FutureOr<void> onError(
      WebSocketSession session, Object error, StackTrace stackTrace) {}

  @override
  FutureOr<void> onClose(WebSocketSession session, int? code, String? reason) {}
}

/// Produces the handler for a new connection. Generated code passes
/// `() => ctx.handler` for shared (singleton) handlers and
/// `() => ctx.createHandler()` for per-connection (transient) handlers.
typedef WebSocketHandlerFactory = FutureOr<WebSocketHandler> Function();
