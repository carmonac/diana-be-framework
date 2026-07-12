# WebSockets

Diana's WebSocket support mirrors Spring's `WebSocketHandler` /
`WebSocketSession` model: implement a handler interface, annotate it with a
path, and the framework wires the HTTP upgrade, the lifecycle callbacks and
dependency injection.

```dart
import 'package:diana/diana.dart';

@WebSocketController('/ws/echo')
class EchoHandler extends BaseWebSocketHandler {
  @override
  void onOpen(WebSocketSession session) => session.sendText('welcome');

  @override
  void onMessage(WebSocketSession session, WebSocketMessage message) {
    if (message is TextMessage) session.sendText(message.text);
  }
}
```

Clients connect with any WebSocket client:

```dart
final socket = await WebSocket.connect('ws://localhost:8080/ws/echo');
```

## The handler lifecycle

`WebSocketHandler` declares four callbacks (Spring's
`afterConnectionEstablished` / `handleMessage` / `handleTransportError` /
`afterConnectionClosed`, with shorter names). Extend
`BaseWebSocketHandler` to override only what you need; all callbacks may be
`async`.

| Callback | When |
|---|---|
| `onOpen(session)` | Connection established. |
| `onMessage(session, message)` | A frame arrived — `TextMessage(text)` or `BinaryMessage(data)` (pattern-match the sealed type). |
| `onError(session, error, stackTrace)` | A transport error or an exception escaped a callback; the connection is closed with code 1011 afterwards. |
| `onClose(session, code, reason)` | Connection closed by either side; always called last. |

Messages within one connection are dispatched **sequentially** — `await`ing
in `onMessage` back-pressures that connection's frames.

## The session

`WebSocketSession` is your channel to one connected peer:

| Member | Description |
|---|---|
| `id` | Unique per connection (`ws-1`, `ws-2`, …). |
| `uri` | The URI the client connected to. |
| `pathParameters` | Route parameters — `@WebSocketController('/ws/chat/:room')` ⇒ `session.pathParameters['room']`. |
| `queryParameters` | Handshake query string. |
| `attributes` | Per-connection `Map<String, Object?>` bag, alive for the whole session. |
| `isOpen` | Whether the connection is (believed) open. |
| `sendText(text)` / `sendBytes(data)` | Send a frame; return `false` instead of throwing when already closed. |
| `close([code, reason])` | Close the connection (`code`: 1000 or 3000–4999). |

Keep a `Set<WebSocketSession>` in your handler to broadcast — see the
[chat example](../../examples/todo_api/lib/websocket/chat_handler.dart).

## Handler instances and scope

`@WebSocketController(path, [scope])` — the class joins the DI graph
(constructor injection, `@Value`, everything from the
[DI guide](dependency-injection.md) applies):

- **`Scope.singleton`** (default): one shared handler for all connections —
  Spring's default. Keep per-connection state in `session.attributes`, and
  connection registries as handler fields.
- **`Scope.transient`**: a **fresh handler per connection** — instance
  fields become per-connection state, no bookkeeping needed.
- `Scope.request` doesn't apply to WebSockets and is a build error.

```dart
@WebSocketController('/ws/game', Scope.transient)
class GameSession extends BaseWebSocketHandler {
  GameSession(this.engine);        // injected per connection
  final GameEngine engine;
  int score = 0;                   // this connection's state
}
```

## Handshake interceptors

`@UseMiddleware` on a `@WebSocketController` runs the listed
[middleware](middleware.md) on the **handshake request**:

```dart
@WebSocketController('/ws/chat/:room')
@UseMiddleware([ApiKeyMiddleware])
class ChatHandler extends BaseWebSocketHandler {
  @override
  void onOpen(WebSocketSession session) {
    final user = session.attributes['user'];   // set by the middleware
    ...
  }
}
```

- A middleware that short-circuits (e.g. returns a 401) **blocks the
  upgrade** with that response.
- `request.attributes` set during the handshake are copied into
  `session.attributes`.
- Exceptions in handshake middleware go through the normal exception
  pipeline (advice, `HttpException` mapping).
- Global middleware do **not** apply to handshakes — interceptors are
  explicit opt-in (mirroring Spring's `HandshakeInterceptor` registration).

## What does *not* apply

- After the upgrade, middleware and `@ControllerAdvice` play no role in
  socket traffic; errors reach the handler's `onError`.
- The [validation](validation.md) machinery targets request bodies; decode
  and validate WebSocket payloads yourself (e.g.
  `$MyDtoFromJson(jsonDecode(message.text))` plus a generated
  `$MyDtoValidator`).

## Build-time checks

- The annotated class must implement `WebSocketHandler` (or extend
  `BaseWebSocketHandler`).
- Endpoint paths must be unique across the application.
- `Scope.request` is rejected.

See [build diagnostics](../reference/build-diagnostics.md#websockets).

## What gets generated

One registration per endpoint in `buildDianaServer()`:

```dart
server.registerWebSocket('/ws/chat/:room', () => ctx.chatHandler,
    middleware: [ctx.apiKeyMiddleware]);                                 // singleton
server.registerWebSocket('/ws/game', () => ctx.createGameSession());    // transient
```

## Testing

Connect a real client from `dart:io` against an ephemeral port:

```dart
final server = await buildDianaServer(config: const DianaConfig.empty());
await server.serve(port: 0, quiet: true);

final ws = await WebSocket.connect(
    'ws://127.0.0.1:${server.port}/ws/chat/dart');
ws.add('hello');
expect(await ws.first, 'joined dart');
```

The [example's WebSocket suite](../../examples/todo_api/test/websocket_test.dart)
shows multi-client broadcast assertions.
