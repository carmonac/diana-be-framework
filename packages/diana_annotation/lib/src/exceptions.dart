import 'package:meta/meta_meta.dart';

/// Marks a class as a global exception-handling component.
///
/// Methods annotated with [ExceptionHandler] map thrown exceptions to
/// responses. The class joins the dependency injection graph as a singleton.
@Target({TargetKind.classType})
class ControllerAdvice {
  const ControllerAdvice();
}

/// Handles exceptions of type [exception] (and its subtypes) thrown by any
/// route.
///
/// Valid signatures:
/// `DianaResponse on(MyException e)` or
/// `DianaResponse on(MyException e, DianaRequest req)`, optionally `async`.
/// When several handlers match, the most specific exception type wins.
@Target({TargetKind.method})
class ExceptionHandler {
  final Type exception;
  const ExceptionHandler(this.exception);
}
