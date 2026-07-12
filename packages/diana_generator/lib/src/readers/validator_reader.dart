/// Reads constraint annotations on DTO fields into plain [ValidatorModel]s.
library;

import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:source_gen/source_gen.dart';

import '../model/validator_model.dart';
import 'checkers.dart';
import 'library_reader.dart' show DianaSourceError;

/// Whether [cls] needs a generated `$XValidator`.
bool classNeedsValidator(ClassElement cls) => cls.fields.any(
      (f) =>
          validChecker.hasAnnotationOf(f) ||
          constraintCheckers.any((c) => c.hasAnnotationOf(f)),
    );

ValidatorModel readValidator(ClassElement cls) {
  final fields = <FieldChecks>[];
  for (final field in cls.fields) {
    if (field.isStatic) continue;
    final checks = <CheckModel>[];
    final type = field.type;

    void addSimple(
      TypeChecker checker,
      CheckKind kind, {
      bool Function(DartType)? applicable,
      String? requirement,
    }) {
      final ann = checker.firstAnnotationOf(field);
      if (ann == null) return;
      if (applicable != null && !applicable(type)) {
        throw DianaSourceError(
          field,
          '@${kind.annotationName} on ${cls.name}.${field.name} requires a '
          '$requirement field — got ${type.getDisplayString()}.',
        );
      }
      checks.add(CheckModel(
        kind: kind,
        message: ann.getField('message')?.toStringValue(),
      ));
    }

    bool isString(DartType t) => t is InterfaceType && t.isDartCoreString;
    bool isNum(DartType t) =>
        t is InterfaceType &&
        (t.isDartCoreNum || t.isDartCoreInt || t.isDartCoreDouble);
    bool isSized(DartType t) =>
        t is InterfaceType &&
        (t.isDartCoreString ||
            t.isDartCoreList ||
            t.isDartCoreMap ||
            t.isDartCoreSet);

    addSimple(notNullChecker, CheckKind.notNull);
    addSimple(notEmptyChecker, CheckKind.notEmpty,
        applicable: isSized, requirement: 'String, List, Set or Map');
    addSimple(notBlankChecker, CheckKind.notBlank,
        applicable: isString, requirement: 'String');
    addSimple(emailChecker, CheckKind.email,
        applicable: isString, requirement: 'String');

    final min = minChecker.firstAnnotationOf(field);
    if (min != null) {
      if (!isNum(type)) {
        throw DianaSourceError(
          field,
          '@Min on ${cls.name}.${field.name} requires a numeric field — got '
          '${type.getDisplayString()}.',
        );
      }
      checks.add(CheckModel(
        kind: CheckKind.min,
        numArg: _numValue(min.getField('value')),
        message: min.getField('message')?.toStringValue(),
      ));
    }
    final max = maxChecker.firstAnnotationOf(field);
    if (max != null) {
      if (!isNum(type)) {
        throw DianaSourceError(
          field,
          '@Max on ${cls.name}.${field.name} requires a numeric field — got '
          '${type.getDisplayString()}.',
        );
      }
      checks.add(CheckModel(
        kind: CheckKind.max,
        numArg: _numValue(max.getField('value')),
        message: max.getField('message')?.toStringValue(),
      ));
    }
    final size = sizeChecker.firstAnnotationOf(field);
    if (size != null) {
      if (!isSized(type)) {
        throw DianaSourceError(
          field,
          '@Size on ${cls.name}.${field.name} requires a String, List, Set '
          'or Map field — got ${type.getDisplayString()}.',
        );
      }
      checks.add(CheckModel(
        kind: CheckKind.size,
        minArg: size.getField('min')?.toIntValue(),
        maxArg: size.getField('max')?.toIntValue(),
        message: size.getField('message')?.toStringValue(),
      ));
    }
    final pattern = patternChecker.firstAnnotationOf(field);
    if (pattern != null) {
      if (!isString(type)) {
        throw DianaSourceError(
          field,
          '@Pattern on ${cls.name}.${field.name} requires a String field — '
          'got ${type.getDisplayString()}.',
        );
      }
      checks.add(CheckModel(
        kind: CheckKind.pattern,
        stringArg: pattern.getField('regex')!.toStringValue(),
        message: pattern.getField('message')?.toStringValue(),
      ));
    }

    CascadeModel? cascade;
    if (validChecker.hasAnnotationOf(field)) {
      cascade = _readCascade(cls, field);
    }

    if (checks.isEmpty && cascade == null) continue;
    fields.add(FieldChecks(
      fieldName: field.name!,
      nullable: field.type.getDisplayString().endsWith('?'),
      checks: checks,
      cascade: cascade,
    ));
  }
  return ValidatorModel(className: cls.name!, fields: fields);
}

CascadeModel _readCascade(ClassElement cls, FieldElement field) {
  var type = field.type;
  var isList = false;
  if (type is InterfaceType && type.isDartCoreList) {
    isList = true;
    type = type.typeArguments.single;
  }
  final target = type is InterfaceType ? type.element : null;
  if (target is! ClassElement || !classNeedsValidator(target)) {
    throw DianaSourceError(
      field,
      '@Valid on ${cls.name}.${field.name} cascades into '
      '${type.getDisplayString()}, which has no constraint annotations.',
    );
  }
  return CascadeModel(dtoName: target.name!, isList: isList);
}

num _numValue(DartObject? value) =>
    value?.toIntValue() ?? value?.toDoubleValue() ?? 0;
