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
