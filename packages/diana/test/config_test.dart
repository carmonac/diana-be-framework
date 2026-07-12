import 'dart:io';

import 'package:diana/diana.dart';
import 'package:test/test.dart';

void main() {
  group('DianaConfig', () {
    test('coerces scalars to the requested type', () {
      final config = DianaConfig({
        'server.port': 8080,
        'app.pi': 3.14,
        'app.debug': 'true',
        'app.name': 'demo',
      });
      expect(config.get<int>('server.port'), 8080);
      expect(config.get<String>('server.port'), '8080');
      expect(config.get<double>('app.pi'), 3.14);
      expect(config.get<bool>('app.debug'), isTrue);
      expect(config.get<String>('app.name'), 'demo');
    });

    test('missing keys: default, nullable, or startup error', () {
      final config = DianaConfig(const {});
      expect(config.get<int>('a.b', defaultValue: 7), 7);
      expect(config.get<String?>('a.b'), isNull);
      expect(
        () => config.get<String>('app.greeting'),
        throwsA(isA<ConfigException>().having(
          (e) => e.message,
          'message',
          contains('APP_GREETING'),
        )),
      );
    });

    test('environment variables override file values', () {
      final config = DianaConfig(
        {'server.port': 8080, 'app.api-key': 'from-file'},
        environment: {'SERVER_PORT': '9090', 'APP_API_KEY': 'from-env'},
      );
      expect(config.get<int>('server.port'), 9090);
      expect(config.get<String>('app.api-key'), 'from-env');
      // Env-only keys work without a YAML entry.
      final envOnly =
          DianaConfig(const {}, environment: {'EXTRA_FLAG': 'true'});
      expect(envOnly.get<bool>('extra.flag'), isTrue);
    });

    test('uncoercible values fail with a clear message', () {
      final config = DianaConfig({'server.port': 'not-a-number'});
      expect(
        () => config.get<int>('server.port'),
        throwsA(isA<ConfigException>().having(
          (e) => e.message,
          'message',
          contains('cannot be read as int'),
        )),
      );
    });

    test('typed lists from YAML lists and comma-separated env vars', () {
      final config = DianaConfig(
        {
          'cors.origins': ['https://a.com', 'https://b.com'],
          'app.ports': [8080, 9090],
          'app.flags': ['true', 'false'],
        },
        environment: {'APP_TAGS': 'x, y ,z', 'APP_PORTS': '1,2'},
      );
      expect(config.get<List<String>>('cors.origins'),
          ['https://a.com', 'https://b.com']);
      // Env overrides a YAML list with a comma-separated string.
      expect(config.get<List<int>>('app.ports'), [1, 2]);
      expect(config.get<List<bool>>('app.flags'), [true, false]);
      expect(config.get<List<String>>('app.tags'), ['x', 'y', 'z']);
      expect(config.get<List<String>?>('app.missing'), isNull);
      expect(
        () => config.get<List<int>>('cors.origins'),
        throwsA(isA<ConfigException>()),
      );
    });

    test('section() strips the prefix and applies env overrides', () {
      final config = DianaConfig(
        {'info.name': 'demo', 'info.build.rev': 'abc', 'other.key': 1},
        environment: {'INFO_NAME': 'from-env'},
      );
      expect(config.section('info'), {
        'name': 'from-env',
        'build.rev': 'abc',
      });
      expect(config.section('nope'), isEmpty);
    });

    test('profiles: base < profile overlays (in order) < env', () async {
      final dir = Directory.systemTemp.createTempSync('diana_profiles');
      addTearDown(() => dir.deleteSync(recursive: true));
      File('${dir.path}/application.yaml').writeAsStringSync('''
diana:
  profile: dev
app:
  a: base
  b: base
  c: base
''');
      File('${dir.path}/application-dev.yaml').writeAsStringSync('''
app:
  a: dev
  b: dev
''');
      File('${dir.path}/application-extra.yaml').writeAsStringSync('''
app:
  b: extra
''');

      // diana.profile from the base file activates 'dev'.
      final fromFile =
          await DianaConfig.load('${dir.path}/application.yaml',
              environment: {});
      expect(fromFile.activeProfiles, ['dev']);
      expect(fromFile.get<String>('app.a'), 'dev');
      expect(fromFile.get<String>('app.c'), 'base');

      // DIANA_PROFILE fully replaces diana.profile; later profiles win;
      // env vars beat every file.
      final fromEnv = await DianaConfig.load(
        '${dir.path}/application.yaml',
        environment: {'DIANA_PROFILE': 'dev,extra', 'APP_A': 'env'},
      );
      expect(fromEnv.activeProfiles, ['dev', 'extra']);
      expect(fromEnv.get<String>('app.a'), 'env');
      expect(fromEnv.get<String>('app.b'), 'extra');
      expect(fromEnv.get<String>('app.c'), 'base');

      // A profile without a file is skipped silently.
      final missing = await DianaConfig.load(
        '${dir.path}/application.yaml',
        environment: {'DIANA_PROFILE': 'nope'},
      );
      expect(missing.activeProfiles, ['nope']);
      expect(missing.get<String>('app.a'), 'base');
    });

    test('load() flattens nested YAML and tolerates a missing file',
        () async {
      final dir = Directory.systemTemp.createTempSync('diana_config');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = File('${dir.path}/application.yaml')
        ..writeAsStringSync('''
server:
  port: 3000
app:
  greeting: hola
  tags:
    - a
    - b
''');
      final config = await DianaConfig.load(file.path, environment: {});
      expect(config.get<int>('server.port'), 3000);
      expect(config.get<String>('app.greeting'), 'hola');
      expect(config.contains('app.tags'), isTrue);

      final missing =
          await DianaConfig.load('${dir.path}/nope.yaml', environment: {});
      expect(missing.get<int>('server.port', defaultValue: 8080), 8080);
    });
  });
}
