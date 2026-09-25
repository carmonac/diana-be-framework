// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import

// ignore_for_file: no_leading_underscores_for_library_prefixes

import 'dart:async' as _i12;

import 'package:blog_api/caching/app_cache_store.dart' as _i3;
import 'package:blog_api/controllers/comment_controller.dart' as _i9;
import 'package:blog_api/controllers/post_controller.dart' as _i11;
import 'package:blog_api/db/db_health.dart' as _i4;
import 'package:blog_api/db/sqlite_connector.dart' as _i5;
import 'package:blog_api/dto/comment.dart' as _i15;
import 'package:blog_api/dto/post.dart' as _i13;
import 'package:blog_api/observability/app_observability.dart' as _i6;
import 'package:blog_api/repositories/comment_repository.dart' as _i7;
import 'package:blog_api/repositories/post_repository.dart' as _i8;
import 'package:blog_api/services/blog_service.dart' as _i10;
import 'package:diana/diana.dart' as _i1;
import 'package:diana_data/diana_data.dart' as _i2;
import 'package:diana_data/src/database.dart' as _i14;
import 'package:diana_observability/diana_observability.dart' as _i16;

class DianaContext {
  DianaContext(this.config, [this._overrides = const DianaOverrides()]);

  final _i1.DianaConfig config;

  final DianaOverrides _overrides;

  late final _i2.Database database = _i2.Database(
    sqliteConnector,
    config,
    observer: appObservability,
  );

  late final _i3.AppCacheStore appCacheStore =
      _overrides.appCacheStore ?? _i3.AppCacheStore();

  late final _i4.DbHealth dbHealth =
      _overrides.dbHealth ?? _i4.DbHealth(database);

  late final _i5.SqliteConnector sqliteConnector =
      _overrides.sqliteConnector ?? _i5.SqliteConnector();

  late final _i6.AppObservability appObservability =
      _overrides.appObservability ??
      _i6.AppObservability(
        config.get<String>('observability.tracing.endpoint', defaultValue: ''),
      );

  late final _i7.CommentRepository commentRepository =
      _overrides.commentRepository ?? $Repo$CommentRepository(database);

  late final _i8.PostRepository postRepository =
      _overrides.postRepository ?? _i8.PostRepository(database);

  late final _i9.CommentController commentController =
      _overrides.commentController ?? _i9.CommentController(commentRepository);

  late final _i10.BlogService blogService =
      _overrides.blogService ??
      $Aspect$BlogService(
        appObservability,
        appCacheStore,
        database,
        postRepository,
      );

  late final _i11.PostController postController =
      _overrides.postController ?? _i11.PostController(blogService);

  /// Constructs every singleton in dependency order and runs @PostConstruct hooks.
  Future<void> initialize() async {
    await database.open();
    await database.migrate();
    appCacheStore;
    dbHealth;
    sqliteConnector;
    appObservability;
    commentRepository;
    postRepository;
    commentController;
    blogService;
    postController;
  }

  /// Runs @PreDestroy hooks in reverse dependency order; call after initialize().
  Future<void> dispose() async {
    appObservability.shutdown();
    await database.close();
  }
}

/// Per-provider overrides for tests: a non-null field replaces the real provider everywhere it is injected.
class DianaOverrides {
  const DianaOverrides({
    this.appCacheStore,
    this.dbHealth,
    this.sqliteConnector,
    this.appObservability,
    this.commentRepository,
    this.postRepository,
    this.commentController,
    this.blogService,
    this.postController,
  });

  final _i3.AppCacheStore? appCacheStore;

  final _i4.DbHealth? dbHealth;

  final _i5.SqliteConnector? sqliteConnector;

  final _i6.AppObservability? appObservability;

  final _i7.CommentRepository? commentRepository;

  final _i8.PostRepository? postRepository;

  final _i9.CommentController? commentController;

  final _i10.BlogService? blogService;

  final _i11.PostController? postController;
}

