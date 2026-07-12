import 'package:build_test/build_test.dart';
import 'package:diana_generator/src/bootstrap_builder.dart';
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
            for (final path in sources.keys)
              'a|${path.replaceFirst('.dart', '.diana.json')}': anything,
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
        contains('late final _i2.MemRepo memRepo = _i2.MemRepo();'),
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
        contains('_i2.UuidFactory createUuidFactory() => _i2.UuidFactory();'),
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
    final derived = generated!.indexOf('is _i2.DerivedError');
    final base = generated!.indexOf('is _i2.BaseError');
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
      output: contains('_i1.HttpMethod.head'),
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
}
