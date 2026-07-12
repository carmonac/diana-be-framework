# JSON serialization

Diana gives you three interchangeable ways to serialize DTOs. Route
adapters detect which one a class uses — at build time, with actionable
errors.

## Option 1 — `@Json` (recommended: zero boilerplate)

Annotate the class; Diana generates the codec into the part file and route
adapters use it automatically. No `fromJson`, no `toJson`:

```dart
import 'package:diana/diana.dart';

part 'create_todo_request.diana.dart';

@Json()
class CreateTodoRequest {
  @NotBlank()                 // validation composes with @Json
  final String title;

  @JsonField(name: 'prio')    // rename the JSON key
  final int? priority;

  const CreateTodoRequest({required this.title, this.priority});
}
```

Supported field types: `String`, `int`, `double`, `bool`, `num`, `dynamic`,
`DateTime` (ISO-8601), enums (by name), `List<T>` and `Map<String, T>` of
supported types, nested `@Json` classes (codec-to-codec) or classes
following the convention below — all optionally nullable. Anything else is
a build error listing exactly this set.

Rules: `part` directive required; public unnamed constructor whose
parameters match field names. Bodies that don't match the DTO shape
(wrong types, missing keys, unknown enum values) become **400s**, not 500s.

Generated names: `$CreateTodoRequestFromJson` / `$CreateTodoRequestToJson`
— public, callable manually if needed.

## Option 2 — hand-written convention

```dart
class TodoDto {
  final int id;
  const TodoDto({required this.id});

  factory TodoDto.fromJson(Map<String, dynamic> json) =>
      TodoDto(id: json['id'] as int);
  Map<String, dynamic> toJson() => {'id': id};
}
```

Full control; verified at build time (`fromJson` needed for `@Body`,
`toJson` for returns).

## Option 3 — json_serializable

Diana's `.diana.dart` part files coexist with json_serializable's
`.g.dart`; one `build_runner` run drives both. The
[todo_api example](../../examples/todo_api) keeps `TodoDto` on
json_serializable precisely to prove the interop.

## What routes accept and return

The full table of `@Body` parameter types (including `String` raw bodies
and `FormData` uploads) and return types is in the
[controllers guide](controllers.md#request-bodies).

## Manual JSON responses

`DianaResponse.json(data)` encodes with `jsonEncode`. Prefer explicit
`$XToJson(dto)` / `dto.toJson()` for compile-time safety.
