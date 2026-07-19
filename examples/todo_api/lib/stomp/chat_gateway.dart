import 'package:diana/diana.dart';
import 'package:diana_auth/diana_auth.dart';

import '../auth/app_auth.dart';

part 'chat_gateway.diana.dart';

/// A STOMP 1.2 endpoint at `/stomp`. Authentication runs on the handshake
/// (`@UseMiddleware([AppAuth])` + `@Secured()`), exactly like the plain
/// WebSocket controller; the principal is available to `@MessageMapping`
/// handlers via `StompMessage.principal`.
@WebSocketController('/stomp')
@UseMiddleware([AppAuth])
@Secured()
class ChatGateway extends StompEndpoint {
  ChatGateway(super.broker);
}

/// A message a client SENDs to `/app/chat`.
@Json()
class ChatIn {
  final String text;
  const ChatIn(this.text);
}

/// A message published to `/topic/chat`.
@Json()
class ChatOut {
  final String from;
  final String text;
  const ChatOut({required this.from, required this.text});
}

/// Handles STOMP messages. `@MessageMapping('/chat')` receives client SENDs
/// to `/app/chat`; the returned `ChatOut` is published to `/topic/chat`.
@Service()
class ChatMessaging {
  @MessageMapping('/chat')
  @SendTo('/topic/chat')
  ChatOut chat(ChatIn payload, StompMessage message) {
    final principal = message.principal;
    final from = principal is AuthPrincipal ? principal.name : 'anonymous';
    return ChatOut(from: from, text: payload.text);
  }
}
