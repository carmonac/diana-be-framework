// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import

part of 'post_controller.dart';

Future<DianaResponse> $diana$PostController$list(
  PostController c,
  DianaRequest req,
) async {
  final result = await c.list();
  return DianaResponse.json([for (final e in result) $ArticleToJson(e)]);
}

Future<DianaResponse> $diana$PostController$getById(
  PostController c,
  DianaRequest req,
) async {
  final $a0 = bindPathParam<int>(req, 'id');
  final result = await c.getById($a0);
  return DianaResponse.json($ArticleToJson(result));
}

Future<DianaResponse> $diana$PostController$publishPair(
  PostController c,
  DianaRequest req,
) async {
  final $a0$json = await decodeJsonMapBody(req);
  final $a0 = decodeDto(() => $PostPairFromJson($a0$json));
  const $PostPairValidator().validate($a0).throwIfInvalid();
  final result = await c.publishPair($a0);
  return DianaResponse.json([
    for (final e in result) $ArticleToJson(e),
  ], statusCode: 201);
}

Future<DianaResponse> $diana$PostController$fail(
  PostController c,
  DianaRequest req,
) async {
  final $a0$json = await decodeJsonMapBody(req);
  final $a0 = decodeDto(() => $CreatePostFromJson($a0$json));
  const $CreatePostValidator().validate($a0).throwIfInvalid();
  await c.fail($a0);
  return const DianaResponse.noContent();
}

PostPair $PostPairFromJson(Map<String, dynamic> json) => PostPair(
  first: $CreatePostFromJson((json['first'] as Map).cast<String, dynamic>()),
  second: $CreatePostFromJson((json['second'] as Map).cast<String, dynamic>()),
);

Map<String, dynamic> $PostPairToJson(PostPair value) => <String, dynamic>{
  'first': $CreatePostToJson(value.first),
  'second': $CreatePostToJson(value.second),
};

class $PostPairValidator implements Validator<PostPair> {
  const $PostPairValidator();

  @override
  ValidationResult validate(PostPair value) {
    final errors = <FieldError>[];
    mergeNested(
      const $CreatePostValidator().validate(value.first),
      'first',
      errors,
    );
    mergeNested(
      const $CreatePostValidator().validate(value.second),
      'second',
      errors,
    );
    return ValidationResult(errors);
  }
}
