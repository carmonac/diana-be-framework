import 'package:diana/diana.dart';

import '../repositories/todo_repository.dart';

/// Contributes to `GET /actuator/health` (enabled via `management.enabled`).
@Component()
class RepositoryHealthIndicator implements HealthIndicator {
  final InMemoryTodoRepository repository;

  RepositoryHealthIndicator(this.repository);

  @override
  String get name => 'todoRepository';

  @override
  Future<HealthStatus> health() async => repository.warmedUp
      ? HealthStatus.up({'todos': repository.findAll().length})
      : const HealthStatus.down({'reason': 'not warmed up'});
}
