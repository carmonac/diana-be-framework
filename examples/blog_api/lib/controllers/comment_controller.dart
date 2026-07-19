import 'package:diana/diana.dart';

import '../dto/comment.dart';
import '../repositories/comment_repository.dart';

part 'comment_controller.diana.dart';

/// HTTP surface over the generated query repository.
@RestController('/comments')
class CommentController {
  final CommentRepository comments;

  CommentController(this.comments);

  @Get()
  Future<List<Comment>> list() => comments.findAll();

  @Post()
  @ResponseStatus(201)
  Future<void> create(@Body() Comment body) => comments.save(body);
}
