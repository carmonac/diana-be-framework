import 'package:diana/diana.dart';

import 'todo_created.dart';

/// Reacts to [TodoCreated] events published by the service layer: listener
/// methods are annotated with `@EventListener` and receive every event
/// whose type matches their parameter (subtypes included).
@Component()
class TodoAuditListener {
  final List<String> seen = [];

  @EventListener()
  void onTodoCreated(TodoCreated event) => seen.add(event.title);
}
