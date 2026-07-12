import 'package:diana/diana.dart';

part 'create_todo_request.diana.dart';

/// JSON handled entirely by Diana's `@Json` codegen — no fromJson/toJson
/// boilerplate (compare with TodoDto, which uses json_serializable).
/// Validation annotations compose with `@Json` in the same class.
@Json()
class CreateTodoRequest {
  @NotBlank(message: 'title is required')
  @Size(max: 120)
  final String title;

  @Min(1)
  @Max(5)
  final int? priority;

  const CreateTodoRequest({required this.title, this.priority});
}
