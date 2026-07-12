import 'package:diana/diana.dart';

part 'create_todo_request.diana.dart';

class CreateTodoRequest {
  @NotBlank(message: 'title is required')
  @Size(max: 120)
  final String title;

  @Min(1)
  @Max(5)
  final int? priority;

  const CreateTodoRequest({required this.title, this.priority});

  factory CreateTodoRequest.fromJson(Map<String, dynamic> json) =>
      CreateTodoRequest(
        title: json['title'] as String? ?? '',
        priority: json['priority'] as int?,
      );

  Map<String, dynamic> toJson() => {'title': title, 'priority': priority};
}
