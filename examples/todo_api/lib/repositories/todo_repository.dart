import 'package:diana/diana.dart';

import '../dto/todo_dto.dart';

abstract interface class TodoRepository {
  List<TodoDto> findAll({int limit});
  TodoDto? find(int id);
  TodoDto save(String title);
  bool delete(int id);
}

@Repository()
class InMemoryTodoRepository implements TodoRepository {
  final Map<int, TodoDto> _todos = {
    1: const TodoDto(id: 1, title: 'learn diana'),
  };
  int _nextId = 2;

  @override
  List<TodoDto> findAll({int limit = 20}) =>
      _todos.values.take(limit).toList();

  @override
  TodoDto? find(int id) => _todos[id];

  @override
  TodoDto save(String title) {
    final todo = TodoDto(id: _nextId++, title: title);
    _todos[todo.id] = todo;
    return todo;
  }

  @override
  bool delete(int id) => _todos.remove(id) != null;
}
