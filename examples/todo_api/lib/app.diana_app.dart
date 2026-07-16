// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import

// ignore_for_file: no_leading_underscores_for_library_prefixes
import 'dart:async' as _i20;

import 'package:diana/diana.dart' as _i2;
import 'package:diana_auth/diana_auth.dart' as _i22;
import 'package:todo_api/advice/error_advice.dart' as _i3;
import 'package:todo_api/auth/app_auth.dart' as _i4;
import 'package:todo_api/codecs/app_xml_codec.dart' as _i5;
import 'package:todo_api/config/app_info_props.dart' as _i6;
import 'package:todo_api/controllers/audit_controller.dart' as _i19;
import 'package:todo_api/controllers/auth_controller.dart' as _i7;
import 'package:todo_api/controllers/events_controller.dart' as _i8;
import 'package:todo_api/controllers/info_controller.dart' as _i15;
import 'package:todo_api/controllers/todo_controller.dart' as _i18;
import 'package:todo_api/controllers/upload_controller.dart' as _i9;
import 'package:todo_api/errors/todo_not_found_error.dart' as _i21;
import 'package:todo_api/events/todo_audit_listener.dart' as _i10;
import 'package:todo_api/events/todo_created.dart' as _i1;
import 'package:todo_api/health/repository_health.dart' as _i16;
import 'package:todo_api/jobs/heartbeat_job.dart' as _i11;
import 'package:todo_api/middleware/logging_middleware.dart' as _i12;
import 'package:todo_api/repositories/todo_repository.dart' as _i13;
import 'package:todo_api/services/todo_service.dart' as _i17;
import 'package:todo_api/websocket/chat_handler.dart' as _i14;

class DianaContext {
  DianaContext(this.config, [this._overrides = const DianaOverrides()]) {
    eventBus.on<_i1.TodoCreated>((e) => todoAuditListener.onTodoCreated(e));
  }

  final _i2.DianaConfig config;

  final DianaOverrides _overrides;

  final _i2.DianaEventBus eventBus = _i2.DianaEventBus();

  late final _i3.ErrorAdvice errorAdvice =
      _overrides.errorAdvice ?? _i3.ErrorAdvice();

  late final _i4.AppAuth appAuth =
      _overrides.appAuth ??
      _i4.AppAuth(
        config.get<String>(
          'auth.jwt.secret',
          defaultValue: 'insecure-dev-secret',
        ),
      );

  late final _i5.AppXmlCodec appXmlCodec =
      _overrides.appXmlCodec ?? _i5.AppXmlCodec();

  late final _i6.AppInfoProps appInfoProps =
      _overrides.appInfoProps ?? _i6.$AppInfoPropsFromConfig(config);

  late final _i7.AuthController authController =
      _overrides.authController ??
      _i7.AuthController(
        config.get<String>(
          'auth.jwt.secret',
          defaultValue: 'insecure-dev-secret',
        ),
      );

  late final _i8.EventsController eventsController =
      _overrides.eventsController ?? _i8.EventsController();

  late final _i9.UploadController uploadController =
      _overrides.uploadController ?? _i9.UploadController();

  late final _i10.TodoAuditListener todoAuditListener =
      _overrides.todoAuditListener ?? _i10.TodoAuditListener();

  late final _i11.HeartbeatJob heartbeatJob =
      _overrides.heartbeatJob ?? _i11.HeartbeatJob();

  late final _i12.LoggingMiddleware loggingMiddleware =
      _overrides.loggingMiddleware ?? _i12.LoggingMiddleware();

  late final _i13.InMemoryTodoRepository inMemoryTodoRepository =
      _overrides.inMemoryTodoRepository ?? _i13.InMemoryTodoRepository();

  late final _i14.ChatHandler chatHandler =
      _overrides.chatHandler ?? _i14.ChatHandler();

  late final _i15.InfoController infoController =
      _overrides.infoController ?? _i15.InfoController(appInfoProps);

  late final _i16.RepositoryHealthIndicator repositoryHealthIndicator =
      _overrides.repositoryHealthIndicator ??
      _i16.RepositoryHealthIndicator(inMemoryTodoRepository);

