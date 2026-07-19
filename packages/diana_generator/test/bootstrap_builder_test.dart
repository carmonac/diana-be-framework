import 'package:build_test/build_test.dart';
import 'package:diana_generator/src/bootstrap_builder.dart';
import 'package:diana_generator/src/common.dart';
import 'package:diana_generator/src/metadata_builder.dart';
import 'package:test/test.dart';

import 'util/package_assets.dart';

/// Runs metadata + bootstrap over in-memory sources and returns the
/// generated `.diana_app.dart` content.
Future<void> expectBootstrap(
  Map<String, String> sources, {
  required Object output,
  List<String> expectedErrors = const [],
}) async {
  final logs = <String>[];
  await testBuilders(
    [const DianaMetadataBuilder(), const DianaBootstrapBuilder()],
    {
      ...await dianaTestDeps(),
      for (final e in sources.entries) 'a|${e.key}': e.value,
    },
    isInput: (assetId) => assetId.startsWith('a|'),
    outputs: expectedErrors.isEmpty
        ? {
            'a|lib/app.diana_app.dart': decodedMatches(output),
            // The metadata builder skips libraries without Diana annotations
            // (quick-check regex), so only those sources produce a summary.
            for (final e in sources.entries)
              if (dianaAnnotationPattern.hasMatch(e.value) ||
                  dianaApplicationPattern.hasMatch(e.value))
                'a|${e.key.replaceFirst('.dart', '.diana.json')}': anything,
          }
        : null,
    onLog: (record) {
      if (record.level.name == 'SEVERE') logs.add(record.message);
    },
  );
  for (final expected in expectedErrors) {
    expect(logs.join('\n'), contains(expected));
  }
}

const app = '''
import 'package:diana_annotation/diana_annotation.dart';

@DianaApplication()
class App {}
''';

