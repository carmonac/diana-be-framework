import 'dart:io';

import 'package:test/test.dart';

/// Architectural guarantee: the HTTP engine (relic) is confined to the
/// adapter. If this fails, engine types are leaking into Diana's surface.
void main() {
  test('only the adapter imports the HTTP engine', () {
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      if (entity.path.endsWith('src/adapter/relic_adapter.dart')) continue;
      final source = entity.readAsStringSync();
      if (source.contains("import 'package:relic") ||
          source.contains('import "package:relic')) {
        offenders.add(entity.path);
      }
    }
    expect(offenders, isEmpty,
        reason: 'relic may only be imported by the adapter');
  });
}
