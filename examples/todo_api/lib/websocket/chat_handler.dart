import 'package:diana/diana.dart';

/// Room-based chat over WebSockets: connect to `/ws/chat/:room`, every text
/// frame is broadcast to the room. A shared (singleton) handler keeps the
/// room registry; per-connection identity lives in the session.
@WebSocketController('/ws/chat/:room')
class ChatHandler extends BaseWebSocketHandler {
  final Map<String, Set<WebSocketSession>> _rooms = {};

  String _roomOf(WebSocketSession session) =>
      session.pathParameters['room'] ?? 'lobby';

  @override
  void onOpen(WebSocketSession session) {
    final room = _roomOf(session);
    (_rooms[room] ??= {}).add(session);
    session.sendText('joined $room');
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