void main() {
  test('emits a wired DianaContext for a service chain', () async {
    await expectBootstrap(
      {
        'lib/app.dart': app,
        'lib/service.dart': '''
import 'package:diana_annotation/diana_annotation.dart';

abstract interface class Repo {
  int count();
}

@Repository()
class MemRepo implements Repo {
  @override
  int count() => 0;
}

@Service()
class CounterService {
  CounterService(this.repo);
  final Repo repo;
}
''',
      },
      output: allOf(
        contains('late final _i2.MemRepo memRepo = _overrides.memRepo ?? _i2.MemRepo();'),
        contains('late final _i2.CounterService counterService ='),
        contains('_i2.CounterService(memRepo)'),
        contains('DianaContext buildDianaContext'),
      ),
    );
  });

  test('emits transient providers as factory methods', () async {
    await expectBootstrap(
      {
        'lib/app.dart': app,
        'lib/service.dart': '''
import 'package:diana_annotation/diana_annotation.dart';

@Component(scope: Scope.transient)
class UuidFactory {}

@Service()
class Ids {
  Ids(this.factory);
  final UuidFactory factory;
}
''',
      },
      output: allOf(
        contains('_i2.UuidFactory createUuidFactory() =>'),
        contains('_overrides.uuidFactory ?? _i2.UuidFactory()'),
        contains('_i2.Ids(createUuidFactory())'),
      ),
    );
  });

  test('surfaces graph errors through severe logs', () async {
    await expectBootstrap(
      {
        'lib/app.dart': app,
        'lib/service.dart': '''
import 'package:diana_annotation/diana_annotation.dart';

@Service()
class NeedsClock {
  NeedsClock(this.clock);
  final Duration clock;
}
''',
      },
      output: '',
      expectedErrors: [
        'No provider found for Duration — required by constructor parameter '
            '"clock" of NeedsClock (package:a/service.dart).',
      ],
    );
  });

  test('sorts global middleware by order and wires route middleware',
      () async {
    await expectBootstrap(
      {
        'lib/app.dart': app,
        'lib/web.dart': '''
import 'dart:async';

import 'package:diana/diana.dart';

@GlobalMiddleware(order: 5)
class SecondMiddleware implements Middleware {
  @override
  FutureOr<DianaResponse> handle(DianaRequest req, Next next) => next(req);
}

@GlobalMiddleware(order: -1)
class FirstMiddleware implements Middleware {
  @override
  FutureOr<DianaResponse> handle(DianaRequest req, Next next) => next(req);
}

@Component()
class RouteGuard implements Middleware {
  @override
  FutureOr<DianaResponse> handle(DianaRequest req, Next next) => next(req);
}

@RestController('/x')
@UseMiddleware([RouteGuard])
class XController {
  @Get()
  String hello() => 'hi';
}
''',
      },
      output: allOf(
        contains('globalMiddleware: [ctx.firstMiddleware, '
            'ctx.secondMiddleware]'),
        contains('middleware: [ctx.routeGuard]'),
      ),
    );
  });

  test('rejects @UseMiddleware types that are not injectable', () async {
    await expectBootstrap(
      {
        'lib/app.dart': app,
        'lib/web.dart': '''
import 'dart:async';

import 'package:diana/diana.dart';

class NotRegistered implements Middleware {
  @override
  FutureOr<DianaResponse> handle(DianaRequest req, Next next) => next(req);
}

@RestController('/x')
@UseMiddleware([NotRegistered])
class XController {
  @Get()
  String hello() => 'hi';
}
''',
      },
      output: '',
      expectedErrors: [
        'NotRegistered, referenced by @UseMiddleware on XController, is not '
            'an injectable class.',
      ],
    );
  });

  test('orders exception handlers by subtype specificity', () async {
    final logs = <String>[];
    String? generated;
    await testBuilders(
      [const DianaMetadataBuilder(), const DianaBootstrapBuilder()],
      {
        ...await dianaTestDeps(),
        'a|lib/app.dart': app,
        'a|lib/advice.dart': '''
import 'package:diana/diana.dart';

class BaseError implements Exception {}

class DerivedError extends BaseError {}

@ControllerAdvice()
class ErrorAdvice {
  @ExceptionHandler(BaseError)
  DianaResponse onBase(BaseError e) => DianaResponse.json(null);

  @ExceptionHandler(DerivedError)
  DianaResponse onDerived(DerivedError e, DianaRequest req) =>
      DianaResponse.json(null);
}
''',
      },
      isInput: (id) => id.startsWith('a|'),
      outputs: {
        'a|lib/app.diana.json': anything,
        'a|lib/advice.diana.json': anything,
        'a|lib/app.diana_app.dart': decodedMatches(predicate((String out) {
          generated = out;
          return true;
        })),
      },
      onLog: (r) {
        if (r.level.name == 'SEVERE') logs.add(r.message);
      },
    );
    expect(logs, isEmpty);
    final derived = generated!.indexOf(RegExp(r'is _i\d+\.DerivedError'));
    final base = generated!.indexOf(RegExp(r'is _i\d+\.BaseError'));
    expect(derived, isNot(-1));
    expect(base, isNot(-1));
    expect(derived, lessThan(base),
        reason: 'the more specific handler must be checked first');
    expect(generated, contains('ctx.errorAdvice.onDerived(e, req)'));
    expect(generated, contains('ctx.errorAdvice.onBase(e)'));
    expect(generated,
        contains('exceptionMapper: (e, st, req) => _mapException(ctx, e, req)'));
  });

  test('rejects handlers with mismatched signatures', () async {
    await expectBootstrap(
      {
        'lib/app.dart': app,
        'lib/advice.dart': '''
import 'package:diana/diana.dart';

class BoomError implements Exception {}

@ControllerAdvice()
class BadAdvice {
  @ExceptionHandler(BoomError)
  DianaResponse onBoom(String wrong) => DianaResponse.json(null);
}
''',
      },
      output: '',
      expectedErrors: [
        'Exception handler BadAdvice.onBoom must take (BoomError) or '
            '(BoomError, DianaRequest).',
      ],
    );
  });

  test('registers WebSocket endpoints for singleton and transient handlers',
      () async {
    await expectBootstrap(
      {
        'lib/app.dart': app,
        'lib/ws.dart': '''
import 'package:diana/diana.dart';

@WebSocketController('/ws/echo')
class EchoHandler extends BaseWebSocketHandler {}

@WebSocketController('/ws/chat', Scope.transient)
class ChatHandler extends BaseWebSocketHandler {
  ChatHandler(this.echo);
  final EchoHandler echo;
}
''',
      },
      output: allOf(
        contains("server.registerWebSocket('/ws/chat', "
            '() => ctx.createChatHandler());'),
        contains("server.registerWebSocket('/ws/echo', () => ctx.echoHandler);"),
      ),
    );
  });

  test('secures WebSocket handshakes with a guard interceptor', () async {
    await expectBootstrap(
      {
        'lib/app.dart': app,
        'lib/ws.dart': '''
import 'package:diana/diana.dart';

@WebSocketController('/ws/admin')
@RolesAllowed(['admin'])
class AdminHandler extends BaseWebSocketHandler {}
''',
      },
      output: matches(RegExp(
          r"registerWebSocket\(\s*'/ws/admin',[^;]*?"
          r"const (_i\d+\.)?RolesGuard\(\['admin'\]\)")),
    );
  });

  test('rejects @WebSocketController classes without the handler interface',
      () async {
    await expectBootstrap(
      {
        'lib/app.dart': app,
        'lib/ws.dart': '''
import 'package:diana/diana.dart';

@WebSocketController('/ws/echo')
class NotAHandler {}
''',
      },
      output: '',
      expectedErrors: [
        '@WebSocketController class NotAHandler (package:a/ws.dart) does '
            "not implement Diana's WebSocketHandler interface. Implement it, "
            'or extend BaseWebSocketHandler.',
      ],
    );
  });

  test('rejects duplicate WebSocket paths and request scope', () async {
    await expectBootstrap(
      {
        'lib/app.dart': app,
        'lib/ws.dart': '''
import 'package:diana/diana.dart';

@WebSocketController('/ws/echo')
class HandlerA extends BaseWebSocketHandler {}

@WebSocketController('/ws/echo')
class HandlerB extends BaseWebSocketHandler {}
''',
      },
      output: '',
      expectedErrors: [
        'Duplicate WebSocket path "/ws/echo": handled by both HandlerA and '
            'HandlerB.',
      ],
    );

    await expectBootstrap(
      {
        'lib/app.dart': app,
        'lib/ws.dart': '''
import 'package:diana/diana.dart';

@WebSocketController('/ws/echo', Scope.request)
class RequestHandler extends BaseWebSocketHandler {}
''',
      },
      output: '',
      expectedErrors: [
        '@WebSocketController class RequestHandler cannot be request-scoped; '
            'use Scope.singleton (shared handler) or Scope.transient '
            '(one handler per connection).',
      ],
    );
  });

  test('emits initialize/dispose with lifecycle hooks in topo order',
      () async {
    await expectBootstrap(
      {
        'lib/app.dart': app,
        'lib/service.dart': '''
import 'package:diana_annotation/diana_annotation.dart';

@Repository()
class Repo {
  @PostConstruct()
  Future<void> connect() async {}

  @PreDestroy()
  void disconnect() {}
}

@Service()
class Api {
  Api(this.repo);
  final Repo repo;

  @PostConstruct()
  void warm() {}
}
''',
      },
      output: allOf([
        contains('await repo.connect();'),
        contains('api.warm();'),
        contains('repo.disconnect();'),
        contains('class DianaOverrides'),
        contains('_overrides.repo ?? _i2.Repo()'),
        contains('class DianaApp'),
        contains('Future<DianaApp> buildDianaApp'),
        contains('DianaRuntime.run'),
      ]),
    );
  });

  test('rejects invalid lifecycle signatures and scopes', () async {
    await expectBootstrap(
      {
        'lib/app.dart': app,
        'lib/bad.dart': '''
import 'package:diana_annotation/diana_annotation.dart';

@Service()
class BadSignature {
  @PostConstruct()
  int setup(String arg) => 0;
}
''',
      },
      output: '',
      expectedErrors: [
        '@PostConstruct method BadSignature.setup must be a public instance '
            'method with no parameters returning void or Future<void>.',
      ],
    );

    await expectBootstrap(
      {
        'lib/app.dart': app,
        'lib/bad.dart': '''
import 'package:diana_annotation/diana_annotation.dart';

@Component(scope: Scope.transient)
class Ephemeral {
  @PreDestroy()
  void cleanup() {}
}
''',
      },
      output: '',
      expectedErrors: [
        '@PreDestroy on Ephemeral requires singleton scope; found transient.',
      ],
    );

    await expectBootstrap(
      {
        'lib/app.dart': app,
        'lib/bad.dart': '''
import 'package:diana_annotation/diana_annotation.dart';

@Service()
class Doubled {
  @PostConstruct()
  void a() {}

  @PostConstruct()
  void b() {}
}
''',
      },
      output: '',
      expectedErrors: [
        'Class Doubled declares multiple @PostConstruct methods; declare at '
            'most one.',
      ],
    );
  });

  test('supports custom methods via @HttpRoute', () async {
    await expectBootstrap(
      {
        'lib/app.dart': app,
        'lib/web.dart': '''
import 'package:diana_annotation/diana_annotation.dart';

@RestController('/health')
class HealthController {
  @HttpRoute('HEAD', '/status')
  void status() {}
}
''',
      },
      output: contains('HttpMethod.head'),
    );
  });

  test('rejects multiple @DianaApplication classes in one package', () async {
    await expectBootstrap(
      {
        'lib/app.dart': app,
        'lib/other.dart': '''
import 'package:diana_annotation/diana_annotation.dart';

@DianaApplication()
class OtherApp {}
''',
      },
      output: '',
      expectedErrors: [
        'Multiple @DianaApplication classes found: App (package:a/app.dart), '
            'OtherApp (package:a/other.dart). A package must declare exactly '
            'one application entrypoint.',
      ],
    );
  });

  test('injects @Value parameters from config', () async {
    await expectBootstrap(
      {
        'lib/app.dart': app,
        'lib/service.dart': '''
import 'package:diana_annotation/diana_annotation.dart';

@Service()
class Greeter {
  Greeter(@Value('app.greeting', defaultValue: 'hi') this.greeting);
  final String greeting;
}
''',
      },
      output: contains(
        "config.get<String>('app.greeting', defaultValue: 'hi')",
      ),
    );
  });


  test('wires BodyCodec singletons into DianaServer', () async {
    await expectBootstrap(
      {
        'lib/app.dart': app,
        'lib/codec.dart': '''
import 'package:diana/diana.dart';

@Component()
class AppXmlCodec implements BodyCodec {
  @override
  List<String> get mimeTypes => const ['application/xml'];

  @override
  Object? decode(String body) => null;

  @override
  String encode(Object? value) => '';
}
''',
      },
      output: contains('bodyCodecs: [ctx.appXmlCodec]'),
    );
  });

  test('rejects non-singleton body codecs', () async {
    await expectBootstrap(
      {
        'lib/app.dart': app,
        'lib/codec.dart': '''
import 'package:diana/diana.dart';

@Component(scope: Scope.transient)
class AppXmlCodec implements BodyCodec {
  @override
  List<String> get mimeTypes => const ['application/xml'];

  @override
  Object? decode(String body) => null;

  @override
  String encode(Object? value) => '';
}
''',
      },
      output: '',
      expectedErrors: [
        'AppXmlCodec implements BodyCodec but is transient-scoped; '
            'body codecs must be singletons.',
      ],
    );
  });

  test('wires @GrpcService classes into DianaApp.grpcServer', () async {
    await expectBootstrap(
      {
        'lib/app.dart': app,
        // Mimics protoc output: the base class lives in its own library and
        // imports grpc internally (user code never names grpc's Service,
        // which would clash with Diana's @Service annotation).
        'lib/greeter_base.dart': r'''
import 'package:grpc/grpc.dart';

class GreeterServiceBase extends Service {
  @override
  String get $name => 'greeter.Greeter';
}
''',
        'lib/svc.dart': '''
import 'package:diana_annotation/diana_annotation.dart';

import 'greeter_base.dart';

@GrpcService()
class GreeterService extends GreeterServiceBase {}
''',
      },
      output: allOf([
        contains('final grpcServer = '),
        contains('DianaGrpcServer(cfg, services: [ctx.greeterService])'),
        contains('await grpcServer.serve();'),
        contains('await grpcServer.shutdown();'),
      ]),
    );
  });

  test('rejects @GrpcService classes not extending grpc Service', () async {
    await expectBootstrap(
      {
        'lib/app.dart': app,
        'lib/svc.dart': '''
import 'package:diana_annotation/diana_annotation.dart';

@GrpcService()
class NotAService {}
''',
      },
      output: '',
      expectedErrors: [
        '@GrpcService class NotAService does not extend a grpc service '
            'base class. Extend your protoc-generated XServiceBase '
            '(package:grpc Service).',
      ],
    );
  });

  test('emits scheduler registrations with perIsolate only when annotated',
      () async {
    await expectBootstrap(
      {
        'lib/app.dart': app,
        'lib/jobs.dart': '''
import 'package:diana_annotation/diana_annotation.dart';

@Component()
class Jobs {
  @Scheduled(fixedDelay: 50)
  void leaderJob() {}

  @Scheduled(fixedRate: 100, perIsolate: true)
  void cacheRefresh() {}
}
''',
      },
      output: allOf([
        contains('..schedule(task: () async => context.jobs.leaderJob(), '
            'fixedDelayMs: 50)'),
        matches(RegExp(
            r'\.\.schedule\(\s*task: \(\) async => context\.jobs\.cacheRefresh\(\),'
            r'\s*fixedRateMs: 100,\s*perIsolate: true,?\s*\)')),
        contains('scheduler.start()'),
        contains('await scheduler.stop()'),
      ]),
    );
  });

  test('default scheduled tasks emit no perIsolate argument (byte identity)',
      () async {
    await expectBootstrap(
      {
        'lib/app.dart': app,
        'lib/jobs.dart': '''
import 'package:diana_annotation/diana_annotation.dart';

@Component()
class Jobs {
  @Scheduled(fixedDelay: 50)
  void beat() {}
}
''',
      },
      output: isNot(contains('perIsolate')),
    );
  });

  test('emits a cron schedule from @Scheduled(cron:)', () async {
    await expectBootstrap(
      {
        'lib/app.dart': app,
        'lib/jobs.dart': '''
import 'package:diana_annotation/diana_annotation.dart';

@Component()
class Jobs {
  @Scheduled(cron: '0 0 3 * * *')
  Future<void> nightly() async {}

  @Scheduled(cron: '@daily')
  Future<void> daily() async {}
}
''',
      },
      output: allOf([
        contains('..schedule(task: () async => context.jobs.nightly(), '
            "cron: '0 0 3 * * *')"),
        contains("cron: '@daily'"),
      ]),
    );
  });

  test('rejects a cron with the wrong field count', () async {
    await expectBootstrap(
      {
        'lib/app.dart': app,
        'lib/jobs.dart': '''
import 'package:diana_annotation/diana_annotation.dart';

@Component()
class Jobs {
  @Scheduled(cron: '0 0 3 * *')
  Future<void> nightly() async {}
}
''',
      },
      output: '',
      expectedErrors: [
        '@Scheduled cron on Jobs.nightly must have 6 fields (second minute '
            'hour day-of-month month day-of-week) or be a macro like @daily; '
            'got 5.',
      ],
    );
  });

  test('rejects combining cron with fixedRate', () async {
    await expectBootstrap(
      {
        'lib/app.dart': app,
        'lib/jobs.dart': '''
import 'package:diana_annotation/diana_annotation.dart';

@Component()
class Jobs {
  @Scheduled(cron: '@daily', fixedRate: 100)
  Future<void> nightly() async {}
}
''',
      },
      output: '',
      expectedErrors: [
        '@Scheduled on Jobs.nightly requires exactly one of fixedRate, '
            'fixedDelay or cron.',
      ],
    );
  });

  test('wires @EventListener methods and DianaEventPublisher injection',
      () async {
    await expectBootstrap(
      {
        'lib/app.dart': app,
        'lib/orders.dart': '''
import 'package:diana/diana.dart';

class OrderCreated {
  final int id;
  const OrderCreated(this.id);
}

@Service()
class OrderService {
  OrderService(this.publisher);
  final DianaEventPublisher publisher;

  @EventListener()
  void onOrderCreated(OrderCreated event) {}
}
''',
      },
      output: allOf([
        matches(RegExp(r'final (_i\d+\.)?DianaEventBus eventBus = '
            r'(_i\d+\.)?DianaEventBus\(\);')),
        matches(RegExp(r'eventBus\.on<(_i\d+\.)?OrderCreated>'
            r'\(\(e\) => orderService\.onOrderCreated\(e\)\)')),
        contains('OrderService(eventBus)'),
        contains('eventBus: app.context.eventBus'),
      ]),
    );
  });

  test('injects the publisher into request-scoped providers via _ctx',
      () async {
    await expectBootstrap(
      {
        'lib/app.dart': app,
        'lib/audit.dart': '''
import 'package:diana/diana.dart';

@Component(scope: Scope.request)
class RequestAudit {
  RequestAudit(this.publisher);
  final DianaEventPublisher publisher;
}
''',
      },
      output: contains('RequestAudit(_ctx.eventBus)'),
    );
  });

  test('apps without events emit no event bus (byte identity)', () async {
    await expectBootstrap(
      {
        'lib/app.dart': app,
        'lib/service.dart': '''
import 'package:diana_annotation/diana_annotation.dart';

@Service()
class Plain {}
''',
      },
      output: isNot(contains('eventBus')),
    );
  });

  test('rejects @EventListener methods with invalid signatures', () async {
    await expectBootstrap(
      {
        'lib/app.dart': app,
        'lib/listener.dart': '''
import 'package:diana_annotation/diana_annotation.dart';

@Component()
class Auditor {
  @EventListener()
  void onAnything() {}
}
''',
      },
      output: '',
      expectedErrors: [
        '@EventListener method Auditor.onAnything must be a public instance '
            'method with exactly one positional parameter returning void or '
            'Future<void>.',
      ],
    );
  });

  test('rejects @EventListener parameters that are not class types',
      () async {
    await expectBootstrap(
      {
        'lib/app.dart': app,
        'lib/listener.dart': '''
import 'package:diana_annotation/diana_annotation.dart';

@Component()
class Auditor {
  @EventListener()
  void onMaybe(String? event) {}
}
''',
      },
      output: '',
      expectedErrors: [
        '@EventListener parameter "event" of Auditor.onMaybe must be a '
            'non-nullable class type; found String?.',
      ],
    );
  });

  test('rejects @EventListener on non-singleton providers', () async {
    await expectBootstrap(
      {
        'lib/app.dart': app,
        'lib/listener.dart': '''
import 'package:diana_annotation/diana_annotation.dart';

class Ping {}

@Component(scope: Scope.request)
class Auditor {
  @EventListener()
  void onPing(Ping event) {}
}
''',
      },
      output: '',
      expectedErrors: [
        '@EventListener on Auditor requires singleton scope; found request.',
      ],
    );
  });

  test('emits guards as the last route middleware element', () async {
    await expectBootstrap(
      {
        'lib/app.dart': app,
        'lib/web.dart': '''
import 'dart:async';

import 'package:diana/diana.dart';

@Component()
class Guard implements Middleware {
  @override
  FutureOr<DianaResponse> handle(DianaRequest req, Next next) => next(req);
}

@RestController('/admin')
@Secured()
class AdminController {
  @Get('/stats')
  @UseMiddleware([Guard])
  @RolesAllowed(['admin', 'ops'])
  String stats() => 'ok';

  @Get('/ping')
  String ping() => 'pong';
}
''',
      },
      output: allOf([
        // Method @RolesAllowed replaces controller @Secured; guard appended
        // after the route's own middleware.
        matches(RegExp(r'ctx\.guard,\s*const (_i\d+\.)?'
            r"RolesGuard\(\['admin', 'ops'\]\)")),
        // Route without its own annotation inherits @Secured from the class.
        matches(RegExp(r'const (_i\d+\.)?SecuredGuard\(\)')),
        contains("import 'package:diana_auth/diana_auth.dart'"),
      ]),
    );
  });

  test('apps without security emit no diana_auth reference', () async {
    await expectBootstrap(
      {
        'lib/app.dart': app,
        'lib/web.dart': '''
import 'package:diana/diana.dart';

@RestController('/x')
class XController {
  @Get()
  String hello() => 'hi';
}
''',
      },
      output: isNot(contains('diana_auth')),
    );
  });

  test('rejects @RolesAllowed with an empty role list', () async {
    await expectBootstrap(
      {
        'lib/app.dart': app,
        'lib/web.dart': '''
import 'package:diana/diana.dart';

@RestController('/x')
class XController {
  @Get()
  @RolesAllowed([])
  String hello() => 'hi';
}
''',
      },
      output: '',
      expectedErrors: ['@RolesAllowed on XController.hello lists no roles.'],
    );
  });

  test('rejects security annotations on non-securable elements', () async {
    await expectBootstrap(
      {
        'lib/app.dart': app,
        'lib/svc.dart': '''
import 'package:diana/diana.dart';

@Secured()
@Service()
class PlainService {}
''',
      },
      output: '',
      expectedErrors: [
        '@Secured/@RolesAllowed on PlainService has no effect: it is not a '
            'REST controller, WebSocket controller, gRPC service, or route '
            'method.',
      ],
    );
  });

  test('wires a gRPC auth interceptor from the AuthenticationMiddleware',
      () async {
    await expectBootstrap(
      {
        'lib/app.dart': app,
        'lib/svc.dart': '''
import 'package:diana_annotation/diana_annotation.dart';

import 'grpc_base.dart';
import 'auth.dart';

@GrpcService()
@RolesAllowed(['admin'])
class GreeterService extends GreeterServiceBase {}
''',
        'lib/grpc_base.dart': r'''
import 'package:grpc/grpc.dart';

class GreeterServiceBase extends Service {
  @override
  String get $name => 'greeter.Greeter';
}
''',
        'lib/auth.dart': '''
import 'package:diana/diana.dart';
import 'package:diana_auth/diana_auth.dart';

@GlobalMiddleware(order: -100)
class AppAuth extends AuthenticationMiddleware {
  AppAuth() : super(authenticators: const []);
}
''',
      },
      output: matches(RegExp(
          r'grpcAuthInterceptor\(\s*ctx\.appAuth\.authorizeMetadata,\s*'
          r"rolesAllowed: \['admin'\]")),
    );
  });

  test('rejects gRPC security without an AuthenticationMiddleware', () async {
    await expectBootstrap(
      {
        'lib/app.dart': app,
        'lib/svc.dart': '''
import 'package:diana_annotation/diana_annotation.dart';

import 'grpc_base.dart';

@GrpcService()
@Secured()
class GreeterService extends GreeterServiceBase {}
''',
        'lib/grpc_base.dart': r'''
import 'package:grpc/grpc.dart';

class GreeterServiceBase extends Service {
  @override
  String get $name => 'greeter.Greeter';
}
''',
      },
      output: '',
      expectedErrors: [
        '@Secured/@RolesAllowed on @GrpcService GreeterService requires '
            "exactly one singleton provider extending diana_auth's "
            'AuthenticationMiddleware; found none.',
      ],
    );
  });

  test('rejects divergent gRPC security across services', () async {
    await expectBootstrap(
      {
        'lib/app.dart': app,
        'lib/svc.dart': '''
import 'package:diana_annotation/diana_annotation.dart';

import 'grpc_base.dart';
import 'auth.dart';

@GrpcService()
@Secured()
class AService extends AServiceBase {}

@GrpcService()
class BService extends BServiceBase {}
''',
        'lib/grpc_base.dart': r'''
import 'package:grpc/grpc.dart';

class AServiceBase extends Service {
  @override
  String get $name => 'a.A';
}

class BServiceBase extends Service {
  @override
  String get $name => 'b.B';
}
''',
        'lib/auth.dart': '''
import 'package:diana/diana.dart';
import 'package:diana_auth/diana_auth.dart';

@GlobalMiddleware(order: -100)
class AppAuth extends AuthenticationMiddleware {
  AppAuth() : super(authenticators: const []);
}
''',
      },
      output: '',
      expectedErrors: [
        'gRPC security is server-wide in this version; all @GrpcService '
            'classes must declare identical @Secured/@RolesAllowed (found '
            'differing declarations on AService and BService).',
      ],
    );
  });

  test('wires Database + a transactional proxy for @Transactional providers',
      () async {
    await expectBootstrap(
      {
        'lib/app.dart': app,
        'lib/data.dart': '''
import 'package:diana/diana.dart';
import 'package:diana_data/diana_data.dart';

@Component()
class AppDb extends DatabaseConnector {
  @override
  Future<Object> connect(Object config) async => Object();
  @override
  Future<void> close(Object connection) async {}
}

@Repository()
class Ledger {
  Ledger(this.db);
  final Database db;

  @Transactional()
  Future<void> transfer(int amount) async {}
}
''',
      },
      output: allOf([
        // Database field on the context, opened/closed in the lifecycle.
        matches(RegExp(r'late final (_i\d+\.)?Database database =')),
        contains('await database.open();'),
        contains('await database.migrate();'),
        contains('await database.close();'),
        // The provider is constructed as the generated proxy, db first.
        contains(r'$Tx$Ledger(database, '),
        // Proxy override wraps super in runTransactional.
        matches(RegExp(r'class \$Tx\$Ledger extends (_i\d+\.)?Ledger')),
        contains('_db.runTransactional(() => super.transfer(amount))'),
      ]),
    );
  });

  test('apps without data emit no diana_data reference', () async {
    await expectBootstrap(
      {
        'lib/app.dart': app,
        'lib/service.dart': '''
import 'package:diana_annotation/diana_annotation.dart';

@Service()
class Plain {}
''',
      },
      output: isNot(contains('diana_data')),
    );
  });

  test('rejects @Transactional/Database without a connector', () async {
    await expectBootstrap(
      {
        'lib/app.dart': app,
        'lib/data.dart': '''
import 'package:diana/diana.dart';
import 'package:diana_data/diana_data.dart';

@Repository()
class Ledger {
  Ledger(this.db);
  final Database db;
}
''',
      },
      output: '',
      expectedErrors: [
        '@Transactional/Database/DianaRepository usage found but no '
            'DatabaseConnector '
            "provider was declared. Add a @Component extending diana_data's "
            'DatabaseConnector.',
      ],
    );
  });

  test('rejects @Transactional on a non-extendable class', () async {
    await expectBootstrap(
      {
        'lib/app.dart': app,
        'lib/svc.dart': '''
import 'package:diana/diana.dart';

@Service()
final class Ledger {
  @Transactional()
  Future<void> transfer() async {}
}
''',
      },
      output: '',
      expectedErrors: [
        '@Transactional class Ledger must be extendable: remove the '
            'final/base/sealed modifier so Diana can generate a transactional '
            'proxy subclass.',
      ],
    );
  });

  test('rejects @Transactional on a non-Future method', () async {
    await expectBootstrap(
      {
        'lib/app.dart': app,
        'lib/svc.dart': '''
import 'package:diana/diana.dart';

@Service()
class Ledger {
  @Transactional()
  void transfer() {}
}
''',
      },
      output: '',
      expectedErrors: [
        '@Transactional method Ledger.transfer must return Future '
            '(transactions are asynchronous); found void.',
      ],
    );
  });

  test('rejects @Transactional on a non-provider class', () async {
    await expectBootstrap(
      {
        'lib/app.dart': app,
        'lib/svc.dart': '''
import 'package:diana/diana.dart';

@RestController('/x')
class XController {
  @Get()
  @Transactional()
  Future<String> hello() async => 'hi';
}
''',
      },
      output: '',
      expectedErrors: [
        '@Transactional on XController has no effect: it is not a '
            '@Service/@Component/@Repository provider.',
      ],
    );
  });

  group('aspect proxies', () {
    test('tx-only providers keep the historical shape with no aspect '
        'machinery', () async {
      await expectBootstrap(
        {
          'lib/app.dart': app,
          'lib/data.dart': '''
import 'package:diana/diana.dart';
import 'package:diana_data/diana_data.dart';

@Component()
class AppDb extends DatabaseConnector {
  @override
  Future<Object> connect(Object config) async => Object();
  @override
  Future<void> close(Object connection) async {}
}

@Repository()
class Ledger {
  Ledger(this.db);
  final Database db;

  @Transactional()
  Future<void> transfer(int amount) async {}
}
''',
        },
        output: allOf([
          contains(r'class $Tx$Ledger'),
          isNot(contains(r'$Aspect$')),
          isNot(contains('runTimed')),
          isNot(contains('DianaObserver')),
          isNot(contains('MethodCache')),
        ]),
      );
    });

    test('composes all five aspects in the fixed order', () async {
      await expectBootstrap(
        {
          'lib/app.dart': app,
          'lib/data.dart': '''
import 'package:diana/diana.dart';
import 'package:diana_data/diana_data.dart';

class DbUnavailable implements Exception {}

@Component()
class AppDb extends DatabaseConnector {
  @override
  Future<Object> connect(Object config) async => Object();
  @override
  Future<void> close(Object connection) async {}
}

@Service()
class Reports {
  Reports(this.db);
  final Database db;

  @Timed()
  @Cacheable(ttlSeconds: 30, maxEntries: 16)
  @Retryable(maxAttempts: 4, backoffMs: 100, retryOn: [DbUnavailable])
  @CircuitBreaker(failureThreshold: 2, resetTimeoutMs: 5000)
  @Transactional()
  Future<List<String>> summarize(int year, String region) async => [];
}
''',
        },
        output: allOf([
          // Proxy class with observer + db prepended in the constructor.
          matches(RegExp(r'class \$Aspect\$Reports extends (_i\d+\.)?Reports')),
          matches(RegExp(
              r'\$Aspect\$Reports\(\s*this\._observer,\s*this\._db,')),
          matches(RegExp(r'final (_i\d+\.)?DianaObserver\? _observer;')),
          // Per-method state fields with the annotation's values.
          matches(RegExp(
              r'final _cache\$summarize = (_i\d+\.)?MethodCache<List<String>>\(')),
          contains('ttl: const Duration(seconds: 30)'),
          contains('maxEntries: 16'),
          contains('failureThreshold: 2'),
          contains('resetTimeout: const Duration(milliseconds: 5000)'),
          contains('maxAttempts: 4'),
          matches(RegExp(r'retryWhen: \(e\) => e is (_i\d+\.)?DbUnavailable')),
          // Nesting order: Timed → Cacheable → Breaker → Retry → Tx.
          matches(RegExp(
              r"runTimed\(\s*_observer,\s*'Reports\.summarize',\s*\(\) =>\s*"
              r'_cache\$summarize\.run\(\s*\[\s*year,\s*region,?\s*\],\s*\(\) =>\s*'
              r'_breaker\$summarize\.run\(\s*\(\) =>\s*'
              r'_retry\$summarize\.run\(\s*\(\) =>\s*'
              r'_db\.runTransactional\(\s*\(\) =>\s*super\.summarize\(year, region\)',
              multiLine: true)),
          // Context constructs the proxy with observer slot = null (no
          // observability provider in this app).
          matches(RegExp(r'\$Aspect\$Reports\(\s*null,\s*database,')),
        ]),
      );
    });

    test('@Timed wires the observability provider into the proxy', () async {
      await expectBootstrap(
        {
          'lib/app.dart': app,
          'lib/obs.dart': '''
import 'package:diana_annotation/diana_annotation.dart';
import 'package:diana_observability/diana_observability.dart';

@Component()
class AppObservability extends DianaObservability {}
''',
          'lib/svc.dart': '''
import 'package:diana/diana.dart';

@Service()
class Reporter {
  @Timed()
  Future<int> count() async => 1;
}
''',
        },
        output: allOf([
          matches(RegExp(r'\$Aspect\$Reporter\(appObservability\)')),
          matches(RegExp(
              r"runTimed\(\s*_observer,\s*'Reporter\.count',\s*\(\) =>\s*"
              r'super\.count\(\)',
              multiLine: true)),
        ]),
      );
    });

    test('cache/retry/breaker alone require no database', () async {
      await expectBootstrap(
        {
          'lib/app.dart': app,
          'lib/svc.dart': '''
import 'package:diana/diana.dart';

@Service()
class Lookup {
  @Cacheable(ttlSeconds: 5)
  Future<String> find(int id) async => '\$id';

  @Retryable(maxAttempts: 2)
  @CircuitBreaker()
  Future<void> ping() async {}
}
''',
        },
        output: allOf([
          isNot(contains('diana_data')),
          matches(RegExp(r'class \$Aspect\$Lookup')),
          contains(r'_cache$find.run('),
          matches(RegExp(
              r'_breaker\$ping\.run\(\s*\(\) =>\s*_retry\$ping\.run\(',
              multiLine: true)),
          isNot(contains('_observer')),
        ]),
      );
    });

    test('generic aspect methods re-declare their type parameters',
        () async {
      await expectBootstrap(
        {
          'lib/app.dart': app,
          'lib/svc.dart': '''
import 'package:diana/diana.dart';

@Service()
class Picker {
  @Retryable(maxAttempts: 2)
  Future<T> first<T extends Object>(List<T> items) async => items.first;
}
''',
        },
        output: allOf([
          matches(RegExp(
              r'Future<T> first<T extends Object>\(List<T> items\)')),
          contains(r'_retry$first.run(() => super.first(items))'),
        ]),
      );
    });
  });

  group('STOMP', () {
    const dtoLib = '''
import 'package:diana/diana.dart';

@Json()
class ChatIn { final String text; const ChatIn(this.text); }

@Json()
class ChatOut { final String msg; const ChatOut(this.msg); }
''';
    const gatewayLib = '''
import 'package:diana/diana.dart';

@WebSocketController('/stomp')
class Gw extends StompEndpoint { Gw(super.broker); }
''';

    test('wires the broker, endpoint and mapping registrations', () async {
      await expectBootstrap(
        {
          'lib/app.dart': app,
          'lib/dto.dart': dtoLib,
          'lib/gateway.dart': gatewayLib,
          'lib/svc.dart': '''
import 'package:diana/diana.dart';
import 'dto.dart';

@Service()
class ChatService {
  @MessageMapping('/chat')
  @SendTo('/topic/chat')
  Future<ChatOut> handle(ChatIn payload, StompMessage m) async =>
      const ChatOut('hi');

  @MessageMapping('/echo')
  @SendTo('/topic/echo')
  String echo(String body) => body;

  @MessageMapping('/log')
  Future<void> log(String body) async {}
}

@Service()
class Notifier {
  final StompPublisher stomp;
  Notifier(this.stomp);
}
''',
        },
        output: allOf([
          // Broker field, built from the event bus + config.
          matches(RegExp(
              r'late final stompBroker = (_i\d+\.)?StompBroker\(eventBus, config\)')),
          // STOMP forces the event bus to exist.
          matches(RegExp(r'(_i\d+\.)?DianaEventBus eventBus =')),
          // json payload + reply encode.
          matches(RegExp(
              r"registerMapping\(\s*'/chat',\s*\(m\) =>\s*"
              r'chatService\.handle\(\s*(_i\d+\.)?\$ChatInFromJson\(\s*'
              r'(_i\d+\.)?stompJsonMap\(m\.body\)\),\s*m\),\s*'
              r"sendTo: '/topic/chat',\s*encode: \(r\) =>\s*"
              r'(_i\d+\.)?stompJsonBody\(\s*(_i\d+\.)?\$ChatOutToJson\(r as (_i\d+\.)?ChatOut\)\)',
              multiLine: true)),
          // text payload + text reply, no encode.
          matches(RegExp(
              r"registerMapping\(\s*'/echo',\s*\(m\) => chatService\.echo\(m\.body\),\s*"
              r"sendTo: '/topic/echo',\s*\)",
              multiLine: true)),
          // void handler wrapped in an awaiting async block.
          matches(RegExp(
              r"registerMapping\('/log', \(m\) async \{\s*"
              r'await chatService\.log\(m\.body\);\s*return null;\s*\}\)',
              multiLine: true)),
          // Endpoint + publisher get the broker.
          contains(r'Gw(stompBroker)'),
          contains(r'Notifier(stompBroker)'),
          // The endpoint is registered as a WebSocket.
          matches(RegExp(r"registerWebSocket\(\s*'/stomp'")),
          // DianaRunnable receives the bus for cross-isolate relay.
          contains('eventBus: app.context.eventBus'),
        ]),
      );
    });

    test('an endpoint with no mappings still constructs the broker eagerly',
        () async {
      await expectBootstrap(
        {
          'lib/app.dart': app,
          'lib/gateway.dart': gatewayLib,
        },
        output: allOf([
          matches(RegExp(r'late final stompBroker =')),
          contains('stompBroker;'), // eager relay-listener registration
        ]),
      );
    });

    test('apps without STOMP emit no broker', () async {
      await expectBootstrap(
        {
          'lib/app.dart': app,
          'lib/svc.dart': '''
import 'package:diana_annotation/diana_annotation.dart';

@Service()
class Plain {}
''',
        },
        output: isNot(contains('stompBroker')),
      );
    });

    test('rejects a StompEndpoint without @WebSocketController', () async {
      await expectBootstrap(
        {
          'lib/app.dart': app,
          'lib/gw.dart': '''
import 'package:diana/diana.dart';

@Service()
class Gw extends StompEndpoint { Gw(super.broker); }
''',
        },
        output: '',
        expectedErrors: [
          'Class Gw (package:a/gw.dart) extends StompEndpoint but is not '
              'annotated with @WebSocketController. Annotate it with '
              "@WebSocketController('/path') to expose the STOMP endpoint.",
        ],
      );
    });

    test('rejects @MessageMapping with no endpoint', () async {
      await expectBootstrap(
        {
          'lib/app.dart': app,
          'lib/svc.dart': '''
import 'package:diana/diana.dart';

@Service()
class Svc {
  @MessageMapping('/x')
  void handle(String body) {}
}
''',
        },
        output: '',
        expectedErrors: [
          '@MessageMapping methods were found but no @WebSocketController '
              'extends StompEndpoint. Declare a singleton endpoint class '
              'extending StompEndpoint to accept STOMP connections.',
        ],
      );
    });

    test('rejects duplicate mapping destinations', () async {
      await expectBootstrap(
        {
          'lib/app.dart': app,
          'lib/gateway.dart': gatewayLib,
          'lib/svc.dart': '''
import 'package:diana/diana.dart';

@Service()
class A {
  @MessageMapping('/x')
  void a(String body) {}
}

@Service()
class B {
  @MessageMapping('/x')
  void b(String body) {}
}
''',
        },
        output: '',
        expectedErrors: [
          '@MessageMapping destination "/x" is handled by both A.a '
              '(package:a/svc.dart) and B.b (package:a/svc.dart). '
              'Destinations must be unique across the application.',
        ],
      );
    });

    group('reader diagnostics', () {
      Future<void> expectMappingError(String svc, String message) =>
          expectBootstrap(
            {'lib/app.dart': app, 'lib/svc.dart': svc},
            output: '',
            expectedErrors: [message],
          );

      test('bad signature', () async {
        await expectMappingError('''
import 'package:diana/diana.dart';

@Service()
class Svc {
  @MessageMapping('/x')
  void handle(String a, String b, String c) {}
}
''', '@MessageMapping method Svc.handle must be a public instance method '
            'with one or two positional parameters: the payload (String or '
            'an @Json class), optionally followed by a StompMessage.');
      });

      test('bad payload type', () async {
        await expectMappingError('''
import 'package:diana/diana.dart';

@Service()
class Svc {
  @MessageMapping('/x')
  void handle(int payload) {}
}
''', '@MessageMapping payload parameter "payload" of Svc.handle must be '
            'String or a class annotated with @Json; found int.');
      });

      test('non-void return without @SendTo', () async {
        await expectMappingError('''
import 'package:diana/diana.dart';

@Service()
class Svc {
  @MessageMapping('/x')
  String handle(String body) => body;
}
''', '@MessageMapping method Svc.handle returns a value but has no @SendTo '
            "destination. Add @SendTo('/topic/...') or return void.");
      });

      test('@SendTo on a void method', () async {
        await expectMappingError('''
import 'package:diana/diana.dart';

@Service()
class Svc {
  @MessageMapping('/x')
  @SendTo('/topic/y')
  void handle(String body) {}
}
''', '@SendTo on Svc.handle requires a non-void return value to publish.');
      });

      test('@SendTo without @MessageMapping', () async {
        await expectMappingError('''
import 'package:diana/diana.dart';

@Service()
class Svc {
  @SendTo('/topic/y')
  String handle(String body) => body;
}
''', '@SendTo on Svc.handle requires @MessageMapping on the same method.');
      });

      test('destination without a leading slash', () async {
        await expectMappingError('''
import 'package:diana/diana.dart';

@Service()
class Svc {
  @MessageMapping('x')
  void handle(String body) {}
}
''', '@MessageMapping destination "x" on Svc.handle must start with "/".');
      });

      test('non-singleton provider', () async {
        await expectMappingError('''
import 'package:diana/diana.dart';

@Service(scope: Scope.transient)
class Svc {
  @MessageMapping('/x')
  void handle(String body) {}
}
''', '@MessageMapping on Svc requires singleton scope; found transient.');
      });
    });
  });

  group('query repositories', () {
    /// dart_style splits long fluent chains across lines; make every
    /// chain-dot whitespace-tolerant (and allocator prefixes optional).
    Matcher chainMatch(String chain) {
      var pattern = RegExp.escape(chain).replaceAll(r'\.', r'\s*\.\s*');
      pattern = pattern.replaceAll(r'\$PREFIX', r'(_i\d+\.)?');
      return matches(RegExp(pattern, multiLine: true));
    }

    const commentLib = '''
import 'package:diana/diana.dart';

@Json()
@Table('comments')
class Comment {
  final int? id;

  @JsonField(name: 'post_id')
  final int postId;

  final String title;
  final String body;

  const Comment(
      {this.id, required this.postId, required this.title, required this.body});
}
''';

    const connectorLib = '''
import 'package:diana/diana.dart';
import 'package:diana_data/diana_data.dart';

@Component()
class AppDb extends DatabaseConnector {
  @override
  Future<Object> connect(Object config) async => Object();
  @override
  Future<void> close(Object connection) async {}
}
''';

    Future<void> expectRepo(String repoLib, Object output,
        {List<String> expectedErrors = const []}) {
      return expectBootstrap(
        {
          'lib/app.dart': app,
          'lib/comment.dart': commentLib,
          'lib/db.dart': connectorLib,
          'lib/repo.dart': repoLib,
        },
        output: output,
        expectedErrors: expectedErrors,
      );
    }

    test('emits the CRUD + query implementations and swaps construction',
        () async {
      await expectRepo('''
import 'package:diana/diana.dart';
import 'package:diana_data/diana_data.dart';

import 'comment.dart';

@Repository()
abstract class CommentRepository extends DianaRepository<Comment> {
  CommentRepository(super.db);

  Future<List<Comment>> findByTitle(String title);
  Future<Comment?> findFirstByIdAndTitle(int id, String title);
  Future<int> countByTitle(String title);
  Future<bool> existsByBodyLike(String body);
  Future<void> deleteByTitle(String title);
  Future<List<Comment>> findByBodyContainsOrderByIdDesc(String body);
  Future<List<Comment>> findByIdBetween(int low, int high);
  Future<List<Comment>> findByTitleIn(List<String> titles);
  Future<List<Comment>> findByTitleOrBody(String title, String body);
  Future<List<Comment>> findByBodyIsNull();
  Future<List<Comment>> findByIdNot(int id);
  Future<List<Comment>> findByTitleStartsWithOrderByTitleAscIdDesc(
      String prefix);
  Future<List<Comment>> findByPostId(int postId);
}
''', allOf([
        matches(RegExp(
            r'class \$Repo\$CommentRepository extends (_i\d+\.)?CommentRepository')),
        // Construction swapped to the generated impl, db forwarded.
        matches(RegExp(r'\$Repo\$CommentRepository\(database\)')),
        // CRUD.
        chainMatch("for (final row in await db.select(db.table('comments')))"),
        chainMatch("db.table('comments').where('id', '=', id).limit(1)"),
        chainMatch(
            r'.insert($PREFIX$CommentToJson(entity)'
            '..removeWhere((k, v) => v == null))'),
        chainMatch("db.table('comments').where('id', '=', id).delete()"),
        // Query methods.
        chainMatch("db.table('comments').where('title', '=', title)"),
        chainMatch(
            "db.table('comments').where('id', '=', id)"
            ".where('title', '=', title).limit(1)"),
        chainMatch("runCount(db.table('comments')"),
        chainMatch(
            "runExists(db.table('comments').where('body', 'like', body))"),
        chainMatch(
            "db.delete(db.table('comments')"
            ".where('title', '=', title).delete())"),
        chainMatch(r"where('body', 'like', '%$body%').orderBy('id', 'desc')"),
        chainMatch("whereBetween('id', [low, high])"),
        chainMatch("whereIn('title', titles)"),
        chainMatch(
            "where('title', '=', title).orWhere('body', '=', body)"),
        chainMatch("whereNull('body')"),
        chainMatch("where('id', '<>', id)"),
        chainMatch(r"where('title', 'like', '$prefix%')"
            ".orderBy('title', 'asc').orderBy('id', 'desc')"),
        // @JsonField(name:) doubles as the column override.
        chainMatch("where('post_id', '=', postId)"),
        matches(RegExp(r'(_i\d+\.)?\$CommentFromJson\(row\)')),
      ]));
    });

    test('apps without query repos emit no repo machinery', () async {
      await expectBootstrap(
        {
          'lib/app.dart': app,
          'lib/comment.dart': commentLib,
          'lib/db.dart': connectorLib,
        },
        output: isNot(contains(r'$Repo$')),
      );
    });

    test('rejects a raw DianaRepository supertype', () async {
      await expectRepo('''
import 'package:diana/diana.dart';
import 'package:diana_data/diana_data.dart';

@Repository()
abstract class BadRepo extends DianaRepository {
  BadRepo(super.db);
}
''', '', expectedErrors: [
        'Query repository BadRepo must extend DianaRepository<E> with a '
            'concrete class type argument.',
      ]);
    });

    test('rejects a non-@Json entity', () async {
      await expectBootstrap({
        'lib/app.dart': app,
        'lib/db.dart': connectorLib,
        'lib/repo.dart': '''
import 'package:diana/diana.dart';
import 'package:diana_data/diana_data.dart';

class Plain {
  final int id;
  const Plain(this.id);
}

@Repository()
abstract class PlainRepo extends DianaRepository<Plain> {
  PlainRepo(super.db);
}
''',
      }, output: '', expectedErrors: [
        'Query repository PlainRepo targets Plain, which is not a @Json '
            'class. Annotate Plain with @Json() so rows can be mapped to '
            'instances.',
      ]);
    });

    test('rejects a missing @Table and a missing id field', () async {
      await expectBootstrap({
        'lib/app.dart': app,
        'lib/db.dart': connectorLib,
        'lib/repo.dart': '''
import 'package:diana/diana.dart';
import 'package:diana_data/diana_data.dart';

@Json()
class NoTable {
  final int id;
  const NoTable(this.id);
}

@Repository()
abstract class NoTableRepo extends DianaRepository<NoTable> {
  NoTableRepo(super.db);
}
''',
      }, output: '', expectedErrors: [
        'Query repository NoTableRepo targets NoTable, which is missing '
            "@Table. Annotate NoTable with @Table('table_name').",
      ]);
      await expectBootstrap({
        'lib/app.dart': app,
        'lib/db.dart': connectorLib,
        'lib/repo.dart': '''
import 'package:diana/diana.dart';
import 'package:diana_data/diana_data.dart';

@Json()
@Table('things')
class NoId {
  final String name;
  const NoId(this.name);
}

@Repository()
abstract class NoIdRepo extends DianaRepository<NoId> {
  NoIdRepo(super.db);
}
''',
      }, output: '', expectedErrors: [
        "Query repository NoIdRepo targets NoId, which has no 'id' field; "
            'DianaRepository.findById/deleteById need one.',
      ]);
    });

    test('rejects aspects, abstract getters and CRUD re-declarations',
        () async {
      await expectRepo('''
import 'package:diana/diana.dart';
import 'package:diana_data/diana_data.dart';

import 'comment.dart';

@Repository()
abstract class R1 extends DianaRepository<Comment> {
  R1(super.db);

  @Transactional()
  Future<List<Comment>> findByTitle(String title);
}
''', '', expectedErrors: [
        'Query repository R1 declares aspect-annotated methods; '
            '@Transactional/@Timed/@Cacheable/@Retryable/@CircuitBreaker are '
            'not supported on query repositories in this version. Move them '
            'to a service that injects R1.',
      ]);
      await expectRepo('''
import 'package:diana/diana.dart';
import 'package:diana_data/diana_data.dart';

import 'comment.dart';

@Repository()
abstract class R2 extends DianaRepository<Comment> {
  R2(super.db);

  int get total;
}
''', '', expectedErrors: [
        'Query repository R2 declares abstract member "total" which is not '
            'a method; only query methods can be abstract.',
      ]);
      await expectRepo('''
import 'package:diana/diana.dart';
import 'package:diana_data/diana_data.dart';

import 'comment.dart';

@Repository()
abstract class R3 extends DianaRepository<Comment> {
  R3(super.db);

  @override
  Future<List<Comment>> findAll();
}
''', '', expectedErrors: [
        'Query repository R3 re-declares "findAll", which is implemented by '
            'the generated repository; remove the declaration.',
      ]);
    });

    test('rejects unparseable names with helpful positions', () async {
      await expectRepo('''
import 'package:diana/diana.dart';
import 'package:diana_data/diana_data.dart';

import 'comment.dart';

@Repository()
abstract class R extends DianaRepository<Comment> {
  R(super.db);

  Future<List<Comment>> byTitle(String title);
}
''', '', expectedErrors: [
        'Query method R.byTitle must start with findBy, findFirstBy, '
            'countBy, existsBy or deleteBy.',
      ]);
      await expectRepo('''
import 'package:diana/diana.dart';
import 'package:diana_data/diana_data.dart';

import 'comment.dart';

@Repository()
abstract class R extends DianaRepository<Comment> {
  R(super.db);

  Future<List<Comment>> findByAuthor(String author);
}
''', '', expectedErrors: [
        'Cannot parse query method R.findByAuthor at "Author": expected a '
            'property of Comment followed by an optional condition. Known '
            'properties: id, postId, title, body.',
      ]);
      await expectRepo('''
import 'package:diana/diana.dart';
import 'package:diana_data/diana_data.dart';

import 'comment.dart';

@Repository()
abstract class R extends DianaRepository<Comment> {
  R(super.db);

  Future<List<Comment>> findByTitleAndBodyOrId(String t, String b, int id);
}
''', '', expectedErrors: [
        'Query method R.findByTitleAndBodyOrId mixes And and Or; a method '
            'may use only one connector.',
      ]);
      await expectRepo('''
import 'package:diana/diana.dart';
import 'package:diana_data/diana_data.dart';

import 'comment.dart';

@Repository()
abstract class R extends DianaRepository<Comment> {
  R(super.db);

  Future<List<Comment>> findByTitleOrderByTitle(String title);
}
''', '', expectedErrors: [
        'Cannot parse the OrderBy clause of query method '
            'R.findByTitleOrderByTitle at "": expected <Property>Asc or '
            '<Property>Desc. Known properties: id, postId, title, body.',
      ]);
      await expectRepo('''
import 'package:diana/diana.dart';
import 'package:diana_data/diana_data.dart';

import 'comment.dart';

@Repository()
abstract class R extends DianaRepository<Comment> {
  R(super.db);

  Future<int> countByTitleOrderByIdAsc(String title);
}
''', '', expectedErrors: [
        'OrderBy is not supported on countBy/existsBy/deleteBy (query '
            'method R.countByTitleOrderByIdAsc).',
      ]);
    });

    test('rejects parameter and return-type mismatches', () async {
      await expectRepo('''
import 'package:diana/diana.dart';
import 'package:diana_data/diana_data.dart';

import 'comment.dart';

@Repository()
abstract class R extends DianaRepository<Comment> {
  R(super.db);

  Future<List<Comment>> findByTitle({required String title});
}
''', '', expectedErrors: [
        'Query method R.findByTitle must declare only required positional '
            'parameters.',
      ]);
      await expectRepo('''
import 'package:diana/diana.dart';
import 'package:diana_data/diana_data.dart';

import 'comment.dart';

@Repository()
abstract class R extends DianaRepository<Comment> {
  R(super.db);

  Future<List<Comment>> findByIdBetween(int low);
}
''', '', expectedErrors: [
        'Query method R.findByIdBetween declares 1 parameter(s) but its '
            'conditions take 2.',
      ]);
      await expectRepo('''
import 'package:diana/diana.dart';
import 'package:diana_data/diana_data.dart';

import 'comment.dart';

@Repository()
abstract class R extends DianaRepository<Comment> {
  R(super.db);

  Future<List<Comment>> findByTitleIn(String titles);
}
''', '', expectedErrors: [
        'Parameter "titles" of query method R.findByTitleIn must be '
            'List<String> for condition "TitleIn"; got String.',
      ]);
      await expectRepo('''
import 'package:diana/diana.dart';
import 'package:diana_data/diana_data.dart';

import 'comment.dart';

@Repository()
abstract class R extends DianaRepository<Comment> {
  R(super.db);

  Future<List<Comment>> findByIdContains(int id);
}
''', '', expectedErrors: [
        'Condition "IdContains" of query method R.findByIdContains needs a '
            "String-typed property; 'id' of Comment is int?.",
      ]);
      await expectRepo('''
import 'package:diana/diana.dart';
import 'package:diana_data/diana_data.dart';

import 'comment.dart';

@Repository()
abstract class R extends DianaRepository<Comment> {
  R(super.db);

  Future<Comment> findByTitle(String title);
}
''', '', expectedErrors: [
        'Query method R.findByTitle must return Future<List<Comment>> '
            '(findBy); got Future<Comment>.',
      ]);
      await expectRepo('''
import 'package:diana/diana.dart';
import 'package:diana_data/diana_data.dart';

import 'comment.dart';

@Repository()
abstract class R extends DianaRepository<Comment> {
  R(super.db);

  Future<List<Comment>> findByTitleInOrBody(List<String> t, String b);
}
''', '', expectedErrors: [
        'Query method R.findByTitleInOrBody combines In with the Or '
            'connector, which the query builder cannot express; use And.',
      ]);
    });
  });

  group('pluggable cache store', () {
    const storeLib = '''
import 'package:diana/diana.dart';

@Component()
class AppCacheStore extends DianaCacheStore {
  @override
  Future<V> run<V>(
          CacheSpec spec, List<Object?> key, Future<V> Function() miss) =>
      miss();
}
''';

    test('routes @Cacheable through the declared store', () async {
      await expectBootstrap(
        {
          'lib/app.dart': app,
          'lib/store.dart': storeLib,
          'lib/svc.dart': '''
import 'package:diana/diana.dart';

@Service()
class Lookup {
  @Timed()
  @Cacheable(ttlSeconds: 5, maxEntries: 4)
  Future<String> find(int id) async => '\$id';
}
''',
        },
        output: allOf([
          // Constructor order: observer, store (no tx here).
          matches(RegExp(
              r'\$Aspect\$Lookup\(\s*this\._observer,\s*this\._cacheStore\)')),
          matches(RegExp(r'final (_i\d+\.)?DianaCacheStore _cacheStore;')),
          // Per-method const spec replaces the MethodCache field.
          matches(RegExp(r'static const _spec\$find = (_i\d+\.)?CacheSpec\(')),
          contains("method: 'Lookup.find'"),
          contains('ttl: Duration(seconds: 5)'),
          contains('maxEntries: 4'),
          isNot(contains('MethodCache')),
          // Cache layer goes through the store.
          matches(RegExp(
              r'_cacheStore\.run\(\s*_spec\$find,\s*\[\s*id,?\s*\]',
              multiLine: true)),
          // Context passes the store provider into the proxy.
          matches(RegExp(r'\$Aspect\$Lookup\(\s*null,\s*appCacheStore\)')),
        ]),
      );
    });

    test('without a store the built-in MethodCache emission is unchanged',
        () async {
      await expectBootstrap(
        {
          'lib/app.dart': app,
          'lib/svc.dart': '''
import 'package:diana/diana.dart';

@Service()
class Lookup {
  @Cacheable(ttlSeconds: 5)
  Future<String> find(int id) async => '\$id';
}
''',
        },
        output: allOf([
          contains(r'_cache$find'),
          matches(RegExp(r'(_i\d+\.)?MethodCache<String>\(')),
          isNot(contains('_cacheStore')),
          isNot(contains('CacheSpec')),
        ]),
      );
    });

    test('a store without @Cacheable is a plain provider', () async {
      await expectBootstrap(
        {
          'lib/app.dart': app,
          'lib/store.dart': storeLib,
        },
        output: isNot(contains('_cacheStore')),
      );
    });

    test('rejects multiple stores and non-singleton stores', () async {
      await expectBootstrap(
        {
          'lib/app.dart': app,
          'lib/stores.dart': '''
import 'package:diana/diana.dart';

@Component()
class StoreA extends DianaCacheStore {
  @override
  Future<V> run<V>(
          CacheSpec spec, List<Object?> key, Future<V> Function() miss) =>
      miss();
}

@Component()
class StoreB extends DianaCacheStore {
  @override
  Future<V> run<V>(
          CacheSpec spec, List<Object?> key, Future<V> Function() miss) =>
      miss();
}
''',
        },
        output: '',
        expectedErrors: [
          'Multiple DianaCacheStore providers: StoreA (package:a/stores.dart), '
              'StoreB (package:a/stores.dart). Declare exactly one.',
        ],
      );
      await expectBootstrap(
        {
          'lib/app.dart': app,
          'lib/stores.dart': '''
import 'package:diana/diana.dart';

@Component(scope: Scope.transient)
class StoreA extends DianaCacheStore {
  @override
  Future<V> run<V>(
          CacheSpec spec, List<Object?> key, Future<V> Function() miss) =>
      miss();
}
''',
        },
        output: '',
        expectedErrors: [
          'StoreA extends DianaCacheStore but is transient-scoped; '
              'cache stores must be singletons.',
        ],
      );
    });
  });

  group('aspect annotation diagnostics', () {
    Future<void> expectAspectError(String svc, String message) =>
        expectBootstrap(
          {'lib/app.dart': app, 'lib/svc.dart': svc},
          output: '',
          expectedErrors: [message],
        );

    test('rejects class-level @Timed (method-level only)', () async {
      await expectAspectError('''
import 'package:diana/diana.dart';

@Service()
@Timed()
class Reporter {
  Future<int> count() async => 1;
}
''', '@Timed is method-level only; annotate individual methods of Reporter.');
    });

    test('rejects @Cacheable on a non-Future method', () async {
      await expectAspectError('''
import 'package:diana/diana.dart';

@Service()
class Reporter {
  @Cacheable()
  int count() => 1;
}
''', '@Cacheable method Reporter.count must return Future (aspect proxies '
          'are asynchronous); found int.');
    });

    test('rejects @Retryable on a static method', () async {
      await expectAspectError('''
import 'package:diana/diana.dart';

@Service()
class Reporter {
  @Retryable()
  static Future<int> count() async => 1;
}
''', '@Retryable method Reporter.count must be a public instance method.');
    });

    test('rejects a non-extendable class with new aspects', () async {
      await expectAspectError('''
import 'package:diana/diana.dart';

@Service()
final class Reporter {
  @Timed()
  Future<int> count() async => 1;
}
''', 'Aspect-annotated class Reporter must be extendable: remove the '
          'final/base/sealed modifier so Diana can generate an aspect proxy '
          'subclass.');
    });

    test('rejects @Cacheable on a generic method', () async {
      await expectAspectError('''
import 'package:diana/diana.dart';

@Service()
class Reporter {
  @Cacheable()
  Future<T> first<T>(List<T> items) async => items.first;
}
''', '@Cacheable method Reporter.first declares type parameters; caching '
          'generic methods is not supported.');
    });

    test('rejects @Cacheable on Future<void>', () async {
      await expectAspectError('''
import 'package:diana/diana.dart';

@Service()
class Reporter {
  @Cacheable()
  Future<void> warm() async {}
}
''', '@Cacheable method Reporter.warm must return Future<T> with a '
          'non-void T (a void result cannot be cached); found Future<void>.');
    });

    test('rejects out-of-range aspect values', () async {
      await expectAspectError('''
import 'package:diana/diana.dart';

@Service()
class Reporter {
  @Cacheable(ttlSeconds: 0)
  Future<int> count() async => 1;
}
''', '@Cacheable on Reporter.count requires ttlSeconds >= 1; found 0.');
      await expectAspectError('''
import 'package:diana/diana.dart';

@Service()
class Reporter {
  @Retryable(maxAttempts: 0)
  Future<int> count() async => 1;
}
''', '@Retryable on Reporter.count requires maxAttempts >= 1; found 0.');
      await expectAspectError('''
import 'package:diana/diana.dart';

@Service()
class Reporter {
  @Retryable(backoffMs: -5)
  Future<int> count() async => 1;
}
''', '@Retryable on Reporter.count requires backoffMs >= 0; found -5.');
      await expectAspectError('''
import 'package:diana/diana.dart';

@Service()
class Reporter {
  @CircuitBreaker(failureThreshold: 0)
  Future<int> count() async => 1;
}
''', '@CircuitBreaker on Reporter.count requires failureThreshold >= 1; '
          'found 0.');
      await expectAspectError('''
import 'package:diana/diana.dart';

@Service()
class Reporter {
  @CircuitBreaker(resetTimeoutMs: 0)
  Future<int> count() async => 1;
}
''', '@CircuitBreaker on Reporter.count requires resetTimeoutMs >= 1; '
          'found 0.');
      await expectAspectError('''
import 'package:diana/diana.dart';

@Service()
class Reporter {
  @Timed(name: '')
  Future<int> count() async => 1;
}
''', '@Timed name on Reporter.count must not be empty.');
    });

    test('rejects @Timed on a non-provider class', () async {
      await expectAspectError('''
import 'package:diana/diana.dart';

@RestController('/x')
class XController {
  @Get()
  @Timed()
  Future<String> hello() async => 'hi';
}
''', '@Timed on XController has no effect: it is not a '
          '@Service/@Component/@Repository provider.');
    });
  });

  test('wires the observability provider into server, scheduler and metrics',
      () async {
    await expectBootstrap(
      {
        'lib/app.dart': app,
        'lib/obs.dart': '''
import 'package:diana_annotation/diana_annotation.dart';
import 'package:diana_observability/diana_observability.dart';

@Component()
class AppObservability extends DianaObservability {}

@Component()
class Beater {
  @Scheduled(fixedDelay: 50)
  void beat() {}
}
''',
      },
      output: allOf([
        // Server gets the observer.
        matches(RegExp(r'DianaServer\([^;]*observer: ctx\.appObservability')),
        // Scheduler gets the observer and each task a name.
        contains('DianaScheduler(observer: context.appObservability)'),
        matches(RegExp(r"name: 'Beater\.beat'")),
        // Metrics endpoint served from the provider.
        contains("'/actuator/metrics'"),
        contains('metricsEndpointHandler(ctx.appObservability)'),
        // Liveness/readiness always present.
        contains("'/actuator/health/liveness'"),
        contains("'/actuator/health/readiness'"),
        contains("import 'package:diana_observability/diana_observability.dart'"),
      ]),
    );
  });

  test('apps without observability emit no diana_observability reference '
      'but keep liveness/readiness', () async {
    await expectBootstrap(
      {
        'lib/app.dart': app,
        'lib/web.dart': '''
import 'package:diana/diana.dart';

@RestController('/x')
class XController {
  @Get()
  String hello() => 'hi';
}
''',
      },
      output: allOf([
        isNot(contains('diana_observability')),
        isNot(contains('observer:')),
        contains("'/actuator/health/liveness'"),
      ]),
    );
  });

  test('rejects multiple DianaObservability providers', () async {
    await expectBootstrap(
      {
        'lib/app.dart': app,
        'lib/obs.dart': '''
import 'package:diana_annotation/diana_annotation.dart';
import 'package:diana_observability/diana_observability.dart';

@Component()
class ObsA extends DianaObservability {}

@Component()
class ObsB extends DianaObservability {}
''',
      },
      output: '',
      expectedErrors: [
        'Multiple DianaObservability providers: ObsA (package:a/obs.dart), '
            'ObsB (package:a/obs.dart). Declare exactly one.',
      ],
    );
  });

  test('rejects a non-singleton DianaObservability provider', () async {
    await expectBootstrap(
      {
        'lib/app.dart': app,
        'lib/obs.dart': '''
import 'package:diana_annotation/diana_annotation.dart';
import 'package:diana_observability/diana_observability.dart';

@Component(scope: Scope.transient)
class AppObservability extends DianaObservability {}
''',
      },
      output: '',
      expectedErrors: [
        'AppObservability extends DianaObservability but is transient-scoped; '
            'observability providers must be singletons.',
      ],
    );
  });
}
