import 'package:meta/meta_meta.dart';

/// Generates `fromJson`/`toJson` for this class — no boilerplate needed.
///
/// Diana emits public `$XFromJson(Map<String, dynamic>)` and
/// `$XToJson(X)` functions into the class's part file, and route adapters
/// use them automatically when the class appears as a `@Body` parameter or
/// a return type. The class itself stays plain Dart:
///
/// ```dart
/// part 'create_todo_request.diana.dart';
///
/// @Json()
/// class CreateTodoRequest {
///   @NotBlank()
///   final String title;
///
///   @JsonField(name: 'prio')
///   final int? priority;
///
///   const CreateTodoRequest({required this.title, this.priority});
/// }
/// ```
///
/// Supported field types: `String`, `int`, `double`, `bool`, `num`,
/// `dynamic`, `DateTime` (ISO-8601), enums (by name), `List`/`Map<String, _>`
/// of supported types, nested `@Json` classes or classes following the
/// `fromJson`/`toJson` convention — all optionally nullable. Construction
/// uses the unnamed constructor, whose parameters must match field names.
@Target({TargetKind.classType})
class Json {
  const Json();
}

/// Customizes the JSON key of a field inside a `@Json` class.
@Target({TargetKind.field})
class JsonField {
  /// JSON key; defaults to the field name.
  final String? name;

  const JsonField({this.name});
}
