import 'package:diana/diana.dart';
import 'package:test/test.dart';

void main() {
  List<FieldError> errs() => [];

  test('checkNotNull flags nulls, others skip nulls', () {
    final errors = errs();
    checkNotNull(null, 'a', errors);
    checkNotBlank(null, 'b', errors);
    checkNotEmpty(null, 'c', errors);
    checkMin(null, 1, 'd', errors);
    checkMax(null, 1, 'e', errors);
    checkSize(null, 'f', errors, min: 1);
    checkPattern(null, '^x', 'g', errors);
    checkEmail(null, 'h', errors);
    expect(errors.map((e) => e.field), ['a']);
    expect(errors.single.message, 'must not be null');
  });

  test('string constraints', () {
    final errors = errs();
    checkNotBlank('   ', 'title', errors, message: 'title is required');
    checkNotEmpty('', 'tag', errors);
    checkPattern('ABC', r'^[a-z]+$', 'handle', errors);
    checkEmail('not-an-email', 'mail', errors);
    expect(errors.map((e) => e.message), [
      'title is required',
      'must not be empty',
      r'must match pattern ^[a-z]+$',
      'must be a valid email address',
    ]);
  });

  test('numeric and size constraints', () {
    final errors = errs();
    checkMin(0, 1, 'priority', errors);
    checkMax(9, 5, 'priority', errors);
    checkSize('x', 'name', errors, min: 2, max: 5);
    checkSize([1, 2, 3], 'items', errors, max: 2);
    expect(errors.map((e) => e.message), [
      'must be at least 1',
      'must be at most 5',
      'size must be between 2 and 5',
      'size must be at most 2',
    ]);
  });

  test('ValidationResult.throwIfInvalid throws with grouped fields', () {
    final result = ValidationResult([
      const FieldError('title', 'must not be blank'),
      const FieldError('title', 'size must be at most 5'),
      const FieldError('priority', 'must be at least 1'),
    ]);
    expect(result.isValid, isFalse);
    expect(
      result.throwIfInvalid,
      throwsA(isA<ValidationException>().having(
        (e) => e.fieldMap,
        'fieldMap',
        {
          'title': ['must not be blank', 'size must be at most 5'],
          'priority': ['must be at least 1'],
        },
      )),
    );
    expect(const ValidationResult([]).isValid, isTrue);
    const ValidationResult([]).throwIfInvalid();
  });

  test('mergeNested prefixes field names', () {
    final errors = errs();
    mergeNested(
      const ValidationResult([FieldError('street', 'must not be blank')]),
      'address',
      errors,
    );
    expect(errors.single.field, 'address.street');
  });
}
