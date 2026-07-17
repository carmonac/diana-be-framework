/// Server-Sent Events: routes return `Stream<ServerSentEvent>` (or
/// `Stream<Dto>`) and Diana emits a spec-compliant `text/event-stream`
/// response with optional keep-alive heartbeats.
library;

import 'dart:async';
import 'dart:convert';

import 'http/request.dart';
import 'http/response.dart';

/// One event of an SSE stream.
class ServerSentEvent {
  /// Event payload (`data:` lines; multi-line data is split per spec).
  final String data;

  /// `id:` field — lets clients resume with `Last-Event-ID`.
  final String? id;

  /// `event:` field — the event type dispatched to listeners.
  final String? event;

  /// `retry:` field — client reconnection delay in milliseconds.
  final int? retryMs;

  const ServerSentEvent(this.data, {this.id, this.event, this.retryMs});

  /// Convenience: JSON-encodes [data] (generated adapters use this for
  /// `Stream<Dto>` routes).
  ServerSentEvent.json(Object? data, {String? id, String? event, int? retryMs})
      : this(jsonEncode(data), id: id, event: event, retryMs: retryMs);
}

/// Encodes [events] into the `text/event-stream` wire format. A positive
/// [heartbeatSeconds] interleaves comment lines (`: keep-alive`) so proxies
/// keep the connection open — and so a dead client is detected on the next
/// write.
Stream<List<int>> encodeSse(
  Stream<ServerSentEvent> events, {
  int heartbeatSeconds = 0,
}) {
  final controller = StreamController<List<int>>();
  Timer? heartbeat;
  late StreamSubscription<ServerSentEvent> subscription;

  void startHeartbeat() {
    if (heartbeatSeconds <= 0) return;
    heartbeat = Timer.periodic(Duration(seconds: heartbeatSeconds), (_) {
      if (!controller.isClosed) {
        controller.add(utf8.encode(': keep-alive\n\n'));
      }
    });
  }

  controller.onListen = () {
    startHeartbeat();
    subscription = events.listen(
      (event) => controller.add(utf8.encode(encodeSseEvent(event))),
      onError: (Object error, StackTrace stackTrace) {
        // A source error terminates the stream: cancel the heartbeat (it
        // would otherwise keep writing into the closed connection forever)
        // and close after forwarding.
        heartbeat?.cancel();
        unawaited(subscription.cancel());
        controller.addError(error, stackTrace);
        controller.close();
      },
      onDone: controller.close,
    );
  };
  controller.onCancel = () async {
    heartbeat?.cancel();
    await subscription.cancel();
  };
  return controller.stream;
}

/// Frames a single event per the SSE specification.
String encodeSseEvent(ServerSentEvent event) {
  final buffer = StringBuffer();
  if (event.id != null) buffer.writeln('id: ${event.id}');
  if (event.event != null) buffer.writeln('event: ${event.event}');
  if (event.retryMs != null) buffer.writeln('retry: ${event.retryMs}');
  for (final line in event.data.split('\n')) {
    buffer.writeln('data: $line');
  }
  buffer.writeln();
  return buffer.toString();
}

/// Builds the streaming SSE response for [events]: 200,
/// `text/event-stream`, `cache-control: no-cache`, heartbeat from
/// `request.limits.sseHeartbeatSeconds`.
DianaResponse sseResponse(
  DianaRequest request,
  Stream<ServerSentEvent> events,
) =>
    DianaResponse.stream(
      encodeSse(events,
          heartbeatSeconds: request.limits.sseHeartbeatSeconds),
      mimeType: 'text/event-stream',
      headers: const {'cache-control': 'no-cache'},
    );
