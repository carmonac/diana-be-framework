import 'dart:async';

import 'authenticator.dart';
import 'principal.dart';

/// Validates an API key and resolves the principal it belongs to. Return
/// `null` for unknown keys.
abstract interface class ApiKeyValidator {
  Future<AuthPrincipal?> validate(String key);
}

/// Authenticates requests carrying an API key header (default `X-API-Key`).
class ApiKeyAuthenticator implements Authenticator {
  final ApiKeyValidator validator;
  final String headerName;

  const ApiKeyAuthenticator(this.validator, {this.headerName = 'X-API-Key'});

  @override
  String? get challenge => null;

  @override
  FutureOr<AuthPrincipal?> authenticate(AuthRequest request) async {
    final key = request.header(headerName);
    if (key == null || key.isEmpty) return null;
    final principal = await validator.validate(key);
    if (principal == null) {
      throw const InvalidCredentialsException('Unknown API key');
    }
    return principal;
  }
}
