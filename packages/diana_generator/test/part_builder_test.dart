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
    String controllerSource, {
    Object? output,
    List<String> expectedErrors = const [],
  }) async {
    final logs = <String>[];
    await testBuilder(
      const DianaPartBuilder(),
      {...deps, 'a|lib/ctrl.dart': controllerSource},
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

  test('generates adapters with param binding and JSON serialization',
      () async {
    await expectPart(
      '''
import 'package:diana_annotation/diana_annotation.dart';

part 'ctrl.diana.dart';

class Dto {
  Dto();
  factory Dto.fromJson(Map<String, dynamic> json) => Dto();
  Map<String, dynamic> toJson() => {};
}

@RestController('/things')
class ThingController {
  @Get('/:id')
  Dto get(@PathParam() int id, @QueryParam('v', '1') int version,
          @Header('x-k') String? key) =>
      Dto();

  @Post()
  @ResponseStatus(201)
  Future<List<Dto>> bulk(@Body() List<Dto> body) async => body;
}
''',
      output: allOf(
        contains("final \$a0 = bindPathParam<int>(req, 'id');"),
        contains("bindQueryParam<int>(req, 'v', defaultValue: '1')"),
        contains("bindHeader<String?>(req, 'x-k')"),
        contains('Dto.fromJson((e as Map).cast<String, dynamic>())'),
        contains('await c.bulk(\$a0)'),
        contains('statusCode: 201'),
      ),
    );
  });

  test('rejects @Body DTOs without fromJson', () async {
    await expectPart(
      '''
import 'package:diana_annotation/diana_annotation.dart';

part 'ctrl.diana.dart';

class NoJson {}

@RestController()
class C {
  @Post()
  void create(@Body() NoJson body) {}
}
''',
      expectedErrors: [
        'NoJson is used with @Body in C.create but has no '
            '`factory NoJson.fromJson(Map<String, dynamic>)`.',
      ],
    );
  });

  test('rejects return types without toJson', () async {
    await expectPart(
      '''
import 'package:diana_annotation/diana_annotation.dart';

part 'ctrl.diana.dart';

class NoJson {}

@RestController()
class C {
  @Get()
  NoJson get() => NoJson();
}
''',
      expectedErrors: [
        'NoJson is returned from route method C.get but has no '
            '`Map<String, dynamic> toJson()`.',
      ],
    );
  });

  test('rejects unannotated route parameters', () async {
    await expectPart(
      '''
import 'package:diana_annotation/diana_annotation.dart';

part 'ctrl.diana.dart';

@RestController()
class C {
  @Get()
  String get(int id) => '';
}
''',
      expectedErrors: [
        'Parameter "id" of route method C.get needs exactly one binding '
            'annotation',
      ],
    );
  });

  test('rejects nullable path parameters', () async {
    await expectPart(
      '''
import 'package:diana_annotation/diana_annotation.dart';

part 'ctrl.diana.dart';

@RestController()
class C {
  @Get('/:id')
  String get(@PathParam() int? id) => '';
}
''',
      expectedErrors: ['use a non-nullable type'],
    );
  });

  test('requires the part directive when code must be generated', () async {
    await expectPart(
      '''
import 'package:diana_annotation/diana_annotation.dart';

@RestController()
class C {
  @Get()
  String get() => '';
}
''',
      expectedErrors: ["missing the part directive. Add:\n\npart 'ctrl.diana.dart';"],
    );
  });
}
