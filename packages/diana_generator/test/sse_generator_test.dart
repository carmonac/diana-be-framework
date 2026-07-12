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

  test('emits sseResponse for both stream shapes', () async {
    await expectPart(
      '''
import 'package:diana_annotation/diana_annotation.dart';
import 'package:diana/diana.dart';

part 'ctrl.diana.dart';

@Json()
class Tick {
  final int n;
  const Tick({required this.n});
}

@RestController('/events')
class EventsController {
  @Get('/raw')
  Stream<ServerSentEvent> raw() => const Stream.empty();

  @Get('/dtos')
  Stream<Tick> dtos() => const Stream.empty();
}
''',
      output: allOf([
        contains('return sseResponse(req, result);'),
        contains(r'ServerSentEvent.json($TickToJson(e))'),
      ]),
    );
  });

  test('rejects unsupported stream element types', () async {
    await expectPart(
      '''
import 'package:diana_annotation/diana_annotation.dart';

part 'ctrl.diana.dart';

@RestController('/events')
class C {
  @Get()
  Stream<int> nums() => const Stream.empty();
}
''',
      expectedErrors: [
        'Route method C.nums returns Stream<int>; supported stream element '
            'types are ServerSentEvent or a DTO with toJson().',
      ],
    );
  });

  test('rejects @ResponseStatus and @Produces on SSE routes', () async {
    await expectPart(
      '''
import 'package:diana_annotation/diana_annotation.dart';
import 'package:diana/diana.dart';

part 'ctrl.diana.dart';

@RestController('/events')
class C {
  @Get()
  @ResponseStatus(201)
  Stream<ServerSentEvent> raw() => const Stream.empty();
}
''',
      expectedErrors: [
        '@ResponseStatus cannot be combined with a Stream return on C.raw; '
            'SSE responses are always 200.',
      ],
    );

    await expectPart(
      '''
import 'package:diana_annotation/diana_annotation.dart';
import 'package:diana/diana.dart';

part 'ctrl.diana.dart';

@RestController('/events')
class C {
  @Get()
  @Produces(['application/xml'])
  Stream<ServerSentEvent> raw() => const Stream.empty();
}
''',
      expectedErrors: [
        '@Produces cannot be combined with a Stream return on C.raw; SSE '
            'always produces text/event-stream.',
      ],
    );
  });
}
