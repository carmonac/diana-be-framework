# JSON serialization

Diana does not impose a serialization library. It relies on the standard
Dart convention and **verifies it at build time**:

- A class received with `@Body()` must expose
  `factory X.fromJson(Map<String, dynamic> json)` (a static `fromJson`
  method also works).
- A class returned from a route must expose
  `Map<String, dynamic> toJson()` (inherited implementations count).

If either is missing, the build fails pointing at the exact route and
telling you what to add.

## Option 1 — hand-written

```dart
class CreateTodoRequest {
  final String title;
  final int? priority;

  const CreateTodoRequest({required this.title, this.priority});

  factory CreateTodoRequest.fromJson(Map<String, dynamic> json) =>
      CreateTodoRequest(
        title: json['title'] as String? ?? '',
        priority: json['priority'] as int?,
      );

  Map<String, dynamic> toJson() => {'title': title, 'priority': priority};
}
```

Full control, no extra dependency. Prefer lenient casts in `fromJson`
(`as String? ?? ''`) and let [validation](validation.md) produce the
user-facing errors.

## Option 2 — json_serializable

Diana's part files use the `.diana.dart` suffix precisely so they coexist
with json_serializable's `.g.dart`:

```yaml
dependencies:
  json_annotation: ^4.9.0
dev_dependencies:
  json_serializable: ^6.9.0
```

```dart
import 'package:json_annotation/json_annotation.dart';

part 'todo_dto.g.dart';           // json_serializable
// part 'todo_dto.diana.dart';    // add if the class also has constraints

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
```

One `dart run build_runner build` drives both generators. Mixing styles in
one project is fine — the
[todo_api example](../../examples/todo_api) does exactly that.

## What routes accept and return

The exact table of supported `@Body` parameter types and route return
types lives in the
[controllers guide](controllers.md#request-bodies). Summary: DTOs,
`List<Dto>`, `Map<String, dynamic>`, JSON primitives and `String`
(text/plain), `void` (204) and raw `DianaResponse` — all optionally
`Future`-wrapped.

## Manual JSON responses

`DianaResponse.json(data)` encodes with `jsonEncode`, so anything
`jsonEncode` accepts works: maps, lists, primitives, and objects whose
`toJson()` it can call. Prefer passing `dto.toJson()` explicitly for
compile-time safety.

## Roadmap

A Diana-native JSON generator (deriving `fromJson`/`toJson` from the
constructor, like json_serializable but integrated with the validator
generation) is planned post-MVP. The convention-based contract will keep
working regardless.
