import 'dart:convert';

import 'package:build/build.dart';
import 'package:source_gen/source_gen.dart' show spanForElement;

import 'common.dart';
import 'readers/library_reader.dart';

/// Per-library builder that extracts a `LibrarySummary` describing every
/// Diana-annotated declaration, serialized as a hidden `.diana.json` asset
/// for the aggregating bootstrap builder.
class DianaMetadataBuilder implements Builder {
  const DianaMetadataBuilder();

  @override
  Map<String, List<String>> get buildExtensions => const {
        '.dart': ['.diana.json'],
      };

  @override
  Future<void> build(BuildStep buildStep) async {
    final inputId = buildStep.inputId;
    if (!inputId.path.startsWith('lib/')) return;

    final source = await buildStep.readAsString(inputId);
    if (!dianaAnnotationPattern.hasMatch(source)) return;
    if (!await buildStep.resolver.isLibrary(inputId)) return;

    final library = await buildStep.resolver.libraryFor(inputId);
    try {
      final summary = readLibrary(library);
      if (summary.isEmpty) return;
      await buildStep.writeAsString(
        inputId.changeExtension('.diana.json'),
        jsonEncode(summary.toJson()),
      );
    } on DianaSourceError catch (e) {
      log.severe(spanForElement(e.element).message(e.message));
    }
  }
}
