import 'package:meta/meta_meta.dart';

/// Constrains a field to be non-null. All other constraints skip `null`
/// values, so combine them with [NotNull] (or a non-nullable type) when the
/// field is required.
@Target({TargetKind.field})
class NotNull {
  final String? message;
  const NotNull({this.message});
}

/// Constrains a `String`, `List` or `Map` field to be non-empty.
@Target({TargetKind.field})
class NotEmpty {
  final String? message;
  const NotEmpty({this.message});
}

/// Constrains a `String` field to contain at least one non-whitespace
/// character.
@Target({TargetKind.field})
class NotBlank {
  final String? message;
  const NotBlank({this.message});
}

/// Constrains a numeric field to be `>= value`.
@Target({TargetKind.field})
class Min {
  final num value;
  final String? message;
  const Min(this.value, {this.message});
}

/// Constrains a numeric field to be `<= value`.
@Target({TargetKind.field})
class Max {
  final num value;
  final String? message;
  const Max(this.value, {this.message});
}

/// Constrains the length of a `String`, `List` or `Map` field.
@Target({TargetKind.field})
class Size {
  final int? min;
  final int? max;
  final String? message;
  const Size({this.min, this.max, this.message});
}

/// Constrains a `String` field to fully match a regular expression.
///
/// Note: this intentionally shadows `dart:core`'s `Pattern` in files that
/// import Diana, mirroring Jakarta Bean Validation's `@Pattern`. Use a
/// prefixed import if you need the core type in the same file.
@Target({TargetKind.field})
class Pattern {
  final String regex;
  final String? message;
  const Pattern(this.regex, {this.message});
}

/// Constrains a `String` field to look like an email address.
@Target({TargetKind.field})
class Email {
  final String? message;
  const Email({this.message});
}

/// Cascades validation into a nested DTO field (or a `List` of DTOs).
@Target({TargetKind.field})
class Valid {
  const Valid();
}
