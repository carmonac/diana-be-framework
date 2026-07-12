import 'package:diana/diana.dart';

import '../dto/create_todo_request.dart';
import '../dto/todo_dto.dart';
import '../errors/todo_not_found_error.dart';
import '../repositories/todo_repository.dart';

@Service()
class TodoService {
  final TodoRepository repo;

  TodoService(this.repo);

  List<TodoDto> list(int limit) => repo.findAll(limit: limit);

  TodoDto getOrThrow(int id) =>
      repo.find(id) ?? (throw TodoNotFoundError(id));

  TodoDto create(CreateTodoRequest request) => repo.save(request.title);

  void delete(int id) {
    if (!repo.delete(id)) throw TodoNotFoundError(id);
  }
}
