/// Plain-data model of a generated DTO validator. Local to the part builder.
library;

enum CheckKind {
  notNull('NotNull'),
  notEmpty('NotEmpty'),
  notBlank('NotBlank'),
  min('Min'),
  max('Max'),
  size('Size'),
  pattern('Pattern'),
  email('Email');

  final String annotationName;
  const CheckKind(this.annotationName);
}

class CheckModel {
  final CheckKind kind;
  final num? numArg;
  final int? minArg;
  final int? maxArg;
  final String? stringArg;
  final String? message;

  const CheckModel({
    required this.kind,
    this.numArg,
    this.minArg,
    this.maxArg,
    this.stringArg,
    this.message,
  });
}

class CascadeModel {
  final String dtoName;
  final bool isList;

  const CascadeModel({required this.dtoName, required this.isList});
}

class FieldChecks {
  final String fieldName;
  final bool nullable;
  final List<CheckModel> checks;
  final CascadeModel? cascade;

  const FieldChecks({
    required this.fieldName,
    required this.nullable,
    required this.checks,
    this.cascade,
  });
}

class ValidatorModel {
  final String className;
  final List<FieldChecks> fields;

  const ValidatorModel({required this.className, required this.fields});
}
