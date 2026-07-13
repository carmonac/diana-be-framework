import 'package:diana/diana.dart';

import '../dto/create_todo_request.dart';
import '../dto/todo_dto.dart';
import '../errors/todo_not_found_error.dart';
import '../events/todo_created.dart';
import '../repositories/todo_repository.dart';

@Service()
class TodoService {
  final TodoRepository repo;
  final DianaEventPublisher publisher;

  TodoService(this.repo, this.publisher);

  List<TodoDto> list(int limit) => repo.findAll(limit: limit);

  TodoDto getOrThrow(int id) =>
      repo.find(id) ?? (throw TodoNotFoundError(id));

  Future<TodoDto> create(CreateTodoRequest request) async {
    final todo = repo.save(request.title);
    // Awaited: every @EventListener has run when create() returns.
    await publisher.publish(TodoCreated(todo.id, todo.title));
    return todo;
  }

  void delete(int id) {
    if (!repo.delete(id)) throw TodoNotFoundError(id);
  }
}
