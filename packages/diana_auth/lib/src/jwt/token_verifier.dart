import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../authenticator.dart';
import 'jwt_validation.dart';

/// Verifies a compact JWT and returns its claim set — the seam for
/// plugging any external JWT library.
///
/// Implementations throw [InvalidCredentialsException] (or a subclass) on
/// ANY failure: malformed token, unexpected algorithm, bad signature,
/// expired/not-yet-valid, wrong issuer/audience. `verify` may be
/// asynchronous — verifiers that resolve keys remotely (JWKS) fetch and
/// cache them; purely local verifiers stay synchronous.
abstract interface class TokenVerifier {
  FutureOr<Map<String, Object?>> verify(String token);
}

/// HS256 (HMAC-SHA256) [TokenVerifier], hardened:
///
/// - the `alg` header must be **exactly** `HS256` — `none` and any other
///   algorithm are rejected (kills alg-confusion downgrades);
/// - signatures are compared in constant time;
/// - `exp`/`nbf` are enforced with a configurable [clockSkew];
/// - `iss`/`aud` are checked when [issuer]/[audience] are set.
class Hs256TokenVerifier implements TokenVerifier {
  final List<int> _secret;
  final Duration clockSkew;
  final String? issuer;
  final String? audience;

  Hs256TokenVerifier(
    String secret, {
    this.clockSkew = const Duration(seconds: 30),
    this.issuer,
    this.audience,
  }) : _secret = utf8.encode(secret);

  @override
  Map<String, Object?> verify(String token) {
    final jwt = parseJwt(token);
    checkAlgorithm(jwt, 'HS256');

    final expected =
        Hmac(sha256, _secret).convert(utf8.encode(jwt.signingInput));
    if (!constantTimeEquals(expected.bytes, jwt.signature)) {
      throw const InvalidCredentialsException('Invalid token signature');
    }

    return checkStandardClaims(jwt,
        clockSkew: clockSkew, issuer: issuer, audience: audience);
  }
}
