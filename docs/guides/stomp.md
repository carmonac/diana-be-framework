# STOMP messaging over WebSockets

Diana speaks **STOMP 1.2** on top of its [WebSocket](websockets.md) support:
an in-memory topic broker, `@MessageMapping` handlers for inbound messages,
and an injectable publisher for server-side sends. It is the Spring
`SimpMessagingTemplate` / simple-broker model, built into `package:diana`
(no extra dependency).

## The endpoint

A STOMP endpoint is a singleton `@WebSocketController` extending
`StompEndpoint`. It delegates every WebSocket callback to the framework's
broker, so it inherits all the WebSocket wiring — including handshake
authentication:

```dart
@WebSocketController('/stomp')
@UseMiddleware([AppAuth])   // authenticate the handshake
@Secured()                  // anonymous upgrades get 401
class ChatGateway extends StompEndpoint {
  ChatGateway(super.broker);
}
```

Clients connect a WebSocket to `/stomp` and speak STOMP frames over it. The
authenticated principal (from the handshake) is available to handlers.

## Handling messages: @MessageMapping / @SendTo

A client SENDs to a destination under the **app prefix** (`stomp.appPrefix`,
default `/app`). `@MessageMapping('/chat')` handles SENDs to `/app/chat`:

```dart
@Service()
class ChatMessaging {
  @MessageMapping('/chat')       // client SENDs to /app/chat
  @SendTo('/topic/chat')         // the return value is published here
  ChatOut chat(ChatIn payload, StompMessage message) {
    final from = message.principal is AuthPrincipal
        ? (message.principal as AuthPrincipal).name
        : 'anonymous';
    return ChatOut(from: from, text: payload.text);
  }
}
```

- **Payload**: the first parameter is either a `String` (the raw body) or an
  `@Json` class (decoded from the JSON body).
- **Context**: an optional second `StompMessage` parameter carries the
  destination, headers, body, session id and principal.
- **Return / @SendTo**: a non-void return (a `String` or an `@Json` class,
  optionally wrapped in `Future`) is published to the `@SendTo` destination.
  A void handler consumes the message without replying. Returning a value
  without `@SendTo` — or `@SendTo` on a void method — is a build error.

Handlers must live on singleton providers; every rule is checked at build
time with an exact message.

## Publishing from server code

Inject `StompPublisher` anywhere to push to a destination — every
subscriber, on any isolate, receives a MESSAGE:

```dart
@Service()
class Alerts {
  Alerts(this.stomp);
  final StompPublisher stomp;

  Future<void> broadcast(String text) =>
      stomp.publish('/topic/alerts', text, contentType: 'text/plain');
}
```

## Subscriptions and acknowledgements

Clients SUBSCRIBE with an `id`, an `ack` mode (`auto` — the default — /
`client` / `client-individual`) and a destination (**exact match**, no
wildcards). In `client`/`client-individual` mode each MESSAGE carries an
`ack` header; the client ACKs (or NACKs) to release it:

- `client` — an ACK is **cumulative**: it releases that message and every
  earlier un-acked one in the subscription.
- `client-individual` — an ACK releases only that message.

**NACK drops the message and logs it — there is no redelivery.** The broker
is in-memory with no persistent queue, so NACK is spec-legal but purely
informational.

## Transactions

`BEGIN`/`COMMIT`/`ABORT` buffer SENDs and ACKs per transaction: `COMMIT`
applies them in arrival order, `ABORT` discards them. (App-destined SENDs
inside a transaction are dispatched on commit too.)

## Heartbeats

The client's CONNECT `heart-beat:cx,cy` negotiates against the server's
`stomp.heartbeatMs` (default 10000) per direction (`max` of the two, `0`
disables). The server sends a bare LF at the outgoing interval and closes a
connection whose client goes silent for twice the incoming interval.

## Configuration

| Key | Default | Meaning |
|---|---|---|
| `stomp.appPrefix` | `/app` | Destinations under this prefix route to `@MessageMapping` handlers |
| `stomp.heartbeatMs` | `10000` | Server heartbeat interval offered at CONNECT (both directions) |

## Cross-isolate delivery

With `server.isolates > 1`, a publish to a topic reaches subscribers on
**every** isolate exactly once: the broker relays through the same
[event-bus](events.md) broadcast machinery Diana uses for application
events (hub-and-spoke, drained on shutdown).

## Limitations

- **No `Sec-WebSocket-Protocol` negotiation.** The underlying relic upgrade
  does not echo the `v12.stomp` subprotocol; lenient clients (STOMP.js over
  a raw WebSocket) tolerate this, strict ones may not.
- **Exact-match destinations** — no wildcards or destination hierarchies
  (the Spring simple broker's model).
- **`login`/`passcode` on CONNECT are ignored** — authenticate on the
  handshake with `@UseMiddleware`/`@Secured` instead.
- A SEND to an **unmapped** `/app/...` destination is dropped and logged
  (Spring's behavior).
- Pending (un-acked) messages are held per connection with no upper bound —
  a client that never ACKs in `client` mode grows the set until it
  disconnects.
