import 'package:test/test.dart';
import 'package:todo_api/app.diana_app.dart';

void main() {
  test('generated DianaContext wires the object graph', () {
    final ctx = buildDianaContext();
    expect(ctx.todoService.list(10), hasLength(1));
    // Singleton semantics: the service holds the same repository instance.
    expect(identical(ctx.todoService.repo, ctx.inMemoryTodoRepository), isTrue);
    expect(identical(ctx.todoController.service, ctx.todoService), isTrue);
  });
}
