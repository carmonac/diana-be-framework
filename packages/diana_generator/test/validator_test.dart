import 'package:build_test/build_test.dart';
import 'package:diana_generator/src/part_builder.dart';
import 'package:test/test.dart';

import 'util/package_assets.dart';

void main() {
  late Map<String, String> deps;

  setUpAll(() async {
    deps = await dianaTestDeps();
  });

  Future<void> expectValidator(
    String source, {
    Object? output,
    List<String> expectedErrors = const [],
  }) async {
    final logs = <String>[];
    await testBuilder(
      const DianaPartBuilder(),
      {...deps, 'a|lib/dto.dart': source},
      outputs: expectedErrors.isEmpty && output != null
          ? {'a|lib/dto.diana.dart': decodedMatches(output)}
          : (expectedErrors.isNotEmpty ? {} : null),
      isInput: (id) => id.startsWith('a|'),
      onLog: (r) {
        if (r.level.name == 'SEVERE') logs.add(r.message);
      },
    );
    for (final expected in expectedErrors) {
      expect(logs.join('\n'), contains(expected));
    }
  }

  test('generates a kitchen-sink validator', () async {
    await expectValidator(
      r'''
import 'package:diana_annotation/diana_annotation.dart';

part 'dto.diana.dart';

class Address {
  @NotBlank()
  final String street;
  const Address(this.street);
}

class SignupRequest {
  @NotBlank(message: 'name is required')
  @Size(min: 2, max: 50)
  final String name;

  @Email()
  final String email;

  @Min(18)
  @Max(130)
  final int? age;

  @Pattern(r'^[a-z0-9_]+$', message: 'lowercase only')
  final String handle;

  @NotEmpty()
  final List<String> tags;

  @Valid()
  final Address? address;

  @Valid()
  final List<Address> previous;

  const SignupRequest(this.name, this.email, this.age, this.handle,
      this.tags, this.address, this.previous);
}
''',
      output: allOf([
        contains('class \$AddressValidator implements Validator<Address>'),
        contains(
            'class \$SignupRequestValidator implements Validator<SignupRequest>'),
        contains(
            "checkNotBlank(value.name, 'name', errors, message: 'name is required');"),
        contains("checkSize(value.name, 'name', errors, min: 2, max: 50);"),
        contains("checkEmail(value.email, 'email', errors);"),
        contains("checkMin(value.age, 18, 'age', errors);"),
        contains("checkMax(value.age, 130, 'age', errors);"),
        contains(r"'^[a-z0-9_]+\$',"),
        contains("message: 'lowercase only'"),
        contains("checkNotEmpty(value.tags, 'tags', errors);"),
        contains('if (value.address != null) {'),
        contains(r'const $AddressValidator().validate(value.address!),'),
        contains(r"'previous[$i]'"),
      ]),
    );
  });

  test('rejects constraints on incompatible field types', () async {
    await expectValidator(
      '''
import 'package:diana_annotation/diana_annotation.dart';

part 'dto.diana.dart';

class Bad {
  @Min(1)
  final String name;
  const Bad(this.name);
}
''',
      expectedErrors: [
        '@Min on Bad.name requires a numeric field — got String.',
      ],
    );
  });

  test('rejects @Valid into a class without constraints', () async {
    await expectValidator(
      '''
import 'package:diana_annotation/diana_annotation.dart';

part 'dto.diana.dart';

class Plain {
  const Plain();
}

class Wrapper {
  @Valid()
  final Plain inner;
  const Wrapper(this.inner);
}
''',
      expectedErrors: [
        '@Valid on Wrapper.inner cascades into Plain, which has no '
            'constraint annotations.',
      ],
    );
  });
}
