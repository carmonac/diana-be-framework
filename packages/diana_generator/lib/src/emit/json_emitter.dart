/// Emits `$XFromJson`/`$XToJson` functions into the DTO's part file.
///
/// Public (like `$XValidator`) so route adapters in other libraries can call
/// them.
library;

import '../model/json_model.dart';

String emitJsonCodecs(JsonClassModel model) {
  final name = model.className;
  final buffer = StringBuffer();

  // fromJson
  buffer
      .writeln('$name \$${name}FromJson(Map<String, dynamic> json) => $name(');
  for (final param in model.ctorParams) {
    final field = model.fieldNamed(param.name);
    final label = param.isNamed ? '${param.name}: ' : '';
    buffer.writeln(
        '      $label${_decode(field.type, "json['${field.jsonName}']")},');
  }
  buffer
    ..writeln('    );')
    ..writeln();

  // toJson
  buffer.writeln(
      'Map<String, dynamic> \$${name}ToJson($name value) => <String, dynamic>{');
  for (final field in model.fields) {
    buffer.writeln(
        "      '${field.jsonName}': ${_encode(field.type, 'value.${field.fieldName}')},");
  }
  buffer.writeln('    };');
  return buffer.toString();
}

String _decode(JsonTypeModel type, String src) {
  final suffix = type.nullable ? '?' : '';
  switch (type.kind) {
    case JsonKind.string:
      return '$src as String$suffix';
    case JsonKind.integer:
      return type.nullable
          ? '($src as num?)?.toInt()'
          : '($src as num).toInt()';
    case JsonKind.double_:
      return type.nullable
          ? '($src as num?)?.toDouble()'
          : '($src as num).toDouble()';
    case JsonKind.boolean:
      return '$src as bool$suffix';
    case JsonKind.number:
      return '$src as num$suffix';
    case JsonKind.dynamic_:
      return src;
    case JsonKind.dateTime:
      final parse = 'DateTime.parse($src as String)';
      return type.nullable ? '$src == null ? null : $parse' : parse;
    case JsonKind.enum_:
      final parse = '${type.className}.values.byName($src as String)';
      return type.nullable ? '$src == null ? null : $parse' : parse;
    case JsonKind.jsonClass:
      final parse =
          '\$${type.className}FromJson(($src as Map).cast<String, dynamic>())';
      return type.nullable ? '$src == null ? null : $parse' : parse;
    case JsonKind.conventionClass:
      final parse =
          '${type.className}.fromJson(($src as Map).cast<String, dynamic>())';
      return type.nullable ? '$src == null ? null : $parse' : parse;
    case JsonKind.list:
      final decode =
          '[for (final e in $src as List) ${_decode(type.element!, 'e')}]';
      return type.nullable ? '$src == null ? null : $decode' : decode;
    case JsonKind.map:
      final decode = '{for (final e in ($src as Map).entries) '
          'e.key as String: ${_decode(type.element!, 'e.value')}}';
      return type.nullable ? '$src == null ? null : $decode' : decode;
  }
}

String _encode(JsonTypeModel type, String src) {
  final q = type.nullable ? '?' : '';
  switch (type.kind) {
    case JsonKind.string:
    case JsonKind.integer:
    case JsonKind.double_:
    case JsonKind.boolean:
    case JsonKind.number:
    case JsonKind.dynamic_:
      return src;
    case JsonKind.dateTime:
      return '$src$q.toIso8601String()';
    case JsonKind.enum_:
      return '$src$q.name';
    case JsonKind.jsonClass:
      final encode = '\$${type.className}ToJson';
      return type.nullable
          ? '$src == null ? null : $encode($src!)'
          : '$encode($src)';
    case JsonKind.conventionClass:
      return '$src$q.toJson()';
    case JsonKind.list:
      final source = type.nullable ? '$src!' : src;
      final encode =
          '[for (final e in $source) ${_encode(type.element!, 'e')}]';
      return type.nullable ? '$src == null ? null : $encode' : encode;
    case JsonKind.map:
      final source = type.nullable ? '$src!' : src;
      final encode = '{for (final e in $source.entries) '
          'e.key: ${_encode(type.element!, 'e.value')}}';
      return type.nullable ? '$src == null ? null : $encode' : encode;
  }
}
