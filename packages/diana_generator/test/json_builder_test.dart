import 'package:build_test/build_test.dart';
import 'package:diana_generator/src/part_builder.dart';
import 'package:test/test.dart';

import 'util/package_assets.dart';

void main() {
  late Map<String, String> deps;

  setUpAll(() async {
    deps = await dianaTestDeps();
  });

  Future<void> expectJson(
    String source, {
    Object? output,
    List<String> expectedErrors = const [],
  }) async {
    final logs = <String>[];
    await testBuilder(
      const DianaPartBuilder(),
      {...deps, 'a|lib/dto.dart': source},
      outputs: expectedErrors.isEmpty && output != null
          ? {'a|lib/dto.diana.dart': decodedMatches(output)}
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

  test('generates codecs for a kitchen-sink @Json class', () async {
    await expectJson(
      '''
import 'package:diana_annotation/diana_annotation.dart';

part 'dto.diana.dart';

enum Priority { low, high }

@Json()
class Tag {
  final String label;
  const Tag({required this.label});
}

class Legacy {
  const Legacy();
  factory Legacy.fromJson(Map<String, dynamic> json) => const Legacy();
  Map<String, dynamic> toJson() => {};
}

@Json()
class Task {
  final String title;

  @JsonField(name: 'prio')
  final Priority? priority;

  final DateTime createdAt;
  final DateTime? doneAt;
  final List<Tag> tags;
  final Map<String, int> counts;
  final Legacy? legacy;
  final double score;
  final List<String>? labels;

  const Task({
    required this.title,
    this.priority,
    required this.createdAt,
    this.doneAt,
    this.tags = const [],
    this.counts = const {},
    this.legacy,
    required this.score,
    this.labels,
  });
}
''',
      output: allOf([
        contains(r'Tag $TagFromJson(Map<String, dynamic> json)'),
        contains(r'Task $TaskFromJson(Map<String, dynamic> json)'),
        contains("title: json['title'] as String,"),
        contains("json['prio'] == null"),
        contains("Priority.values.byName(json['prio'] as String)"),
        contains("DateTime.parse(json['createdAt'] as String)"),
        contains("json['doneAt'] == null"),
        contains("DateTime.parse(json['doneAt'] as String)"),
        contains(r'$TagFromJson((e as Map).cast<String, dynamic>())'),
        contains('e.key as String: (e.value as num).toInt()'),
        contains("Legacy.fromJson((json['legacy'] as Map)"),
        contains("(json['score'] as num).toDouble()"),
        contains(r"'prio': value.priority?.name,"),
        contains("'createdAt': value.createdAt.toIso8601String(),"),
        contains(r'[for (final e in value.tags) $TagToJson(e)]'),
        contains("'legacy': value.legacy?.toJson(),"),
      ]),
    );
  });

  test('rejects unsupported field types with guidance', () async {
    await expectJson(
      '''
import 'dart:async';

import 'package:diana_annotation/diana_annotation.dart';

part 'dto.diana.dart';

@Json()
class Bad {
  final StreamController<int> controller;
  const Bad(this.controller);
}
''',
      expectedErrors: [
        'Unsupported field type StreamController<int> in @Json class Bad.',
      ],
    );
  });

  test('rejects constructor params without a matching field', () async {
    await expectJson(
      '''
import 'package:diana_annotation/diana_annotation.dart';

part 'dto.diana.dart';

@Json()
class Mismatch {
  final String a;
  const Mismatch(this.a, {int other = 0});
}
''',
      expectedErrors: [
        'Constructor parameter "other" of @Json class Mismatch has no '
            'matching field',
      ],
    );
  });
}
