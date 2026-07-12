import 'package:meta/meta_meta.dart';

import 'di.dart';

/// Registers a class implementing Diana's `WebSocketHandler` interface as a
/// WebSocket endpoint at [path] (Spring: a `WebSocketHandler` registered
/// through `WebSocketConfigurer`).
///
/// The class joins the dependency injection graph. [scope] controls handler
/// instances:
///
/// - [Scope.singleton] (default): one shared handler for all connections —
///   keep per-connection state in `WebSocketSession.attributes`.
/// - [Scope.transient]: a fresh handler per connection — instance fields
///   are per-connection state.
///
/// [Scope.request] is not applicable to WebSockets and is a build error.
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
@Target({TargetKind.classType})
class WebSocketController {
  /// Endpoint path. May contain `:name` path parameters, available through
  /// `WebSocketSession.pathParameters`.
  final String path;

  final Scope scope;

  const WebSocketController(this.path, [this.scope = Scope.singleton]);
}
