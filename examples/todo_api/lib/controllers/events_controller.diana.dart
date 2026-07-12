// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import

part of 'events_controller.dart';

Future<DianaResponse> $diana$EventsController$ticks(
  EventsController c,
  DianaRequest req,
) async {
  final result = c.ticks();
  return sseResponse(req, result);
}

Future<DianaResponse> $diana$EventsController$todoFeed(
  EventsController c,
  DianaRequest req,
) async {
  final result = c.todoFeed();
  return sseResponse(req, result.map((e) => ServerSentEvent.json(e.toJson())));
}
