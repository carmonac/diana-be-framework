import 'package:build/build.dart';
import 'package:dart_style/dart_style.dart';
import 'package:path/path.dart' as p;
import 'package:source_gen/source_gen.dart' show spanForElement;

import 'common.dart';
import 'emit/adapter_emitter.dart';
import 'emit/config_props_emitter.dart';
import 'emit/validator_emitter.dart';
import 'readers/adapter_reader.dart';
import 'readers/checkers.dart';
import 'readers/config_props_reader.dart';
import 'readers/library_reader.dart' show DianaSourceError;
import 'readers/validator_reader.dart';

/// Per-library builder that emits the `.diana.dart` part file containing
/// route adapters, DTO validators and configuration binders for the library.
class DianaPartBuilder implements Builder {
  const DianaPartBuilder();

  @override
  Map<String, List<String>> get buildExtensions => const {
        '.dart': ['.diana.dart'],
      };

  @override
  Future<void> build(BuildStep buildStep) async {
    final inputId = buildStep.inputId;
    if (!inputId.path.startsWith('lib/')) return;

    final source = await buildStep.readAsString(inputId);
    if (!dianaAnnotationPattern.hasMatch(source)) return;
    if (!await buildStep.resolver.isLibrary(inputId)) return;

    final library = await buildStep.resolver.libraryFor(inputId);

    final sections = <String>[];
    try {
      for (final cls in library.classes) {
        if (classNeedsValidator(cls)) {
          sections.add(emitValidator(readValidator(cls)));
        }
        if (configPropsChecker.firstAnnotationOf(cls) != null) {
          sections.add(emitConfigPropsBinder(readConfigProps(cls)));
        }
        if (restControllerChecker.firstAnnotationOf(cls) == null) continue;
        for (final adapter in readControllerAdapters(cls)) {
          sections.add(emitAdapter(adapter));
        }
      }
    } on DianaSourceError catch (e) {
      log.severe(spanForElement(e.element).message(e.message));
      return;
    }

    if (sections.isEmpty) return;

    final baseName = p.basename(inputId.path);
    final partName = p.basename(inputId.changeExtension('.diana.dart').path);
    if (!source.contains("part '$partName'")) {
      log.severe(
        '$baseName declares Diana members that need generated code, but is '
        "missing the part directive. Add:\n\npart '$partName';",
      );
      return;
    }

    final content = StringBuffer()
      ..writeln(generatedHeader)
      ..writeln("part of '$baseName';")
      ..writeln();
    for (final section in sections) {
      content
        ..writeln(section)
        ..writeln();
    }

    final formatted = DartFormatter(
      languageVersion: DartFormatter.latestLanguageVersion,
    ).format(content.toString());
    await buildStep.writeAsString(
      inputId.changeExtension('.diana.dart'),
      formatted,
    );
  }
}
