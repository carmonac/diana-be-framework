import 'package:diana/diana.dart';
import 'package:diana_auth/diana_auth.dart';

import '../auth/app_auth.dart';

/// Room-based chat over WebSockets: connect to `/ws/chat/:room`, every text
/// frame is broadcast to the room.
///
/// Authentication runs on the **handshake**: `@UseMiddleware([AppAuth])`
/// authenticates the request (global middleware do not run on handshakes),
/// and `@Secured()` blocks anonymous upgrades with a 401. The authenticated
/// principal is copied into `session.attributes`.
@WebSocketController('/ws/chat/:room')
@UseMiddleware([AppAuth])
@Secured()
class ChatHandler extends BaseWebSocketHandler {
  final Map<String, Set<WebSocketSession>> _rooms = {};

  String _roomOf(WebSocketSession session) =>
      session.pathParameters['room'] ?? 'lobby';

  @override
  void onOpen(WebSocketSession session) {
    final room = _roomOf(session);
    (_rooms[room] ??= {}).add(session);
    final principal = session.attributes[principalAttributeKey];
    final user = principal is AuthPrincipal ? principal.name : null;
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
