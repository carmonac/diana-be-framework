// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import

// ignore_for_file: no_leading_underscores_for_library_prefixes
import 'dart:async' as _i8;

import 'package:blog_api/controllers/post_controller.dart' as _i7;
import 'package:blog_api/db/db_health.dart' as _i3;
import 'package:blog_api/db/sqlite_connector.dart' as _i4;
import 'package:blog_api/dto/post.dart' as _i9;
import 'package:blog_api/repositories/post_repository.dart' as _i5;
import 'package:blog_api/services/blog_service.dart' as _i6;
import 'package:diana/diana.dart' as _i1;
import 'package:diana_data/diana_data.dart' as _i2;

class DianaContext {
  DianaContext(this.config, [this._overrides = const DianaOverrides()]);

  final _i1.DianaConfig config;

  final DianaOverrides _overrides;

  late final _i2.Database database = _i2.Database(sqliteConnector, config);

  late final _i3.DbHealth dbHealth =
      _overrides.dbHealth ?? _i3.DbHealth(database);

  late final _i4.SqliteConnector sqliteConnector =
      _overrides.sqliteConnector ?? _i4.SqliteConnector();

  late final _i5.PostRepository postRepository =
      _overrides.postRepository ?? _i5.PostRepository(database);

  late final _i6.BlogService blogService =
      _overrides.blogService ?? $Tx$BlogService(database, postRepository);

  late final _i7.PostController postController =
      _overrides.postController ?? _i7.PostController(blogService);

  /// Constructs every singleton in dependency order and runs @PostConstruct hooks.
  Future<void> initialize() async {
    await database.open();
    await database.migrate();
    dbHealth;
    sqliteConnector;
    postRepository;
    blogService;
    postController;
  }

  /// Runs @PreDestroy hooks in reverse dependency order; call after initialize().
  Future<void> dispose() async {
    await database.close();
  }
}

/// Per-provider overrides for tests: a non-null field replaces the real provider everywhere it is injected.
class DianaOverrides {
  const DianaOverrides({
    this.dbHealth,
    this.sqliteConnector,
    this.postRepository,
    this.blogService,
    this.postController,
  });

  final _i3.DbHealth? dbHealth;

  final _i4.SqliteConnector? sqliteConnector;

  final _i5.PostRepository? postRepository;

  final _i6.BlogService? blogService;

  final _i7.PostController? postController;
}

class $Tx$BlogService extends _i6.BlogService {
  $Tx$BlogService(this._db, _i5.PostRepository posts) : super(posts);

  final _i2.Database _db;

  @override
  _i8.Future<List<_i9.Article>> publishPair(
    _i9.CreatePost first,
    _i9.CreatePost second,
  ) => _db.runTransactional(() => super.publishPair(first, second));

  @override
  _i8.Future<void> publishThenFail(_i9.CreatePost post) =>
      _db.runTransactional(() => super.publishThenFail(post));
}

/// The assembled application: context, server and lifecycle entrypoints.
class DianaApp {
  DianaApp(this.context, this.server);

  final DianaContext context;

  final _i1.DianaServer server;

  Future<void> initialize() => context.initialize();

  Future<void> dispose() => context.dispose();
}

DianaContext buildDianaContext({
  _i1.DianaConfig? config,
  DianaOverrides overrides = const DianaOverrides(),
}) => DianaContext(config ?? const _i1.DianaConfig.empty(), overrides);

/// Build-time OpenAPI 3 document (info patched from config at startup).
const String dianaOpenApiJson =
    '{"openapi":"3.0.3","info":{"title":"Diana application","version":"0.0.0"},"paths":{"/posts":{"get":{"operationId":"PostController_list","tags":["PostController"],"responses":{"200":{"description":"","content":{"application/json":{"schema":{"type":"array","items":{"\$ref":"#/components/schemas/Article"}}}}}}},"post":{"operationId":"PostController_publishPair","tags":["PostController"],"requestBody":{"required":true,"content":{"application/json":{"schema":{"\$ref":"#/components/schemas/PostPair"}}}},"responses":{"201":{"description":"","content":{"application/json":{"schema":{"type":"array","items":{"\$ref":"#/components/schemas/Article"}}}}}}}},"/posts/fail":{"post":{"operationId":"PostController_fail","tags":["PostController"],"requestBody":{"required":true,"content":{"application/json":{"schema":{"\$ref":"#/components/schemas/CreatePost"}}}},"responses":{"204":{"description":""}}}},"/posts/{id}":{"get":{"operationId":"PostController_getById","tags":["PostController"],"parameters":[{"name":"id","in":"path","required":true,"schema":{"type":"integer"}}],"responses":{"200":{"description":"","content":{"application/json":{"schema":{"\$ref":"#/components/schemas/Article"}}}}}}}},"components":{"schemas":{"Article":{"type":"object","properties":{"body":{"type":"string"},"id":{"type":"integer"},"title":{"type":"string"}},"required":["body","id","title"]},"CreatePost":{"type":"object","properties":{"body":{"type":"string","minLength":1},"title":{"type":"string","minLength":1}},"required":["body","title"]},"PostPair":{"type":"object","properties":{"first":{"\$ref":"#/components/schemas/CreatePost"},"second":{"\$ref":"#/components/schemas/CreatePost"}},"required":["first","second"]}}}}';
Future<DianaApp> buildDianaApp({
  _i1.DianaConfig? config,
  DianaOverrides overrides = const DianaOverrides(),
}) async {
  final cfg = config ?? await _i1.DianaConfig.load('application.yaml');
  final ctx = DianaContext(cfg, overrides);
  final server = _i1.DianaServer(config: cfg);
  server.register(
    _i1.HttpMethod.get,
    '/posts',
    (req) => _i7.$diana$PostController$list(ctx.postController, req),
  );
  server.register(
    _i1.HttpMethod.get,
    '/posts/:id',
    (req) => _i7.$diana$PostController$getById(ctx.postController, req),
  );
  server.register(
    _i1.HttpMethod.post,
    '/posts',
    (req) => _i7.$diana$PostController$publishPair(ctx.postController, req),
  );
  server.register(
    _i1.HttpMethod.post,
    '/posts/fail',
    (req) => _i7.$diana$PostController$fail(ctx.postController, req),
  );
  if (cfg.get<bool>('management.enabled', defaultValue: false)) {
    server.register(
      _i1.HttpMethod.get,
      '/actuator/health',
      _i1.healthEndpointHandler([ctx.dbHealth]),
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
