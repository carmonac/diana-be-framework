import 'dart:io';

import 'package:test/test.dart';

Iterable<File> _dartFiles(String dir) => Directory(dir)
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'));

void main() {
  test('only diana_observability imports package:opentelemetry', () {
    final offenders = <String>[];
    for (final package in [
      'diana',
      'diana_annotation',
      'diana_generator',
      'diana_grpc',
      'diana_auth',
      'diana_data',
    ]) {
      for (final file in _dartFiles('../$package/lib')) {
        if (file.readAsStringSync().contains("import 'package:opentelemetry")) {
          offenders.add(file.path);
        }
      }
    }
    expect(offenders, isEmpty);
  });

  test('the generator never imports diana_observability (URL-string rule)', () {
    final offenders = [
      for (final file in _dartFiles('../diana_generator/lib'))
        if (file
            .readAsStringSync()
            .contains("import 'package:diana_observability"))
          file.path,
    ];
    expect(offenders, isEmpty);
  });
}
