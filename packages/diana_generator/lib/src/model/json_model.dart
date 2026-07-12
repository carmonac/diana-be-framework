/// Plain-data model of a generated `@Json` codec. Local to the part builder.
library;

enum JsonKind {
  string,
  integer,
  double_,
  boolean,
  number,
  dynamic_,
  dateTime,
  enum_,

  /// Nested `@Json` class — encoded via its generated `$XFromJson`/`$XToJson`.
  jsonClass,

  /// Nested class following the `fromJson`/`toJson` convention.
  conventionClass,
  list,
  map,
}

class JsonTypeModel {
  final JsonKind kind;
  final bool nullable;

  /// Element type for lists, value type for maps.
  final JsonTypeModel? element;

  /// Type name for enums and nested classes.
  final String? className;

  const JsonTypeModel({
    required this.kind,
    this.nullable = false,
    this.element,
    this.className,
  });
}

class JsonFieldModel {
  final String fieldName;

  /// JSON key (`@JsonField(name: ...)` or the field name).
  final String jsonName;
  final JsonTypeModel type;

  const JsonFieldModel({
    required this.fieldName,
    required this.jsonName,
    required this.type,
  });
}

class JsonCtorParam {
  final String name;
  final bool isNamed;

  const JsonCtorParam({required this.name, required this.isNamed});
}

class JsonClassModel {
  final String className;
  final List<JsonFieldModel> fields;

  /// Constructor parameters in declaration order; each must match a field.
  final List<JsonCtorParam> ctorParams;

  const JsonClassModel({
    required this.className,
    required this.fields,
    required this.ctorParams,
  });

  JsonFieldModel fieldNamed(String name) =>
      fields.firstWhere((f) => f.fieldName == name);
}
