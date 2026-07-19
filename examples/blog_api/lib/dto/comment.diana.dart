// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import

part of 'comment.dart';

Comment $CommentFromJson(Map<String, dynamic> json) => Comment(
  id: (json['id'] as num?)?.toInt(),
  postId: (json['post_id'] as num).toInt(),
  author: json['author'] as String,
  body: json['body'] as String,
);

Map<String, dynamic> $CommentToJson(Comment value) => <String, dynamic>{
  'id': value.id,
  'post_id': value.postId,
  'author': value.author,
  'body': value.body,
};
