// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import

// ignore_for_file: no_leading_underscores_for_library_prefixes
import 'dart:async' as _i17;

import 'package:diana/diana.dart' as _i1;
import 'package:todo_api/advice/error_advice.dart' as _i2;
import 'package:todo_api/codecs/app_xml_codec.dart' as _i3;
import 'package:todo_api/config/app_info_props.dart' as _i4;
import 'package:todo_api/controllers/audit_controller.dart' as _i16;
import 'package:todo_api/controllers/events_controller.dart' as _i5;
import 'package:todo_api/controllers/info_controller.dart' as _i12;
import 'package:todo_api/controllers/todo_controller.dart' as _i15;
import 'package:todo_api/controllers/upload_controller.dart' as _i6;
import 'package:todo_api/errors/todo_not_found_error.dart' as _i18;
import 'package:todo_api/health/repository_health.dart' as _i13;
import 'package:todo_api/jobs/heartbeat_job.dart' as _i7;
import 'package:todo_api/middleware/api_key_middleware.dart' as _i8;
import 'package:todo_api/middleware/logging_middleware.dart' as _i9;
import 'package:todo_api/repositories/todo_repository.dart' as _i10;
import 'package:todo_api/services/todo_service.dart' as _i14;
import 'package:todo_api/websocket/chat_handler.dart' as _i11;

class DianaContext {
  DianaContext(this.config, [this._overrides = const DianaOverrides()]);

  final _i1.DianaConfig config;

  final DianaOverrides _overrides;

  late final _i2.ErrorAdvice errorAdvice =
      _overrides.errorAdvice ?? _i2.ErrorAdvice();

  late final _i3.AppXmlCodec appXmlCodec =
      _overrides.appXmlCodec ?? _i3.AppXmlCodec();

  late final _i4.AppInfoProps appInfoProps =
      _overrides.appInfoProps ?? _i4.$AppInfoPropsFromConfig(config);

  late final _i5.EventsController eventsController =
      _overrides.eventsController ?? _i5.EventsController();

  late final _i6.UploadController uploadController =
      _overrides.uploadController ?? _i6.UploadController();

  late final _i7.HeartbeatJob heartbeatJob =
      _overrides.heartbeatJob ?? _i7.HeartbeatJob();

  late final _i8.ApiKeyMiddleware apiKeyMiddleware =
      _overrides.apiKeyMiddleware ??
      _i8.ApiKeyMiddleware(
        config.get<String>('app.apiKey', defaultValue: 'secret'),
      );

  late final _i9.LoggingMiddleware loggingMiddleware =
      _overrides.loggingMiddleware ?? _i9.LoggingMiddleware();

  late final _i10.InMemoryTodoRepository inMemoryTodoRepository =
      _overrides.inMemoryTodoRepository ?? _i10.InMemoryTodoRepository();

  late final _i11.ChatHandler chatHandler =
      _overrides.chatHandler ?? _i11.ChatHandler();

  late final _i12.InfoController infoController =
      _overrides.infoController ?? _i12.InfoController(appInfoProps);

  late final _i13.RepositoryHealthIndicator repositoryHealthIndicator =
      _overrides.repositoryHealthIndicator ??
      _i13.RepositoryHealthIndicator(inMemoryTodoRepository);

  late final _i14.TodoService todoService =
      _overrides.todoService ?? _i14.TodoService(inMemoryTodoRepository);

  late final _i15.TodoController todoController =
      _overrides.todoController ?? _i15.TodoController(todoService);

  /// Constructs every singleton in dependency order and runs @PostConstruct hooks.
  Future<void> initialize() async {
    errorAdvice;
    appXmlCodec;
    appInfoProps;
    eventsController;
    uploadController;
    heartbeatJob;
    apiKeyMiddleware;
    loggingMiddleware;
    await inMemoryTodoRepository.warmUp();
    chatHandler;
    infoController;
    repositoryHealthIndicator;
    todoService;
    todoController;
  }

  /// Runs @PreDestroy hooks in reverse dependency order; call after initialize().
  Future<void> dispose() async {
    inMemoryTodoRepository.shutdown();
  }
}

/// Per-provider overrides for tests: a non-null field replaces the real provider everywhere it is injected.
class DianaOverrides {
  const DianaOverrides({
    this.errorAdvice,
    this.appXmlCodec,
    this.appInfoProps,
    this.requestAudit,
    this.eventsController,
    this.uploadController,
    this.heartbeatJob,
    this.apiKeyMiddleware,
    this.loggingMiddleware,
    this.inMemoryTodoRepository,
    this.chatHandler,
    this.infoController,
    this.auditController,
    this.repositoryHealthIndicator,
    this.todoService,
    this.todoController,
  });

  final _i2.ErrorAdvice? errorAdvice;

