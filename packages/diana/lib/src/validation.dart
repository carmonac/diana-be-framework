/// Validation runtime targeted by generated `$XValidator` classes.
///
/// Generated code stays one line per constraint; the semantics and default
/// messages live here. All helpers skip `null` values — requiredness is
/// expressed with `@NotNull` (or a non-nullable Dart type).
library;

import 'exceptions.dart';

/// Validates instances of [T]. Implementations are generated from constraint
/// annotations on DTO fields.
abstract interface class Validator<T> {
  ValidationResult validate(T value);
}

class ValidationResult {
  final List<FieldError> errors;

  const ValidationResult(this.errors);

  bool get isValid => errors.isEmpty;

  /// Throws [ValidationException] (mapped to a structured 400) when any
  /// constraint failed.
  void throwIfInvalid() {
    if (errors.isNotEmpty) throw ValidationException(errors);
  }
}

void checkNotNull(
  Object? value,
  String field,
  List<FieldError> errors, {
  String? message,
}) {
  if (value == null) {
    errors.add(FieldError(field, message ?? 'must not be null'));
  }
}

void checkNotEmpty(
  Object? value,
  String field,
  List<FieldError> errors, {
  String? message,
}) {
  if (value == null) return;
  final empty = switch (value) {
    String s => s.isEmpty,
    Iterable<Object?> i => i.isEmpty,
    Map<Object?, Object?> m => m.isEmpty,
    _ => false,
  };
  if (empty) errors.add(FieldError(field, message ?? 'must not be empty'));
}

void checkNotBlank(
  String? value,
  String field,
  List<FieldError> errors, {
  String? message,
}) {
  if (value == null) return;
  if (value.trim().isEmpty) {
    errors.add(FieldError(field, message ?? 'must not be blank'));
  }
}

void checkMin(
  num? value,
  num min,
  String field,
  List<FieldError> errors, {
  String? message,
}) {
  if (value == null) return;
  if (value < min) {
    errors.add(FieldError(field, message ?? 'must be at least $min'));
  }
}

void checkMax(
  num? value,
  num max,
  String field,
  List<FieldError> errors, {
  String? message,
}) {
  if (value == null) return;
  if (value > max) {
    errors.add(FieldError(field, message ?? 'must be at most $max'));
  }
}

void checkSize(
  Object? value,
  String field,
  List<FieldError> errors, {
  int? min,
  int? max,
  String? message,
}) {
  if (value == null) return;
  final length = switch (value) {
    String s => s.length,
    Iterable<Object?> i => i.length,
    Map<Object?, Object?> m => m.length,
    _ => null,
  };
  if (length == null) return;
  if ((min != null && length < min) || (max != null && length > max)) {
    final range = switch ((min, max)) {
      (final int a, final int b) => 'between $a and $b',
      (final int a, null) => 'at least $a',
      (null, final int b) => 'at most $b',
      _ => '',
    };
    errors.add(FieldError(field, message ?? 'size must be $range'));
  }
}

void checkPattern(
  String? value,
  String regex,
  String field,
  List<FieldError> errors, {
  String? message,
}) {
  if (value == null) return;
  if (!RegExp(regex).hasMatch(value)) {
    errors.add(FieldError(field, message ?? 'must match pattern $regex'));
  }
}

final _emailRegExp = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

void checkEmail(
  String? value,
  String field,
  List<FieldError> errors, {
  String? message,
}) {
  if (value == null) return;
  if (!_emailRegExp.hasMatch(value)) {
    errors.add(FieldError(field, message ?? 'must be a valid email address'));
  }
}

/// Merges the [nested] result of a cascaded (`@Valid`) field into [errors],
/// prefixing field names (`address.street`, `items[2].name`).
void mergeNested(
  ValidationResult nested,
  String prefix,
  List<FieldError> errors,
) {
  for (final error in nested.errors) {
    errors.add(FieldError('$prefix.${error.field}', error.message));
  }
}
