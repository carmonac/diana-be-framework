// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import

// ignore_for_file: no_leading_underscores_for_library_prefixes

import 'package:diana/diana.dart' as _i1;
import 'package:diana_grpc/diana_grpc.dart' as _i4;
import 'package:greeter_grpc/controllers/hello_controller.dart' as _i2;
import 'package:greeter_grpc/services/greeter_service.dart' as _i3;

class DianaContext {
  DianaContext(this.config, [this._overrides = const DianaOverrides()]);

  final _i1.DianaConfig config;

  final DianaOverrides _overrides;

  late final _i2.HelloController helloController =
      _overrides.helloController ?? _i2.HelloController();

  late final _i3.GreeterService greeterService =
      _overrides.greeterService ??
      _i3.GreeterService(
        config.get<String>('app.greeting', defaultValue: 'Hello'),
      );

  /// Constructs every singleton in dependency order and runs @PostConstruct hooks.
  Future<void> initialize() async {
    helloController;
    greeterService;
  }

  /// Runs @PreDestroy hooks in reverse dependency order; call after initialize().
  Future<void> dispose() async {}
}

/// Per-provider overrides for tests: a non-null field replaces the real provider everywhere it is injected.
class DianaOverrides {
  const DianaOverrides({this.helloController, this.greeterService});

  final _i2.HelloController? helloController;

  final _i3.GreeterService? greeterService;
}

/// The assembled application: context, server and lifecycle entrypoints.
class DianaApp {
  DianaApp(this.context, this.server, this.grpcServer);

  final DianaContext context;

  final _i1.DianaServer server;

  final _i4.DianaGrpcServer grpcServer;

  Future<void> initialize() async {
    await context.initialize();
    await grpcServer.serve();
  }

  Future<void> dispose() async {
    await grpcServer.shutdown();
    await context.dispose();
  }
}

DianaContext buildDianaContext({
  _i1.DianaConfig? config,
  DianaOverrides overrides = const DianaOverrides(),
}) => DianaContext(config ?? const _i1.DianaConfig.empty(), overrides);

/// Build-time OpenAPI 3 document (info patched from config at startup).
const String dianaOpenApiJson =
    '{"openapi":"3.0.3","info":{"title":"Diana application","version":"0.0.0"},"paths":{"/hello":{"get":{"operationId":"HelloController_hello","tags":["HelloController"],"responses":{"200":{"description":"","content":{"application/json":{"schema":{}}}}}}}}}';
Future<DianaApp> buildDianaApp({
  _i1.DianaConfig? config,
  DianaOverrides overrides = const DianaOverrides(),
}) async {
  final cfg = config ?? await _i1.DianaConfig.load('application.yaml');
  final ctx = DianaContext(cfg, overrides);
  final server = _i1.DianaServer(config: cfg);
  server.register(
    _i1.HttpMethod.get,
    '/hello',
    (req) => _i2.$diana$HelloController$hello(ctx.helloController, req),
  );
  if (cfg.get<bool>('management.enabled', defaultValue: false)) {
    server.register(
      _i1.HttpMethod.get,
      '/actuator/health',
      _i1.healthEndpointHandler([]),
    );
    server.register(
      _i1.HttpMethod.get,
      '/actuator/health/liveness',
      _i1.livenessEndpointHandler(),
    );
    server.register(
      _i1.HttpMethod.get,
      '/actuator/health/readiness',
      _i1.readinessEndpointHandler([]),
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

  final grpcServer = _i4.DianaGrpcServer(cfg, services: [ctx.greeterService]);
  return DianaApp(ctx, server, grpcServer);
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
