import 'dart:async';

import '../authenticator.dart';
import '../principal.dart';
import 'token_verifier.dart';

/// Authenticates `Authorization: Bearer <jwt>` requests.
///
/// The principal is built from the verified claims: `sub` → [AuthPrincipal.name],
/// [rolesClaim] → roles (a JSON list of strings, or a space-delimited
/// string — which covers OAuth's `scope`), and the full claim set →
/// [AuthPrincipal.attributes].
class JwtAuthenticator implements Authenticator {
  final TokenVerifier verifier;
  final String rolesClaim;

  const JwtAuthenticator(this.verifier, {this.rolesClaim = 'roles'});

  @override
  String? get challenge => 'Bearer';

  @override
  FutureOr<AuthPrincipal?> authenticate(AuthRequest request) {
    final authorization = request.header('authorization');
    if (authorization == null) return null;
    final scheme = authorization.split(' ').first;
    if (scheme.toLowerCase() != 'bearer') return null;
    final token = authorization.substring(scheme.length).trim();
    if (token.isEmpty) {
      throw const InvalidCredentialsException('Empty bearer token');
    }

    final claims = verifier.verify(token);
    return AuthPrincipal(
      claims['sub'] as String? ?? '',
      roles: _rolesOf(claims[rolesClaim]),
      attributes: claims,
    );
  }

  static Set<String> _rolesOf(Object? claim) => switch (claim) {
        List<Object?> values => {for (final v in values) v.toString()},
        String value when value.isNotEmpty => value.split(' ').toSet(),
        _ => const {},
      };
}
