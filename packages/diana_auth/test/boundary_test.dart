import 'dart:io';

import 'package:test/test.dart';

Iterable<File> _dartFiles(String dir) => Directory(dir)
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'));

void main() {
  test('only diana_auth imports package:crypto (keeps crypto out of core)',
      () {
    final offenders = <String>[];
    for (final package in [
      'diana',
      'diana_annotation',
      'diana_generator',
      'diana_grpc',
    ]) {
      for (final file in _dartFiles('../$package/lib')) {
        if (file.readAsStringSync().contains("import 'package:crypto")) {
          offenders.add(file.path);
        }
      }
    }
    expect(offenders, isEmpty);
  });

  test('diana_auth never imports package:grpc', () {
    final offenders = [
      for (final file in _dartFiles('lib'))
        if (file.readAsStringSync().contains("import 'package:grpc"))
          file.path,
    ];
    expect(offenders, isEmpty);
  });

  test('the generator never imports diana_auth (URL-string-only rule)', () {
    final offenders = [
      for (final file in _dartFiles('../diana_generator/lib'))
        if (file.readAsStringSync().contains("import 'package:diana_auth"))
          file.path,
    ];
    expect(offenders, isEmpty);
  });
}
