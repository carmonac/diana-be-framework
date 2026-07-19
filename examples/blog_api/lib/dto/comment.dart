import 'package:diana/diana.dart';

part 'comment.diana.dart';

/// A comment on a post. `@Table` maps it for the query repository; the
/// nullable `id` lets `save()` omit it so sqlite autoincrements, and
/// `@JsonField(name:)` doubles as the column-name override.
@Json()
@Table('comments')
class Comment {
  final int? id;

  @JsonField(name: 'post_id')
  final int postId;

  final String author;
  final String body;

  const Comment({
    this.id,
    required this.postId,
    required this.author,
    required this.body,
  });
}