class $Aspect$BlogService extends _i10.BlogService {
  $Aspect$BlogService(
    this._observer,
    this._cacheStore,
    this._db,
    _i8.PostRepository posts,
  ) : super(posts);

  final _i1.DianaObserver? _observer;

  final _i1.DianaCacheStore _cacheStore;

  final _i2.Database _db;

  static const _spec$totalPosts = _i1.CacheSpec(
    method: 'BlogService.totalPosts',
    ttl: Duration(seconds: 60),
    maxEntries: 1024,
  );

  final _retry$publishFlaky = _i1.RetryPolicy(
    maxAttempts: 3,
    backoff: const Duration(milliseconds: 10),
    retryWhen: (e) => e is _i10.TransientDbFailure,
  );

  final _breaker$unstable = _i1.CircuitBreakerPolicy(
    failureThreshold: 2,
    resetTimeout: const Duration(milliseconds: 60000),
  );

  @override
  _i12.Future<int> totalPosts() => _i1.runTimed(
    _observer,
    'BlogService.totalPosts',
    () => _cacheStore.run(_spec$totalPosts, [], () => super.totalPosts()),
  );

  @override
  _i12.Future<_i13.Article> publishFlaky(_i13.CreatePost post) =>
      _retry$publishFlaky.run(
        () => _db.runTransactional(() => super.publishFlaky(post)),
      );

  @override
  _i12.Future<void> unstable() => _breaker$unstable.run(() => super.unstable());

  @override
  _i12.Future<List<_i13.Article>> publishPair(
    _i13.CreatePost first,
    _i13.CreatePost second,
  ) => _db.runTransactional(() => super.publishPair(first, second));

  @override
  _i12.Future<void> publishThenFail(_i13.CreatePost post) =>
      _db.runTransactional(() => super.publishThenFail(post));
}

class $Repo$CommentRepository extends _i7.CommentRepository {
  $Repo$CommentRepository(_i14.Database db) : super(db);

  @override
  Future<List<_i15.Comment>> findAll() async => [
    for (final row in await db.select(db.table('comments')))
      _i15.$CommentFromJson(row),
  ];

  @override
  Future<_i15.Comment?> findById(Object id) async {
    final rows = await db.select(
      db.table('comments').where('id', '=', id).limit(1),
    );
    return rows.isEmpty ? null : _i15.$CommentFromJson(rows.first);
  }

  @override
  Future<void> save(_i15.Comment entity) => db.insert(
    db
        .table('comments')
        .insert(_i15.$CommentToJson(entity)..removeWhere((k, v) => v == null)),
  );

  @override
  Future<void> deleteById(Object id) =>
      db.delete(db.table('comments').where('id', '=', id).delete());

  @override
  Future<List<_i15.Comment>> findByPostId(int postId) async => [
    for (final row in await db.select(
      db.table('comments').where('post_id', '=', postId),
    ))
      _i15.$CommentFromJson(row),
  ];

  @override
  Future<_i15.Comment?> findFirstByPostIdAndAuthor(
    int postId,
    String author,
  ) async {
    final rows = await db.select(
      db
          .table('comments')
          .where('post_id', '=', postId)
          .where('author', '=', author)
          .limit(1),
    );
    return rows.isEmpty ? null : _i15.$CommentFromJson(rows.first);
  }

  @override
  Future<int> countByPostId(int postId) =>
      runCount(db.table('comments').where('post_id', '=', postId));

  @override
  Future<bool> existsByAuthor(String author) =>
      runExists(db.table('comments').where('author', '=', author));

  @override
  Future<void> deleteByPostId(int postId) =>
      db.delete(db.table('comments').where('post_id', '=', postId).delete());

  @override
  Future<List<_i15.Comment>> findByBodyContainsOrderByIdDesc(
    String fragment,
  ) async => [
    for (final row in await db.select(
      db
          .table('comments')
          .where('body', 'like', '%$fragment%')
          .orderBy('id', 'desc'),
    ))
      _i15.$CommentFromJson(row),
  ];

