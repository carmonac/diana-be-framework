// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import

part of 'post.dart';

Article $ArticleFromJson(Map<String, dynamic> json) => Article(
  id: (json['id'] as num).toInt(),
  title: json['title'] as String,
  body: json['body'] as String,
);

Map<String, dynamic> $ArticleToJson(Article value) => <String, dynamic>{
  'id': value.id,
  'title': value.title,
  'body': value.body,
};

CreatePost $CreatePostFromJson(Map<String, dynamic> json) =>
    CreatePost(title: json['title'] as String, body: json['body'] as String);

Map<String, dynamic> $CreatePostToJson(CreatePost value) => <String, dynamic>{
  'title': value.title,
  'body': value.body,
};

class $CreatePostValidator implements Validator<CreatePost> {
  const $CreatePostValidator();

  @override
  ValidationResult validate(CreatePost value) {
    final errors = <FieldError>[];
    checkNotBlank(value.title, 'title', errors);
    checkNotBlank(value.body, 'body', errors);
    return ValidationResult(errors);
  }
}