  late final _i17.TodoService todoService =
      _overrides.todoService ??
      _i17.TodoService(inMemoryTodoRepository, eventBus);

  late final _i18.TodoController todoController =
      _overrides.todoController ?? _i18.TodoController(todoService);

  /// Constructs every singleton in dependency order and runs @PostConstruct hooks.
  Future<void> initialize() async {
    errorAdvice;
    appAuth;
    appXmlCodec;
    appInfoProps;
    authController;
    eventsController;
    uploadController;
    todoAuditListener;
    heartbeatJob;
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
    this.appAuth,
    this.appXmlCodec,
    this.appInfoProps,
    this.requestAudit,
    this.authController,
    this.eventsController,
    this.uploadController,
    this.todoAuditListener,
    this.heartbeatJob,
    this.loggingMiddleware,
    this.inMemoryTodoRepository,
    this.chatHandler,
    this.infoController,
    this.auditController,
    this.repositoryHealthIndicator,
    this.todoService,
    this.todoController,
  });

  final _i3.ErrorAdvice? errorAdvice;

  final _i4.AppAuth? appAuth;

  final _i5.AppXmlCodec? appXmlCodec;

  final _i6.AppInfoProps? appInfoProps;

  final _i19.RequestAudit? requestAudit;

  final _i7.AuthController? authController;

  final _i8.EventsController? eventsController;

  final _i9.UploadController? uploadController;

  final _i10.TodoAuditListener? todoAuditListener;

  final _i11.HeartbeatJob? heartbeatJob;

  final _i12.LoggingMiddleware? loggingMiddleware;

  final _i13.InMemoryTodoRepository? inMemoryTodoRepository;

  final _i14.ChatHandler? chatHandler;

  final _i15.InfoController? infoController;

  final _i19.AuditController? auditController;

  final _i16.RepositoryHealthIndicator? repositoryHealthIndicator;

  final _i17.TodoService? todoService;

  final _i18.TodoController? todoController;
}

class DianaRequestScope {
  DianaRequestScope(this._ctx);

  final DianaContext _ctx;

  late final _i19.RequestAudit requestAudit =
      _ctx._overrides.requestAudit ?? _i19.RequestAudit();

  late final _i19.AuditController auditController =
      _ctx._overrides.auditController ?? _i19.AuditController(requestAudit);
}

/// The assembled application: context, server and lifecycle entrypoints.
class DianaApp {
  DianaApp(this.context, this.server);

  final DianaContext context;

  final _i2.DianaServer server;

  late final _i2.DianaScheduler scheduler = _i2.DianaScheduler()
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
  _i2.DianaConfig? config,
  DianaOverrides overrides = const DianaOverrides(),
}) => DianaContext(config ?? const _i2.DianaConfig.empty(), overrides);
_i20.FutureOr<_i2.DianaResponse?> _mapException(
  DianaContext ctx,
  Object e,
  _i2.DianaRequest req,
) {
  if (e is _i21.TodoNotFoundError)
    return ctx.errorAdvice.onTodoNotFound(e, req);
  return null;
}