  @override
  Future<List<_i15.Comment>> findByIdBetween(int low, int high) async => [
    for (final row in await db.select(
      db.table('comments').whereBetween('id', [low, high]),
    ))
      _i15.$CommentFromJson(row),
  ];

  @override
  Future<List<_i15.Comment>> findByAuthorIn(List<String> authors) async => [
    for (final row in await db.select(
      db.table('comments').whereIn('author', authors),
    ))
      _i15.$CommentFromJson(row),
  ];

  @override
  Future<List<_i15.Comment>> findByAuthorOrBody(
    String author,
    String body,
  ) async => [
    for (final row in await db.select(
      db
          .table('comments')
          .where('author', '=', author)
          .orWhere('body', '=', body),
    ))
      _i15.$CommentFromJson(row),
  ];

  @override
  Future<List<_i15.Comment>> findByBodyIsNull() async => [
    for (final row in await db.select(db.table('comments').whereNull('body')))
      _i15.$CommentFromJson(row),
  ];

  @override
  Future<List<_i15.Comment>> findByPostIdNot(int postId) async => [
    for (final row in await db.select(
      db.table('comments').where('post_id', '<>', postId),
    ))
      _i15.$CommentFromJson(row),
  ];

  @override
  Future<List<_i15.Comment>> findByAuthorStartsWithOrderByAuthorAscIdDesc(
    String prefix,
  ) async => [
    for (final row in await db.select(
      db
          .table('comments')
          .where('author', 'like', '$prefix%')
          .orderBy('author', 'asc')
          .orderBy('id', 'desc'),
    ))
      _i15.$CommentFromJson(row),
  ];

