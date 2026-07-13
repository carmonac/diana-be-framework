import 'package:diana/diana.dart';

import '../dto/create_todo_request.dart';
import '../dto/todo_dto.dart';
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
  Future<TodoDto> create(@Body() CreateTodoRequest body) =>
      service.create(body);

  /// XML in, XML or JSON out (negotiated by Accept) — same DTO pipeline.
  @Post('/xml')
  @ResponseStatus(201)
  @Consumes(['application/xml'])
  @Produces(['application/xml', 'application/json'])
  Future<TodoDto> createFromXml(@Body() CreateTodoRequest body) =>
      service.create(body);

  /// Deleting requires the `admin` role — enforced by the generated guard
  /// running after the global `AppAuth` authentication filter.
  @Delete('/:id')
  @RolesAllowed(['admin'])
  void remove(@PathParam() int id) => service.delete(id);
}