/// Build-time OpenAPI 3 document (info patched from config at startup).
const String dianaOpenApiJson =
    '{"openapi":"3.0.3","info":{"title":"Diana application","version":"0.0.0"},"paths":{"/audit":{"get":{"operationId":"AuditController_get","tags":["AuditController"],"responses":{"200":{"description":"","content":{"application/json":{"schema":{}}}}}}},"/auth/login":{"post":{"operationId":"AuthController_login","tags":["AuthController"],"requestBody":{"required":true,"content":{"application/json":{"schema":{"\$ref":"#/components/schemas/LoginRequest"}}}},"responses":{"200":{"description":"","content":{"application/json":{"schema":{}}}}}}},"/auth/me":{"get":{"operationId":"AuthController_me","tags":["AuthController"],"security":[{"bearerAuth":[]}],"responses":{"200":{"description":"","content":{"application/json":{"schema":{}}}}}}},"/events/ticks":{"get":{"operationId":"EventsController_ticks","tags":["EventsController"],"responses":{"200":{"description":""}}}},"/events/todos":{"get":{"operationId":"EventsController_todoFeed","tags":["EventsController"],"responses":{"200":{"description":""}}}},"/info":{"get":{"operationId":"InfoController_get","tags":["InfoController"],"responses":{"200":{"description":"","content":{"application/json":{"schema":{}}}}}}},"/todos":{"get":{"operationId":"TodoController_list","tags":["TodoController"],"parameters":[{"name":"limit","in":"query","required":false,"schema":{"type":"integer","default":"20"}}],"responses":{"200":{"description":"","content":{"application/json":{"schema":{"type":"array","items":{}}}}}}},"post":{"operationId":"TodoController_create","tags":["TodoController"],"requestBody":{"required":true,"content":{"application/json":{"schema":{"\$ref":"#/components/schemas/CreateTodoRequest"}}}},"responses":{"201":{"description":"","content":{"application/json":{"schema":{}}}}}}},"/todos/xml":{"post":{"operationId":"TodoController_createFromXml","tags":["TodoController"],"requestBody":{"required":true,"content":{"application/xml":{"schema":{"\$ref":"#/components/schemas/CreateTodoRequest"}}}},"responses":{"201":{"description":"","content":{"application/xml":{"schema":{}},"application/json":{"schema":{}}}}}}},"/todos/{id}":{"get":{"operationId":"TodoController_getById","tags":["TodoController"],"parameters":[{"name":"id","in":"path","required":true,"schema":{"type":"integer"}}],"responses":{"200":{"description":"","content":{"application/json":{"schema":{}}}}}},"delete":{"operationId":"TodoController_remove","tags":["TodoController"],"security":[{"bearerAuth":[]}],"parameters":[{"name":"id","in":"path","required":true,"schema":{"type":"integer"}}],"responses":{"204":{"description":""}}}},"/uploads":{"post":{"operationId":"UploadController_upload","tags":["UploadController"],"requestBody":{"required":true,"content":{"multipart/form-data":{"schema":{}}}},"responses":{"201":{"description":"","content":{"application/json":{"schema":{}}}}}}},"/uploads/echo":{"post":{"operationId":"UploadController_echo","tags":["UploadController"],"requestBody":{"required":true,"content":{"text/plain":{"schema":{"type":"string"}}}},"responses":{"200":{"description":"","content":{"text/plain":{"schema":{"type":"string"}}}}}}}},"components":{"schemas":{"CreateTodoRequest":{"type":"object","properties":{"priority":{"type":"integer","minimum":1,"maximum":5},"title":{"type":"string","maxLength":120,"minLength":1}},"required":["title"]},"LoginRequest":{"type":"object","properties":{"password":{"type":"string","minLength":1},"username":{"type":"string","minLength":1}},"required":["password","username"]}},"securitySchemes":{"bearerAuth":{"type":"http","scheme":"bearer"}}}}';