  @override
  Future<List<_i15.Comment>> findByIdGreaterThanEqual(int id) async => [
    for (final row in await db.select(
      db.table('comments').where('id', '>=', id),
    ))
      _i15.$CommentFromJson(row),
  ];
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
    '{"openapi":"3.0.3","info":{"title":"Diana application","version":"0.0.0"},"paths":{"/comments":{"get":{"operationId":"CommentController_list","tags":["CommentController"],"responses":{"200":{"description":"","content":{"application/json":{"schema":{"type":"array","items":{"\$ref":"#/components/schemas/Comment"}}}}}}},"post":{"operationId":"CommentController_create","tags":["CommentController"],"requestBody":{"required":true,"content":{"application/json":{"schema":{"\$ref":"#/components/schemas/Comment"}}}},"responses":{"201":{"description":""}}}},"/posts":{"get":{"operationId":"PostController_list","tags":["PostController"],"responses":{"200":{"description":"","content":{"application/json":{"schema":{"type":"array","items":{"\$ref":"#/components/schemas/Article"}}}}}}},"post":{"operationId":"PostController_publishPair","tags":["PostController"],"requestBody":{"required":true,"content":{"application/json":{"schema":{"\$ref":"#/components/schemas/PostPair"}}}},"responses":{"201":{"description":"","content":{"application/json":{"schema":{"type":"array","items":{"\$ref":"#/components/schemas/Article"}}}}}}}},"/posts/fail":{"post":{"operationId":"PostController_fail","tags":["PostController"],"requestBody":{"required":true,"content":{"application/json":{"schema":{"\$ref":"#/components/schemas/CreatePost"}}}},"responses":{"204":{"description":""}}}},"/posts/flaky":{"post":{"operationId":"PostController_flaky","tags":["PostController"],"requestBody":{"required":true,"content":{"application/json":{"schema":{"\$ref":"#/components/schemas/CreatePost"}}}},"responses":{"201":{"description":"","content":{"application/json":{"schema":{"\$ref":"#/components/schemas/Article"}}}}}}},"/posts/stats/total":{"get":{"operationId":"PostController_stats","tags":["PostController"],"responses":{"200":{"description":"","content":{"application/json":{"schema":{"\$ref":"#/components/schemas/Stats"}}}}}}},"/posts/unstable/ping":{"get":{"operationId":"PostController_unstable","tags":["PostController"],"responses":{"204":{"description":""}}}},"/posts/{id}":{"get":{"operationId":"PostController_getById","tags":["PostController"],"parameters":[{"name":"id","in":"path","required":true,"schema":{"type":"integer"}}],"responses":{"200":{"description":"","content":{"application/json":{"schema":{"\$ref":"#/components/schemas/Article"}}}}}}}},"components":{"schemas":{"Article":{"type":"object","properties":{"body":{"type":"string"},"id":{"type":"integer"},"title":{"type":"string"}},"required":["body","id","title"]},"Comment":{"type":"object","properties":{"author":{"type":"string"},"body":{"type":"string"},"id":{"type":"integer"},"post_id":{"type":"integer"}},"required":["author","body","post_id"]},"CreatePost":{"type":"object","properties":{"body":{"type":"string","minLength":1},"title":{"type":"string","minLength":1}},"required":["body","title"]},"PostPair":{"type":"object","properties":{"first":{"\$ref":"#/components/schemas/CreatePost"},"second":{"\$ref":"#/components/schemas/CreatePost"}},"required":["first","second"]},"Stats":{"type":"object","properties":{"total":{"type":"integer"}},"required":["total"]}}}}';
Future<DianaApp> buildDianaApp({
  _i1.DianaConfig? config,
  DianaOverrides overrides = const DianaOverrides(),
}) async {
  final cfg = config ?? await _i1.DianaConfig.load('application.yaml');
  final ctx = DianaContext(cfg, overrides);
  final server = _i1.DianaServer(config: cfg, observer: ctx.appObservability);
  server.register(
    _i1.HttpMethod.get,
    '/comments',
    (req) => _i9.$diana$CommentController$list(ctx.commentController, req),
  );
  server.register(
    _i1.HttpMethod.post,
    '/comments',
    (req) => _i9.$diana$CommentController$create(ctx.commentController, req),
  );
  server.register(
    _i1.HttpMethod.get,
    '/posts',
    (req) => _i11.$diana$PostController$list(ctx.postController, req),
  );
  server.register(
    _i1.HttpMethod.get,
    '/posts/:id',
    (req) => _i11.$diana$PostController$getById(ctx.postController, req),
  );
  server.register(
    _i1.HttpMethod.post,
    '/posts',
    (req) => _i11.$diana$PostController$publishPair(ctx.postController, req),
  );
  server.register(
    _i1.HttpMethod.post,
    '/posts/fail',
    (req) => _i11.$diana$PostController$fail(ctx.postController, req),
  );
  server.register(
    _i1.HttpMethod.get,
    '/posts/stats/total',
    (req) => _i11.$diana$PostController$stats(ctx.postController, req),
  );
  server.register(
    _i1.HttpMethod.post,
    '/posts/flaky',
    (req) => _i11.$diana$PostController$flaky(ctx.postController, req),
  );
  server.register(
    _i1.HttpMethod.get,
    '/posts/unstable/ping',
    (req) => _i11.$diana$PostController$unstable(ctx.postController, req),
  );
  if (cfg.get<bool>('management.enabled', defaultValue: false)) {
    server.register(
      _i1.HttpMethod.get,
      '/actuator/health',
      _i1.healthEndpointHandler([ctx.dbHealth]),
    );
    server.register(
      _i1.HttpMethod.get,
      '/actuator/health/liveness',
      _i1.livenessEndpointHandler(),
    );
    server.register(
      _i1.HttpMethod.get,
      '/actuator/health/readiness',
      _i1.readinessEndpointHandler([ctx.dbHealth]),
    );
    server.register(
      _i1.HttpMethod.get,
      '/actuator/info',
      _i1.infoEndpointHandler(cfg),
    );
    server.register(
      _i1.HttpMethod.get,
      '/actuator/metrics',
      _i16.metricsEndpointHandler(ctx.appObservability),
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
