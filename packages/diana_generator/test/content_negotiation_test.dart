import 'package:build_test/build_test.dart';
import 'package:diana_generator/src/part_builder.dart';
import 'package:test/test.dart';

import 'util/package_assets.dart';

void main() {
  late Map<String, String> deps;

  setUpAll(() async {
    deps = await dianaTestDeps();
  });

  Future<void> expectPart(
    String source, {
    Object? output,
    List<String> expectedErrors = const [],
  }) async {
    final logs = <String>[];
    await testBuilder(
      const DianaPartBuilder(),
      {...deps, 'a|lib/ctrl.dart': source},
      outputs: expectedErrors.isEmpty && output != null
          ? {'a|lib/ctrl.diana.dart': decodedMatches(output)}
          : (expectedErrors.isNotEmpty ? {} : null),
      isInput: (id) => id.startsWith('a|'),
      onLog: (r) {
        if (r.level.name == 'SEVERE') logs.add(r.message);
      },
    );
    for (final expected in expectedErrors) {
      expect(logs.join('\n'), contains(expected));
    }
  }

  test('emits codec-aware decode and negotiated response', () async {
    await expectPart(
      '''
import 'package:diana_annotation/diana_annotation.dart';

part 'ctrl.diana.dart';

@Json()
class Dto {
  final String name;
  const Dto({required this.name});
}

@RestController('/x')
@Produces(['application/xml'])
class XmlController {
  @Post()
  @Consumes(['application/xml', 'application/json'])
  Dto echo(@Body() Dto body) => body;
}
''',
      output: allOf([
        contains("decodeMapBody(\n    req,\n    consumes: const ['application/xml', 'application/json'],\n  )"),
        contains("produces: const ['application/xml']"),
        contains('negotiatedResponse('),
      ]),
    );
  });

  test('rejects @Consumes without a codec-decoded body', () async {
    await expectPart(
      '''
import 'package:diana_annotation/diana_annotation.dart';

part 'ctrl.diana.dart';

@RestController('/x')
class C {
  @Post()
  @Consumes(['application/xml'])
  String echo(@Body() String body) => body;
}
''',
      expectedErrors: [
        '@Consumes on C.echo requires a codec-decoded @Body parameter '
            '(Map, List or DTO); String, FormData and raw-request bodies '
            'bypass codecs.',
      ],
    );
  });

  test('rejects @Produces on non-negotiable returns and empty lists',
      () async {
    await expectPart(
      '''
import 'package:diana_annotation/diana_annotation.dart';

part 'ctrl.diana.dart';

@RestController('/x')
class C {
  @Get()
  @Produces(['application/xml'])
  String hello() => 'hi';
}
''',
      expectedErrors: [
        '@Produces on C.hello requires a JSON-encodable return (DTO, List '
            'of DTOs, Map or List); String, void and DianaResponse returns '
            'are not negotiated.',
      ],
    );

    await expectPart(
      '''
import 'package:diana_annotation/diana_annotation.dart';

part 'ctrl.diana.dart';

@RestController('/x')
class C {
  @Get()
  @Produces([])
  Map<String, dynamic> hello() => {};
}
''',
      expectedErrors: ['@Produces on C.hello lists no MIME types.'],
    );
  });
}
