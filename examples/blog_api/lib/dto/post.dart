import 'package:diana/diana.dart';

part 'post.diana.dart';

@Json()
class Article {
  final int id;
  final String title;
  final String body;

  const Article({required this.id, required this.title, required this.body});
}

@Json()
class CreatePost {
  @NotBlank()
  final String title;

  @NotBlank()
  final String body;

  const CreatePost({required this.title, required this.body});
}
