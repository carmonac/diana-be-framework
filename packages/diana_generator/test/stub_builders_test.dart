import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:diana_generator/src/bootstrap_builder.dart';
import 'package:diana_generator/src/metadata_builder.dart';
import 'package:diana_generator/src/part_builder.dart';
import 'package:test/test.dart';

import 'util/package_assets.dart';

const _service = '''
import 'package:diana_annotation/diana_annotation.dart';

@Service()
class Foo {}
''';

void main() {
  late Map<String, String> deps;

  setUpAll(() async {
    deps = await dianaTestDeps();
  });

  Future<void> run(
    Builder builder,
    Map<String, String> sources, {
    Map<String, Object>? outputs,
  }) =>
      testBuilder(
        builder,
        {...deps, ...sources},
        outputs: outputs,
        isInput: (assetId) => assetId.startsWith('a|'),
      );

  group('DianaMetadataBuilder', () {
    test('emits a summary for annotated libraries only', () async {
      await run(
        const DianaMetadataBuilder(),
        {
          'a|lib/service.dart': _service,
          'a|lib/plain.dart': 'class Bar {}',
        },
        outputs: {
          'a|lib/service.diana.json': decodedMatches(contains('"Foo"')),
        },
      );
    });

    test('ignores files outside lib/', () async {
      await run(
        const DianaMetadataBuilder(),
        {'a|bin/main.dart': _service},
        outputs: {},
      );
    });
  });

  group('DianaPartBuilder', () {
    test('emits adapters when the part directive is present', () async {
      await run(
        const DianaPartBuilder(),
        {
          'a|lib/ctrl.dart': '''
import 'package:diana_annotation/diana_annotation.dart';

part 'ctrl.diana.dart';

@RestController('/ping')
class PingController {
  @Get()
  String ping() => 'pong';
}
''',
        },
        outputs: {
          'a|lib/ctrl.diana.dart': decodedMatches(allOf(
            contains("part of 'ctrl.dart';"),
            contains(r'$diana$PingController$ping'),
            contains('DianaResponse.text(result)'),
          )),
        },
      );
    });

    test('emits nothing for libraries with no generatable members', () async {
      await run(
        const DianaPartBuilder(),
        {'a|lib/service.dart': _service},
        outputs: {},
      );
    });
  });

  group('DianaBootstrapBuilder', () {
    test('does nothing without @DianaApplication', () async {
      await run(
        const DianaBootstrapBuilder(),
        {'a|lib/service.dart': _service},
        outputs: {},
      );
    });
  });
}
