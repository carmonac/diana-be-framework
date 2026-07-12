// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import

part of 'todo_controller.dart';

Future<DianaResponse> $diana$TodoController$list(
  TodoController c,
  DianaRequest req,
) async {
  final $a0 = bindQueryParam<int>(req, 'limit', defaultValue: '20');
  final result = c.list($a0);
  return DianaResponse.json([for (final e in result) e.toJson()]);
}

Future<DianaResponse> $diana$TodoController$getById(
  TodoController c,
  DianaRequest req,
) async {
  final $a0 = bindPathParam<int>(req, 'id');
  final result = c.getById($a0);
  return DianaResponse.json(result.toJson());
}

Future<DianaResponse> $diana$TodoController$create(
  TodoController c,
  DianaRequest req,
) async {
  final $a0 = CreateTodoRequest.fromJson(await decodeJsonMapBody(req));
  const $CreateTodoRequestValidator().validate($a0).throwIfInvalid();
  final result = c.create($a0);
  return DianaResponse.json(result.toJson(), statusCode: 201);
}

Future<DianaResponse> $diana$TodoController$remove(
  TodoController c,
  DianaRequest req,
) async {
  final $a0 = bindPathParam<int>(req, 'id');
  c.remove($a0);
  return const DianaResponse.noContent();
}
