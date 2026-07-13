import 'dart:async';
import 'dart:convert';

import 'authenticator.dart';
import 'principal.dart';

/// Looks up and verifies a username/password pair (Spring:
/// `UserDetailsService` + `PasswordEncoder`, collapsed).
///
/// The store owns password hashing — Diana never sees or stores hashes.
/// Return `null` for unknown user OR wrong password (indistinguishable to
/// the caller, by design).
abstract interface class UserStore {
  Future<AuthPrincipal?> verify(String username, String password);
}

/// Authenticates `Authorization: Basic <base64(user:password)>` requests.
class BasicAuthenticator implements Authenticator {
  final UserStore store;
  final String realm;

  const BasicAuthenticator(this.store, {this.realm = 'diana'});

  @override
  String? get challenge => 'Basic realm="$realm"';

  @override
  FutureOr<AuthPrincipal?> authenticate(AuthRequest request) async {
    final authorization = request.header('authorization');
    if (authorization == null) return null;
    final scheme = authorization.split(' ').first;
    if (scheme.toLowerCase() != 'basic') return null;

    final String decoded;
    try {
      decoded = utf8
          .decode(base64.decode(authorization.substring(scheme.length).trim()));
    } on FormatException {
      throw const InvalidCredentialsException('Malformed Basic credentials');
    }
    final separator = decoded.indexOf(':');
    if (separator < 0) {
      throw const InvalidCredentialsException('Malformed Basic credentials');
    }

    final principal = await store.verify(
      decoded.substring(0, separator),
      decoded.substring(separator + 1),
    );
    if (principal == null) {
      throw const InvalidCredentialsException('Bad username or password');
    }
    return principal;
  }
}
