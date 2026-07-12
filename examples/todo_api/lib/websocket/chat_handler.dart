import 'package:diana/diana.dart';

import '../middleware/api_key_middleware.dart';

/// Room-based chat over WebSockets: connect to `/ws/chat/:room`, every text
/// frame is broadcast to the room.
///
/// `@UseMiddleware` runs on the **handshake**: a missing API key blocks the
/// upgrade with the middleware's 401, and attributes the middleware sets on
/// the request are visible in `session.attributes`.
@WebSocketController('/ws/chat/:room')
@UseMiddleware([ApiKeyMiddleware])
class ChatHandler extends BaseWebSocketHandler {
  final Map<String, Set<WebSocketSession>> _rooms = {};

  String _roomOf(WebSocketSession session) =>
      session.pathParameters['room'] ?? 'lobby';

  @override
  void onOpen(WebSocketSession session) {
    final room = _roomOf(session);
    (_rooms[room] ??= {}).add(session);
    final user = session.attributes['user'];
    session.sendText('joined $room${user == null ? '' : ' as $user'}');
  }

  @override
  void onMessage(WebSocketSession session, WebSocketMessage message) {
    if (message is! TextMessage) return;
    final room = _roomOf(session);
    for (final peer in _rooms[room] ?? const <WebSocketSession>{}) {
      peer.sendText('[$room] ${message.text}');
    }
  }

  @override
  void onClose(WebSocketSession session, int? code, String? reason) {
    _rooms[_roomOf(session)]?.remove(session);
  }
}
