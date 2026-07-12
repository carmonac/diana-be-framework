/// Reads `@ConfigurationProperties` classes into plain models for the
/// generated config binder.
library;

import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:collection/collection.dart';

import '../model/config_props_model.dart';
import 'checkers.dart';
import 'library_reader.dart' show DianaSourceError;

ConfigPropsModel readConfigProps(ClassElement cls) {
  final ann = configPropsChecker.firstAnnotationOf(cls)!;
  final prefix = ann.getField('prefix')?.toStringValue() ?? '';

  final ctor = cls.constructors
      .where((c) => c.isGenerative && c.name == 'new')
      .firstOrNull;
  if (ctor == null) {
    throw DianaSourceError(
      cls,
      '@ConfigurationProperties class ${cls.name} has no public unnamed '
      'generative constructor.',
    );
  }

  final params = <ConfigPropsParam>[];
  for (final param in ctor.formalParameters) {
    final type = param.type;
    final bindable = type is InterfaceType &&
        (type.isDartCoreString ||
            type.isDartCoreInt ||
            type.isDartCoreDouble ||
            type.isDartCoreBool ||
            type.isDartCoreNum);
    if (!bindable) {
      throw DianaSourceError(
        param,
        'Constructor parameter "${param.name}" of @ConfigurationProperties '
        'class ${cls.name} must be String, int, double, bool or num '
        '(nullable for optional keys) — got ${type.getDisplayString()}.',
      );
    }
    params.add(ConfigPropsParam(
      name: param.name!,
      isNamed: param.isNamed,
      typeDisplay: type.getDisplayString(),
    ));
  }

  return ConfigPropsModel(
    className: cls.name!,
    prefix: prefix,
    params: params,
  );
}
