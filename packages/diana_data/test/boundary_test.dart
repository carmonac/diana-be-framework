import 'dart:io';

import 'package:test/test.dart';

Iterable<File> _dartFiles(String dir) => Directory(dir)
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'));

void main() {
  test('only diana_data imports package:knex_dart (keeps it out of core)',
      () {
    final offenders = <String>[];
    for (final package in [
      'diana',
      'diana_annotation',
      'diana_generator',
      'diana_grpc',
      'diana_auth',
    ]) {
      for (final file in _dartFiles('../$package/lib')) {
        if (file.readAsStringSync().contains("import 'package:knex_dart")) {
          offenders.add(file.path);
        }
      }
    }
    expect(offenders, isEmpty);
  });

  test('the generator never imports diana_data (URL-string-only rule)', () {
    final offenders = [
      for (final file in _dartFiles('../diana_generator/lib'))
        if (file.readAsStringSync().contains("import 'package:diana_data"))
          file.path,
    ];
    expect(offenders, isEmpty);
  });
}
