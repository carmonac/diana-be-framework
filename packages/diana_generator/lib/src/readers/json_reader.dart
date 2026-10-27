/// Reads `@Json` classes into plain [JsonClassModel]s.
library;

import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:collection/collection.dart';

import '../model/json_model.dart';
import 'checkers.dart';
import 'library_reader.dart' show DianaSourceError;

/// Whether [cls] carries `@Json` (adapters then use the generated codec).
bool isJsonClass(ClassElement cls) => jsonChecker.hasAnnotationOf(cls);

JsonClassModel readJsonClass(ClassElement cls) {
  final fields = <JsonFieldModel>[];
  for (final field in cls.fields) {
    if (field.isStatic || !field.isOriginDeclaration) continue;
    final rename = jsonFieldChecker
        .firstAnnotationOf(field)
        ?.getField('name')
        ?.toStringValue();
    fields.add(JsonFieldModel(
      fieldName: field.name!,
      jsonName: rename ?? field.name!,
      type: _typeModelOf(field.type, cls, field),
    ));
  }

  final ctor = cls.constructors
      .where((c) => c.isGenerative && c.name == 'new')
      .firstOrNull;
  if (ctor == null) {
    throw DianaSourceError(
      cls,
      '@Json class ${cls.name} has no public unnamed generative '
      'constructor.',
    );
  }
  final fieldNames = {for (final f in fields) f.fieldName};
  final ctorParams = <JsonCtorParam>[];
  for (final param in ctor.formalParameters) {
    if (!fieldNames.contains(param.name)) {
      throw DianaSourceError(
        param,
        'Constructor parameter "${param.name}" of @Json class ${cls.name} '
        'has no matching field; @Json builds instances by matching '
        'constructor parameters to fields by name.',
      );
    }
    ctorParams.add(JsonCtorParam(name: param.name!, isNamed: param.isNamed));
  }

  return JsonClassModel(
    className: cls.name!,
    fields: fields,
    ctorParams: ctorParams,
  );
}

JsonTypeModel _typeModelOf(DartType type, ClassElement cls, Element context) {
  final nullable = type.nullabilitySuffix == NullabilitySuffix.question;

  if (type is DynamicType) {
    return const JsonTypeModel(kind: JsonKind.dynamic_, nullable: true);
  }
  if (type is! InterfaceType) return _unsupported(type, cls, context);

  if (type.isDartCoreString) {
    return JsonTypeModel(kind: JsonKind.string, nullable: nullable);
  }
  if (type.isDartCoreInt) {
    return JsonTypeModel(kind: JsonKind.integer, nullable: nullable);
  }
  if (type.isDartCoreDouble) {
    return JsonTypeModel(kind: JsonKind.double_, nullable: nullable);
  }
  if (type.isDartCoreBool) {
    return JsonTypeModel(kind: JsonKind.boolean, nullable: nullable);
  }
  if (type.isDartCoreNum) {
    return JsonTypeModel(kind: JsonKind.number, nullable: nullable);
  }
  final element = type.element;
  if (element.name == 'DateTime' &&
      element.library.uri.toString() == 'dart:core') {
    return JsonTypeModel(kind: JsonKind.dateTime, nullable: nullable);
  }
  if (element is EnumElement) {
    return JsonTypeModel(
      kind: JsonKind.enum_,
      nullable: nullable,
      className: element.name,
    );
  }
  if (type.isDartCoreList) {
    return JsonTypeModel(
      kind: JsonKind.list,
      nullable: nullable,
      element: _typeModelOf(type.typeArguments.single, cls, context),
    );
  }
  if (type.isDartCoreMap) {
    final key = type.typeArguments.first;
    if (key is! InterfaceType || !key.isDartCoreString) {
      throw DianaSourceError(
        context,
        '@Json map fields must have String keys — got '
        '${type.getDisplayString()} in ${cls.name}.',
      );
    }
    return JsonTypeModel(
      kind: JsonKind.map,
      nullable: nullable,
      element: _typeModelOf(type.typeArguments[1], cls, context),
    );
  }
  if (element is ClassElement) {
    if (isJsonClass(element)) {
      return JsonTypeModel(
        kind: JsonKind.jsonClass,
        nullable: nullable,
        className: element.name,
      );
    }
    final hasFromJson = element.constructors.any((c) => c.name == 'fromJson') ||
        element.methods.any((m) => m.isStatic && m.name == 'fromJson');
    final hasToJson = [element, ...element.allSupertypes.map((s) => s.element)]
        .expand((e) => e.methods)
        .any((m) => m.name == 'toJson');
    if (hasFromJson && hasToJson) {
      return JsonTypeModel(
        kind: JsonKind.conventionClass,
        nullable: nullable,
        className: element.name,
      );
    }
  }
  return _unsupported(type, cls, context);
}

Never _unsupported(DartType type, ClassElement cls, Element context) =>
    throw DianaSourceError(
      context,
      'Unsupported field type ${type.getDisplayString()} in @Json class '
      '${cls.name}. Supported: String, int, double, bool, num, dynamic, '
      'DateTime, enums, List/Map<String, _> of supported types, and nested '
      'classes that are @Json or expose fromJson/toJson.',
    );