  final _i3.AppXmlCodec? appXmlCodec;

  final _i4.AppInfoProps? appInfoProps;

  final _i16.RequestAudit? requestAudit;

  final _i5.EventsController? eventsController;

  final _i6.UploadController? uploadController;

  final _i7.HeartbeatJob? heartbeatJob;

  final _i8.ApiKeyMiddleware? apiKeyMiddleware;

  final _i9.LoggingMiddleware? loggingMiddleware;

  final _i10.InMemoryTodoRepository? inMemoryTodoRepository;

  final _i11.ChatHandler? chatHandler;

  final _i12.InfoController? infoController;

  final _i16.AuditController? auditController;

  final _i13.RepositoryHealthIndicator? repositoryHealthIndicator;

  final _i14.TodoService? todoService;

  final _i15.TodoController? todoController;
}

class DianaRequestScope {
  DianaRequestScope(this._ctx);

  final DianaContext _ctx;

  late final _i16.RequestAudit requestAudit =
      _ctx._overrides.requestAudit ?? _i16.RequestAudit();

  late final _i16.AuditController auditController =
      _ctx._overrides.auditController ?? _i16.AuditController(requestAudit);
}

/// The assembled application: context, server and lifecycle entrypoints.
class DianaApp {
  DianaApp(this.context, this.server);

  final DianaContext context;

  final _i1.DianaServer server;

  late final _i1.DianaScheduler scheduler = _i1.DianaScheduler()
    ..schedule(task: () async => context.heartbeatJob.beat(), fixedDelayMs: 50);

  Future<void> initialize() async {
    await context.initialize();
    scheduler.start();
  }

  Future<void> dispose() async {
    await scheduler.stop();
    await context.dispose();
  }
}

DianaContext buildDianaContext({
  _i1.DianaConfig? config,
  DianaOverrides overrides = const DianaOverrides(),
}) => DianaContext(config ?? const _i1.DianaConfig.empty(), overrides);
_i17.FutureOr<_i1.DianaResponse?> _mapException(
  DianaContext ctx,
  Object e,
  _i1.DianaRequest req,
) {
  if (e is _i18.TodoNotFoundError)
    return ctx.errorAdvice.onTodoNotFound(e, req);
  return null;
}

/// Build-time OpenAPI 3 document (info patched from config at startup).
const String dianaOpenApiJson =
    '{"openapi":"3.0.3","info":{"title":"Diana application","version":"0.0.0"},"paths":{"/audit":{"get":{"operationId":"AuditController_get","tags":["AuditController"],"responses":{"200":{"description":"","content":{"application/json":{"schema":{}}}}}}},"/events/ticks":{"get":{"operationId":"EventsController_ticks","tags":["EventsController"],"responses":{"200":{"description":""}}}},"/events/todos":{"get":{"operationId":"EventsController_todoFeed","tags":["EventsController"],"responses":{"200":{"description":""}}}},"/info":{"get":{"operationId":"InfoController_get","tags":["InfoController"],"responses":{"200":{"description":"","content":{"application/json":{"schema":{}}}}}}},"/todos":{"get":{"operationId":"TodoController_list","tags":["TodoController"],"parameters":[{"name":"limit","in":"query","required":false,"schema":{"type":"integer","default":"20"}}],"responses":{"200":{"description":"","content":{"application/json":{"schema":{"type":"array","items":{}}}}}}},"post":{"operationId":"TodoController_create","tags":["TodoController"],"requestBody":{"required":true,"content":{"application/json":{"schema":{"\$ref":"#/components/schemas/CreateTodoRequest"}}}},"responses":{"201":{"description":"","content":{"application/json":{"schema":{}}}}}}},"/todos/xml":{"post":{"operationId":"TodoController_createFromXml","tags":["TodoController"],"requestBody":{"required":true,"content":{"application/xml":{"schema":{"\$ref":"#/components/schemas/CreateTodoRequest"}}}},"responses":{"201":{"description":"","content":{"application/xml":{"schema":{}},"application/json":{"schema":{}}}}}}},"/todos/{id}":{"get":{"operationId":"TodoController_getById","tags":["TodoController"],"parameters":[{"name":"id","in":"path","required":true,"schema":{"type":"integer"}}],"responses":{"200":{"description":"","content":{"application/json":{"schema":{}}}}}},"delete":{"operationId":"TodoController_remove","tags":["TodoController"],"parameters":[{"name":"id","in":"path","required":true,"schema":{"type":"integer"}}],"responses":{"204":{"description":""}}}},"/uploads":{"post":{"operationId":"UploadController_upload","tags":["UploadController"],"requestBody":{"required":true,"content":{"multipart/form-data":{"schema":{}}}},"responses":{"201":{"description":"","content":{"application/json":{"schema":{}}}}}}},"/uploads/echo":{"post":{"operationId":"UploadController_echo","tags":["UploadController"],"requestBody":{"required":true,"content":{"text/plain":{"schema":{"type":"string"}}}},"responses":{"200":{"description":"","content":{"text/plain":{"schema":{"type":"string"}}}}}}}},"components":{"schemas":{"CreateTodoRequest":{"type":"object","properties":{"priority":{"type":"integer","minimum":1,"maximum":5},"title":{"type":"string","maxLength":120,"minLength":1}},"required":["title"]}}}}';
