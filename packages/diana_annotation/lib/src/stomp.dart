import 'package:meta/meta_meta.dart';

/// Handles STOMP messages sent to a destination under the app prefix
/// (`stomp.appPrefix`, default `/app`) — Spring's `@MessageMapping`.
///
/// On a singleton provider; the method takes the payload (a `String` for the
/// raw body, or an `@Json` class decoded from JSON) and, optionally, a
/// second `StompMessage` parameter for headers/session/principal. A non-void
/// return value is published to the [SendTo] destination.
///
/// ```dart
/// @MessageMapping('/chat')     // client SENDs to /app/chat
/// @SendTo('/topic/chat')
/// Future<ChatOut> handle(ChatIn payload) async { ... }
/// ```
@Target({TargetKind.method})
class MessageMapping {
  /// Destination (without the app prefix); must start with `/`.
  final String destination;

  const MessageMapping(this.destination);
}

/// Publishes a `@MessageMapping` method's return value to a broker
/// destination (Spring's `@SendTo`).
@Target({TargetKind.method})
class SendTo {
  /// Broker destination; must start with `/`.
  final String destination;

  const SendTo(this.destination);
}
