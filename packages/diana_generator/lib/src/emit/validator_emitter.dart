/// Emits `$XValidator` classes into the DTO's part file.
///
/// Validators are public so route adapters in other libraries can invoke
/// them (they live in the same library as the DTO they validate).
library;

import '../model/validator_model.dart';

String emitValidator(ValidatorModel model) {
  final name = model.className;
  final buffer = StringBuffer()
    ..writeln('class \$${name}Validator implements Validator<$name> {')
    ..writeln('  const \$${name}Validator();')
    ..writeln()
    ..writeln('  @override')
    ..writeln('  ValidationResult validate($name value) {')
    ..writeln('    final errors = <FieldError>[];');

  for (final field in model.fields) {
    final access = 'value.${field.fieldName}';
    for (final check in field.checks) {
      buffer.writeln('    ${_check(check, access, field.fieldName)}');
    }
    final cascade = field.cascade;
    if (cascade != null) {
      _emitCascade(buffer, field, cascade);
    }
  }

  buffer
    ..writeln('    return ValidationResult(errors);')
    ..writeln('  }')
    ..writeln('}');
  return buffer.toString();
}

String _check(CheckModel check, String access, String fieldName) {
  final field = _literal(fieldName);
  final message =
      check.message == null ? '' : ', message: ${_literal(check.message!)}';
  return switch (check.kind) {
    CheckKind.notNull => 'checkNotNull($access, $field, errors$message);',
    CheckKind.notEmpty => 'checkNotEmpty($access, $field, errors$message);',
    CheckKind.notBlank => 'checkNotBlank($access, $field, errors$message);',
    CheckKind.email => 'checkEmail($access, $field, errors$message);',
    CheckKind.min =>
      'checkMin($access, ${check.numArg}, $field, errors$message);',
    CheckKind.max =>
      'checkMax($access, ${check.numArg}, $field, errors$message);',
    CheckKind.size => 'checkSize($access, $field, errors'
        '${check.minArg == null ? '' : ', min: ${check.minArg}'}'
        '${check.maxArg == null ? '' : ', max: ${check.maxArg}'}'
        '$message);',
    CheckKind.pattern =>
      'checkPattern($access, ${_literal(check.stringArg!)}, $field, '
          'errors$message);',
  };
}

void _emitCascade(StringBuffer buffer, FieldChecks field, CascadeModel c) {
  final access = 'value.${field.fieldName}';
  final validator = 'const \$${c.dtoName}Validator()';
  final fieldLit = _literal(field.fieldName);
  if (c.isList) {
    final items = field.nullable ? '$access ?? const []' : access;
    buffer
      ..writeln('    {')
      ..writeln('      var i = 0;')
      ..writeln('      for (final item in $items) {')
      ..writeln('        mergeNested($validator.validate(item), '
          "'${field.fieldName}[\$i]', errors);")
      ..writeln('        i++;')
      ..writeln('      }')
      ..writeln('    }');
  } else if (field.nullable) {
    buffer
      ..writeln('    if ($access != null) {')
      ..writeln('      mergeNested($validator.validate($access!), '
          '$fieldLit, errors);')
      ..writeln('    }');
  } else {
    buffer.writeln(
        '    mergeNested($validator.validate($access), $fieldLit, errors);');
  }
}

/// Escapes a string into a single-quoted Dart literal.
String _literal(String value) {
  final escaped = value
      .replaceAll(r'\', r'\\')
      .replaceAll(r'$', r'\$')
      .replaceAll("'", r"\'")
      .replaceAll('\n', r'\n');
  return "'$escaped'";
}
