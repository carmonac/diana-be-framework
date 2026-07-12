# Server-Sent Events

Server-Sent Events (SSE) push a stream of events over a single HTTP
response — the browser's `EventSource` API consumes them natively. In
Diana, a route becomes an SSE endpoint by returning a `Stream`. No
annotation needed.

## Two supported stream shapes

**`Stream<ServerSentEvent>`** — full control over the SSE fields:

```dart
@RestController('/events')
class EventsController {
  @Get('/ticks')
  Stream<ServerSentEvent> ticks() async* {
    for (var i = 1; i <= 3; i++) {
      yield ServerSentEvent('tick $i', id: '$i', event: 'tick');
      await Future<void>.delayed(const Duration(seconds: 1));
    }
  }
}
```

**`Stream<Dto>`** — any DTO with a `toJson()` (or `@Json`); each element is
JSON-encoded as the event's `data`:

```dart
@Get('/todos')
Stream<TodoDto> todoFeed() => repository.changes();
```

Both may be wrapped in `Future` (`Future<Stream<…>>`). Any other element
type is a build error, as is combining a `Stream` return with
`@ResponseStatus` (SSE responses are always 200) or `@Produces` (always
`text/event-stream`).

## What Diana sends

- Status 200, `content-type: text/event-stream`,
  `cache-control: no-cache`.
- Spec-compliant framing: `id:`, `event:`, `retry:` fields when set;
  multi-line `data` is split into one `data:` line per line; events are
  separated by a blank line.
- **Immediate flushing**: streamed responses bypass the buffered response
  path and write chunked frames straight to the socket, so an event is on
  the wire the moment your stream emits it.

```
id: 1
event: tick
data: tick 1

```

## Heartbeats and disconnects

Every `server.sse.heartbeatSeconds` (default **15**, `0` disables) Diana
interleaves an SSE comment line (`: keep-alive`) so proxies keep the
connection open. The heartbeat doubles as a disconnect backstop: writing
to a dead socket fails, which tears the response down.

When the client disconnects, your source stream's `onCancel` runs — use it
to release resources:

```dart
@Get('/feed')
Stream<ServerSentEvent> feed() {
  final controller = StreamController<ServerSentEvent>();
  final timer = Timer.periodic(const Duration(seconds: 1),
      (t) => controller.add(ServerSentEvent('t=${t.tick}')));
  controller.onCancel = () => timer.cancel();   // runs on disconnect
  return controller.stream;
}
```

A finite stream ends the response normally when it completes.

## `ServerSentEvent`

| Field | SSE line | Meaning |
|---|---|---|
| `data` | `data:` | Payload (required; multi-line split per spec) |
| `id` | `id:` | Lets clients resume with `Last-Event-ID` |
| `event` | `event:` | Event type dispatched to `addEventListener` |
| `retryMs` | `retry:` | Client reconnection delay (ms) |

`ServerSentEvent.json(object)` JSON-encodes the payload — it's what
generated adapters use for `Stream<Dto>` routes.

## Consuming

```js
const es = new EventSource('/events/ticks');
es.addEventListener('tick', (e) => console.log(e.lastEventId, e.data));
```

Or with curl: `curl -N http://localhost:8080/events/ticks`.

## Manual responses

For full control, return `DianaResponse` and build the stream yourself
with the same public pieces the adapters use:

```dart
return sseResponse(req, events);                       // heartbeat from config
return DianaResponse.stream(encodeSse(events),          // fully manual
    mimeType: 'text/event-stream');
```

`encodeSseEvent` frames a single event if you need the raw text.

## OpenAPI

SSE routes appear in the generated document with a 200 response of content
type `text/event-stream`.

## See also

- [Content negotiation](content-negotiation.md) — non-JSON request/response bodies
- [Configuration keys](../reference/config-keys.md) — `server.sse.heartbeatSeconds`
- [WebSockets](websockets.md) — when you need bidirectional messaging
