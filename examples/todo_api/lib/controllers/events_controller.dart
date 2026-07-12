import 'dart:async';

import 'package:diana/diana.dart';

import '../dto/todo_dto.dart';

part 'events_controller.diana.dart';

/// Server-Sent Events: routes return a Stream and Diana emits
/// text/event-stream with keep-alive heartbeats and disconnect cleanup.
@RestController('/events')
class EventsController {
  /// Raw events with full control over id/event/retry fields.
  @Get('/ticks')
  Stream<ServerSentEvent> ticks() async* {
    for (var i = 1; i <= 3; i++) {
      yield ServerSentEvent('tick $i', id: '$i', event: 'tick');
      await Future<void>.delayed(const Duration(milliseconds: 30));
    }
  }

  /// DTO streams: each element is JSON-encoded as the event data.
  @Get('/todos')
  Stream<TodoDto> todoFeed() => Stream.fromIterable(const [
        TodoDto(id: 1, title: 'learn diana'),
        TodoDto(id: 2, title: 'stream events'),
      ]);
}
