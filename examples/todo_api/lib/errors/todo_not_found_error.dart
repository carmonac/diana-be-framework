/// Domain exception: deliberately NOT part of Diana's HttpException
/// hierarchy — the `@ControllerAdvice` maps it to an HTTP response.
class TodoNotFoundError implements Exception {
  final int id;

  const TodoNotFoundError(this.id);

  @override
  String toString() => 'TodoNotFoundError($id)';
}
