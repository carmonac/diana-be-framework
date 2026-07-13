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
  final $a0$json = await decodeJsonMapBody(req);
  final $a0 = decodeDto(() => $CreateTodoRequestFromJson($a0$json));
  const $CreateTodoRequestValidator().validate($a0).throwIfInvalid();
  final result = await c.create($a0);
  return DianaResponse.json(result.toJson(), statusCode: 201);
}

Future<DianaResponse> $diana$TodoController$createFromXml(
  TodoController c,
  DianaRequest req,
) async {
  final $a0$json = await decodeMapBody(
    req,
    consumes: const ['application/xml'],
  );
  final $a0 = decodeDto(() => $CreateTodoRequestFromJson($a0$json));
  const $CreateTodoRequestValidator().validate($a0).throwIfInvalid();
  final result = await c.createFromXml($a0);
  return negotiatedResponse(
    req,
    result.toJson(),
    produces: const ['application/xml', 'application/json'],
    statusCode: 201,
  );
}

Future<DianaResponse> $diana$TodoController$remove(
  TodoController c,
  DianaRequest req,
) async {
  final $a0 = bindPathParam<int>(req, 'id');
  c.remove($a0);
  return const DianaResponse.noContent();
}