Future<DianaApp> buildDianaApp({
  _i1.DianaConfig? config,
  DianaOverrides overrides = const DianaOverrides(),
}) async {
  final cfg = config ?? await _i1.DianaConfig.load('application.yaml');
  final ctx = DianaContext(cfg, overrides);
  final server = _i1.DianaServer(
    config: cfg,
    globalMiddleware: [ctx.loggingMiddleware],
    bodyCodecs: [ctx.appXmlCodec],
    exceptionMapper: (e, st, req) => _mapException(ctx, e, req),
  );
  server.register(_i1.HttpMethod.get, '/audit', (req) {
    final scope = DianaRequestScope(ctx);
    return _i16.$diana$AuditController$get(scope.auditController, req);
  });
  server.register(
    _i1.HttpMethod.get,
    '/events/ticks',
    (req) => _i5.$diana$EventsController$ticks(ctx.eventsController, req),
  );
  server.register(
    _i1.HttpMethod.get,
    '/events/todos',
    (req) => _i5.$diana$EventsController$todoFeed(ctx.eventsController, req),
  );
  server.register(
    _i1.HttpMethod.get,
    '/info',
    (req) => _i12.$diana$InfoController$get(ctx.infoController, req),
    cors: _i1.CorsPolicy(
      allowedOrigins: ['https://dashboard.example'],
      allowedHeaders: ['*'],
      maxAgeSeconds: 3600,
    ),
  );
  server.register(
    _i1.HttpMethod.get,
    '/todos',
    (req) => _i15.$diana$TodoController$list(ctx.todoController, req),
  );
  server.register(
    _i1.HttpMethod.get,
    '/todos/:id',
    (req) => _i15.$diana$TodoController$getById(ctx.todoController, req),
  );
  server.register(
    _i1.HttpMethod.post,
    '/todos',
    (req) => _i15.$diana$TodoController$create(ctx.todoController, req),
  );
  server.register(
    _i1.HttpMethod.post,
    '/todos/xml',
    (req) => _i15.$diana$TodoController$createFromXml(ctx.todoController, req),
  );
  server.register(
    _i1.HttpMethod.delete,
    '/todos/:id',
    (req) => _i15.$diana$TodoController$remove(ctx.todoController, req),
    middleware: [ctx.apiKeyMiddleware],
  );
  server.register(
    _i1.HttpMethod.post,
    '/uploads',
    (req) => _i6.$diana$UploadController$upload(ctx.uploadController, req),
  );
  server.register(
    _i1.HttpMethod.post,
    '/uploads/echo',
    (req) => _i6.$diana$UploadController$echo(ctx.uploadController, req),
  );
  if (cfg.get<bool>('management.enabled', defaultValue: false)) {
    server.register(
      _i1.HttpMethod.get,
      '/actuator/health',
      _i1.healthEndpointHandler([ctx.repositoryHealthIndicator]),
    );
    server.register(
      _i1.HttpMethod.get,
      '/actuator/info',
      _i1.infoEndpointHandler(cfg),
    );
  }

  if (cfg.get<bool>('server.openapi.enabled', defaultValue: false)) {
    final openApiBody = _i1.patchOpenApiInfo(dianaOpenApiJson, cfg);
    server.register(
      _i1.HttpMethod.get,
      '/openapi.json',
      (req) => _i1.DianaResponse(
        statusCode: 200,
        bodyText: openApiBody,
        mimeType: 'application/json',
      ),
    );
  }

  server.registerWebSocket(
    '/ws/chat/:room',
    () => ctx.chatHandler,
    middleware: [ctx.apiKeyMiddleware],
  );
  return DianaApp(ctx, server);
}

Future<_i1.DianaServer> buildDianaServer({
  _i1.DianaConfig? config,
  DianaOverrides overrides = const DianaOverrides(),
}) async {
  final app = await buildDianaApp(config: config, overrides: overrides);
  return app.server;
}

Future<void> runDiana({
  _i1.DianaConfig? config,
  DianaOverrides overrides = const DianaOverrides(),
}) => _i1.DianaRuntime.run(() async {
  final app = await buildDianaApp(config: config, overrides: overrides);
  return _i1.DianaRunnable(
    server: app.server,
    initialize: app.initialize,
    dispose: app.dispose,
  );
});
