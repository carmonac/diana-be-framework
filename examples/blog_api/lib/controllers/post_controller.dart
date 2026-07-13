import 'package:diana/diana.dart';

import '../dto/post.dart';
import '../services/blog_service.dart';

part 'post_controller.diana.dart';

@RestController('/posts')
class PostController {
  final BlogService service;

  PostController(this.service);

  @Get()
  Future<List<Article>> list() => service.list();

  @Get('/:id')
  Future<Article> getById(@PathParam() int id) => service.get(id);

  @Post()
  @ResponseStatus(201)
  Future<List<Article>> publishPair(@Body() PostPair body) =>
      service.publishPair(body.first, body.second);

  /// Always fails; the transaction rolls back and no post is persisted.
  @Post('/fail')
  Future<void> fail(@Body() CreatePost body) => service.publishThenFail(body);
}

@Json()
class PostPair {
  @Valid()
  final CreatePost first;

  @Valid()
  final CreatePost second;

  const PostPair({required this.first, required this.second});
}