Future<DianaApp> buildDianaApp({
  _i2.DianaConfig? config,
  DianaOverrides overrides = const DianaOverrides(),
}) async {
  final cfg = config ?? await _i2.DianaConfig.load('application.yaml');
  final ctx = DianaContext(cfg, overrides);
  final server = _i2.DianaServer(
    config: cfg,
    globalMiddleware: [ctx.appAuth, ctx.loggingMiddleware],
    bodyCodecs: [ctx.appXmlCodec],
    exceptionMapper: (e, st, req) => _mapException(ctx, e, req),
  );
  server.register(_i2.HttpMethod.get, '/audit', (req) {
    final scope = DianaRequestScope(ctx);
    return _i19.$diana$AuditController$get(scope.auditController, req);
  });
  server.register(
    _i2.HttpMethod.post,
    '/auth/login',
    (req) => _i7.$diana$AuthController$login(ctx.authController, req),
  );
  server.register(
    _i2.HttpMethod.get,
    '/auth/me',
    (req) => _i7.$diana$AuthController$me(ctx.authController, req),
    middleware: [const _i22.SecuredGuard()],
  );
  server.register(
    _i2.HttpMethod.get,
    '/events/ticks',
    (req) => _i8.$diana$EventsController$ticks(ctx.eventsController, req),
  );
  server.register(
    _i2.HttpMethod.get,
    '/events/todos',
    (req) => _i8.$diana$EventsController$todoFeed(ctx.eventsController, req),
  );
  server.register(
    _i2.HttpMethod.get,
    '/info',
    (req) => _i15.$diana$InfoController$get(ctx.infoController, req),
    cors: _i2.CorsPolicy(
      allowedOrigins: ['https://dashboard.example'],
      allowedHeaders: ['*'],
      maxAgeSeconds: 3600,
    ),
  );
  server.register(
    _i2.HttpMethod.get,
    '/todos',
    (req) => _i18.$diana$TodoController$list(ctx.todoController, req),
  );
  server.register(
    _i2.HttpMethod.get,
    '/todos/:id',
    (req) => _i18.$diana$TodoController$getById(ctx.todoController, req),
  );
  server.register(
    _i2.HttpMethod.post,
    '/todos',
    (req) => _i18.$diana$TodoController$create(ctx.todoController, req),
  );
  server.register(
    _i2.HttpMethod.post,
    '/todos/xml',
    (req) => _i18.$diana$TodoController$createFromXml(ctx.todoController, req),
  );
  server.register(
    _i2.HttpMethod.delete,
    '/todos/:id',
    (req) => _i18.$diana$TodoController$remove(ctx.todoController, req),
    middleware: [
      const _i22.RolesGuard(['admin']),
    ],
  );
  server.register(
    _i2.HttpMethod.post,
    '/uploads',
    (req) => _i9.$diana$UploadController$upload(ctx.uploadController, req),
  );
  server.register(
    _i2.HttpMethod.post,
    '/uploads/echo',
    (req) => _i9.$diana$UploadController$echo(ctx.uploadController, req),
  );
  if (cfg.get<bool>('management.enabled', defaultValue: false)) {
    server.register(
      _i2.HttpMethod.get,
      '/actuator/health',
      _i2.healthEndpointHandler([ctx.repositoryHealthIndicator]),
    );
    server.register(
      _i2.HttpMethod.get,
      '/actuator/health/liveness',
      _i2.livenessEndpointHandler(),
    );
    server.register(
      _i2.HttpMethod.get,
      '/actuator/health/readiness',
      _i2.readinessEndpointHandler([ctx.repositoryHealthIndicator]),
    );
    server.register(
      _i2.HttpMethod.get,
      '/actuator/info',
      _i2.infoEndpointHandler(cfg),
    );
  }

  if (cfg.get<bool>('server.openapi.enabled', defaultValue: false)) {
    final openApiBody = _i2.patchOpenApiInfo(dianaOpenApiJson, cfg);
    server.register(
      _i2.HttpMethod.get,
      '/openapi.json',
      (req) => _i2.DianaResponse(
        statusCode: 200,
        bodyText: openApiBody,
        mimeType: 'application/json',
      ),
    );
  }

  server.registerWebSocket(
    '/ws/chat/:room',
    () => ctx.chatHandler,
    middleware: [ctx.appAuth, const _i22.SecuredGuard()],
  );
  return DianaApp(ctx, server);
}

Future<_i2.DianaServer> buildDianaServer({
  _i2.DianaConfig? config,
  DianaOverrides overrides = const DianaOverrides(),
}) async {
  final app = await buildDianaApp(config: config, overrides: overrides);
  return app.server;
}

Future<void> runDiana({
  _i2.DianaConfig? config,
  DianaOverrides overrides = const DianaOverrides(),
}) => _i2.DianaRuntime.run(() async {
  final app = await buildDianaApp(config: config, overrides: overrides);
  return _i2.DianaRunnable(
    server: app.server,
    initialize: app.initialize,
    dispose: app.dispose,
    eventBus: app.context.eventBus,
  );
});
