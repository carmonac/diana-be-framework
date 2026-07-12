# Validation

Diana validates request DTOs declaratively: constraint annotations on
fields become a generated validator that runs **before** your handler. An
invalid body never reaches your code — the client gets a structured 400.

## Declaring constraints

Annotate the fields of any class used with `@Body()`. The library needs a
`part` directive (the validator is generated into it):

```dart
import 'package:diana/diana.dart';

part 'signup_request.diana.dart';

class SignupRequest {
  @NotBlank(message: 'name is required')
  @Size(min: 2, max: 50)
  final String name;

  @Email()
  final String email;

  @Min(18)
  @Max(130)
  final int? age;            // optional: constraints skip null

  @Pattern(r'^[a-z0-9_]+$', message: 'lowercase letters, digits and _ only')
  final String handle;

  @Valid()
  final Address? address;    // cascade into a nested DTO

  // constructor + fromJson/toJson ...
}
```

## The constraint catalogue

| Annotation | Applies to | Fails when |
|---|---|---|
| `@NotNull({message})` | any field | value is `null` |
| `@NotEmpty({message})` | `String`, `List`, `Set`, `Map` | empty |
| `@NotBlank({message})` | `String` | empty or whitespace-only |
| `@Min(value, {message})` | numeric | `< value` |
| `@Max(value, {message})` | numeric | `> value` |
| `@Size({min, max, message})` | `String`, `List`, `Set`, `Map` | length outside `[min, max]` |
| `@Pattern(regex, {message})` | `String` | doesn't match the regex (full or partial per your regex anchors) |
| `@Email({message})` | `String` | not shaped like an email address |
| `@Valid()` | a DTO field, or `List` of DTOs | delegates to the nested type's validator |

Every constraint takes an optional `message` that replaces the default.
Applying a constraint to an incompatible field type (`@Min` on a `String`)
is a **build error**.

### Null semantics

All constraints except `@NotNull` **skip `null` values**. Express
requiredness with a non-nullable Dart type (enforced by your `fromJson`)
or with `@NotNull`. This matches Jakarta Bean Validation semantics: `@Min(1)
int? priority` means *"if present, at least 1"*.

### Cascading with `@Valid`

`@Valid` descends into a nested DTO (or each element of a `List` of DTOs).
Nested field errors are prefixed with the path:

```
address.street        → from @Valid() final Address? address;
items[2].quantity     → from @Valid() final List<OrderItem> items;
```

The nested type must itself carry constraint annotations — `@Valid` into an
unconstrained class is a build error.

## The error response

A failed validation throws `ValidationException`, which the pipeline maps
to:

```json
HTTP 400
{
  "error": "validation_failed",
  "fields": {
    "name": ["name is required", "size must be between 2 and 50"],
    "email": ["must be a valid email address"]
  }
}
```

Messages per field appear in declaration order.

## What gets generated

For each constrained class, a public `$XValidator` in the part file:

```dart
class $SignupRequestValidator implements Validator<SignupRequest> {
  const $SignupRequestValidator();

  @override
  ValidationResult validate(SignupRequest value) {
    final errors = <FieldError>[];
    checkNotBlank(value.name, 'name', errors, message: 'name is required');
    checkSize(value.name, 'name', errors, min: 2, max: 50);
    checkEmail(value.email, 'email', errors);
    ...
    return ValidationResult(errors);
  }
}
```

Generated code is one line per constraint; the semantics live in tested
runtime helpers (`checkNotBlank`, `checkMin`, …). Route adapters invoke the
validator automatically after `fromJson`; for `List<Dto>` bodies each
element is validated.

## Validating manually

Validators are ordinary classes — use them anywhere:

```dart
final result = const $SignupRequestValidator().validate(request);
if (!result.isValid) { ... }        // inspect result.errors
result.throwIfInvalid();            // or throw the standard 400
```

Default messages: `must not be null`, `must not be empty`, `must not be
blank`, `must be at least X`, `must be at most X`, `size must be between X
and Y` / `at least X` / `at most X`, `must match pattern R`, `must be a
valid email address`.

The runtime types (`Validator`, `ValidationResult`, `FieldError`,
`ValidationException`, the `check*` helpers) are documented in the
[runtime reference](../reference/runtime.md#validation).
