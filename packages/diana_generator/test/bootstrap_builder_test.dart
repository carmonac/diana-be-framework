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
        '@Transactional/Database injection found but no DatabaseConnector '
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
}
