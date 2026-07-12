import 'package:diana/diana.dart';

import '../errors/todo_not_found_error.dart';

/// Maps domain exceptions to HTTP responses, Spring-style. Handlers for the
/// most specific exception type win; `(exception)` and
/// `(exception, DianaRequest)` signatures are both supported.
@ControllerAdvice()
class ErrorAdvice {
  @ExceptionHandler(TodoNotFoundError)
  DianaResponse onTodoNotFound(TodoNotFoundError e, DianaRequest req) =>
      DianaResponse.json(
        {'error': 'todo_not_found', 'id': e.id, 'path': req.path},
        statusCode: 404,
      );
}
