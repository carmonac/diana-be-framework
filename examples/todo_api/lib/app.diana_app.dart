// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import

// ignore_for_file: no_leading_underscores_for_library_prefixes
import 'dart:async' as _i11;

import 'package:diana/diana.dart' as _i1;
import 'package:todo_api/advice/error_advice.dart' as _i2;
import 'package:todo_api/config/app_info_props.dart' as _i3;
import 'package:todo_api/controllers/info_controller.dart' as _i8;
import 'package:todo_api/controllers/todo_controller.dart' as _i10;
import 'package:todo_api/errors/todo_not_found_error.dart' as _i12;
import 'package:todo_api/middleware/api_key_middleware.dart' as _i4;
import 'package:todo_api/middleware/logging_middleware.dart' as _i5;
import 'package:todo_api/repositories/todo_repository.dart' as _i6;
import 'package:todo_api/services/todo_service.dart' as _i9;
import 'package:todo_api/websocket/chat_handler.dart' as _i7;

class DianaContext {
  DianaContext(this.config);

  final _i1.DianaConfig config;

  late final _i2.ErrorAdvice errorAdvice = _i2.ErrorAdvice();

  late final _i3.AppInfoProps appInfoProps = _i3.$AppInfoPropsFromConfig(
    config,
  );

  late final _i4.ApiKeyMiddleware apiKeyMiddleware = _i4.ApiKeyMiddleware(
    config.get<String>('app.apiKey', defaultValue: 'secret'),
  );

  late final _i5.LoggingMiddleware loggingMiddleware = _i5.LoggingMiddleware();

  late final _i6.InMemoryTodoRepository inMemoryTodoRepository =
      _i6.InMemoryTodoRepository();

  late final _i7.ChatHandler chatHandler = _i7.ChatHandler();

  late final _i8.InfoController infoController = _i8.InfoController(
    appInfoProps,
  );

  late final _i9.TodoService todoService = _i9.TodoService(
    inMemoryTodoRepository,
  );

  late final _i10.TodoController todoController = _i10.TodoController(
    todoService,
  );
}

DianaContext buildDianaContext({_i1.DianaConfig? config}) =>
    DianaContext(config ?? const _i1.DianaConfig.empty());
_i11.FutureOr<_i1.DianaResponse?> _mapException(
  DianaContext ctx,
  Object e,
  _i1.DianaRequest req,
) {
  if (e is _i12.TodoNotFoundError)
    return ctx.errorAdvice.onTodoNotFound(e, req);
  return null;
}

Future<_i1.DianaServer> buildDianaServer({_i1.DianaConfig? config}) async {
  final cfg = config ?? await _i1.DianaConfig.load('application.yaml');
  final ctx = DianaContext(cfg);
  final server = _i1.DianaServer(
    config: cfg,
    globalMiddleware: [ctx.loggingMiddleware],
    exceptionMapper: (e, st, req) => _mapException(ctx, e, req),
  );
  server.register(
    _i1.HttpMethod.get,
    '/info',
    (req) => _i8.$diana$InfoController$get(ctx.infoController, req),
  );
  server.register(
    _i1.HttpMethod.get,
    '/todos',
    (req) => _i10.$diana$TodoController$list(ctx.todoController, req),
  );
  server.register(
    _i1.HttpMethod.get,
    '/todos/:id',
    (req) => _i10.$diana$TodoController$getById(ctx.todoController, req),
  );
  server.register(
    _i1.HttpMethod.post,
    '/todos',
    (req) => _i10.$diana$TodoController$create(ctx.todoController, req),
  );
  server.register(
    _i1.HttpMethod.delete,
    '/todos/:id',
    (req) => _i10.$diana$TodoController$remove(ctx.todoController, req),
    middleware: [ctx.apiKeyMiddleware],
  );
  server.registerWebSocket('/ws/chat/:room', () => ctx.chatHandler);
  return server;
}

Future<void> runDiana({_i1.DianaConfig? config}) async {
  final server = await buildDianaServer(config: config);
  await server.serve();
}
