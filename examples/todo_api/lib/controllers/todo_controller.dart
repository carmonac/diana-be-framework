import 'package:diana/diana.dart';

import '../dto/create_todo_request.dart';
import '../dto/todo_dto.dart';
import '../middleware/api_key_middleware.dart';
import '../services/todo_service.dart';

part 'todo_controller.diana.dart';

@RestController('/todos')
class TodoController {
  final TodoService service;

  TodoController(this.service);

  @Get()
  List<TodoDto> list(@QueryParam('limit', '20') int limit) =>
      service.list(limit);

  @Get('/:id')
  TodoDto getById(@PathParam() int id) => service.getOrThrow(id);

  @Post()
  @ResponseStatus(201)
  TodoDto create(@Body() CreateTodoRequest body) => service.create(body);

  @Delete('/:id')
  @UseMiddleware([ApiKeyMiddleware])
  void remove(@PathParam() int id) => service.delete(id);
}
