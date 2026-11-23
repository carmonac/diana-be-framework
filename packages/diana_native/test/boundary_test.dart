import 'dart:io';

import 'package:test/test.dart';

Iterable<File> _dartFiles(String dir) => Directory(dir)
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'));

void main() {
  test('only diana_native imports package:relic_native', () {
    final offenders = <String>[];
    for (final package in [
      'diana',
      'diana_annotation',
      'diana_generator',
      'diana_grpc',
      'diana_auth',
      'diana_data',
      'diana_observability',
    ]) {
      for (final file in _dartFiles('../$package/lib')) {
        if (file.readAsStringSync().contains("import 'package:relic_native")) {
          offenders.add(file.path);
        }
      }
    }
    expect(offenders, isEmpty);
  });

  test('diana_native talks to Diana only through the public barrel', () {
    final offenders = [
      for (final file in _dartFiles('lib'))
        if (file.readAsStringSync().contains("import 'package:diana/src/"))
          file.path,
    ];
    expect(offenders, isEmpty);
  });

  test('the generator never imports diana_native (discovery by supertype)', () {
    final offenders = [
      for (final file in _dartFiles('../diana_generator/lib'))
        if (file.readAsStringSync().contains("import 'package:diana_native"))
          file.path,
    ];
    expect(offenders, isEmpty);
  });
}
