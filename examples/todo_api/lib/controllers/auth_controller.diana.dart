// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import

part of 'auth_controller.dart';

LoginRequest $LoginRequestFromJson(Map<String, dynamic> json) => LoginRequest(
  username: json['username'] as String,
  password: json['password'] as String,
);

Map<String, dynamic> $LoginRequestToJson(LoginRequest value) =>
    <String, dynamic>{'username': value.username, 'password': value.password};

class $LoginRequestValidator implements Validator<LoginRequest> {
  const $LoginRequestValidator();

  @override
  ValidationResult validate(LoginRequest value) {
    final errors = <FieldError>[];
    checkNotBlank(value.username, 'username', errors);
    checkNotBlank(value.password, 'password', errors);
    return ValidationResult(errors);
  }
}

Future<DianaResponse> $diana$AuthController$login(
  AuthController c,
  DianaRequest req,
) async {
  final $a0$json = await decodeJsonMapBody(req);
  final $a0 = decodeDto(() => $LoginRequestFromJson($a0$json));
  const $LoginRequestValidator().validate($a0).throwIfInvalid();
  final result = c.login($a0);
  return DianaResponse.json(result);
}

Future<DianaResponse> $diana$AuthController$me(
  AuthController c,
  DianaRequest req,
) async {
  final result = c.me(bindPrincipal<AuthPrincipal>(req));
  return DianaResponse.json(result);
}
