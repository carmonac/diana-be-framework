// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import

part of 'create_todo_request.dart';

CreateTodoRequest $CreateTodoRequestFromJson(Map<String, dynamic> json) =>
    CreateTodoRequest(
      title: json['title'] as String,
      priority: (json['priority'] as num?)?.toInt(),
    );

Map<String, dynamic> $CreateTodoRequestToJson(CreateTodoRequest value) =>
    <String, dynamic>{'title': value.title, 'priority': value.priority};

class $CreateTodoRequestValidator implements Validator<CreateTodoRequest> {
  const $CreateTodoRequestValidator();

  @override
  ValidationResult validate(CreateTodoRequest value) {
    final errors = <FieldError>[];
    checkNotBlank(value.title, 'title', errors, message: 'title is required');
    checkSize(value.title, 'title', errors, max: 120);
    checkMin(value.priority, 1, 'priority', errors);
    checkMax(value.priority, 5, 'priority', errors);
    return ValidationResult(errors);
  }
}
