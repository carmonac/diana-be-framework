import 'package:json_annotation/json_annotation.dart';

part 'todo_dto.g.dart';

/// JSON via json_serializable — Diana's convention only requires
/// `fromJson`/`toJson`, so hand-written and generated JSON coexist
/// (compare with CreateTodoRequest, which writes them by hand).
@JsonSerializable()
class TodoDto {
  final int id;
  final String title;
  final bool done;

  const TodoDto({required this.id, required this.title, this.done = false});

  factory TodoDto.fromJson(Map<String, dynamic> json) =>
      _$TodoDtoFromJson(json);

  Map<String, dynamic> toJson() => _$TodoDtoToJson(this);
}
