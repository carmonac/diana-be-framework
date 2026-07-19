// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import

part of 'comment_controller.dart';

Future<DianaResponse> $diana$CommentController$list(
  CommentController c,
  DianaRequest req,
) async {
  final result = await c.list();
  return DianaResponse.json([for (final e in result) $CommentToJson(e)]);
}

Future<DianaResponse> $diana$CommentController$create(
  CommentController c,
  DianaRequest req,
) async {
  final $a0$json = await decodeJsonMapBody(req);
  final $a0 = decodeDto(() => $CommentFromJson($a0$json));
  await c.create($a0);
  return const DianaResponse(statusCode: 201);
}
