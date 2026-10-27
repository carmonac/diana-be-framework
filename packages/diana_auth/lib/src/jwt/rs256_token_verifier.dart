import 'dart:convert';

import '../authenticator.dart';
import 'jwt_validation.dart';
import 'rsa.dart';
import 'token_verifier.dart';

/// RS256 (RSASSA-PKCS1-v1_5 + SHA-256) [TokenVerifier] over a static set of
/// public keys, with the same hardening as [Hs256TokenVerifier]:
///
/// - the `alg` header must be **exactly** `RS256` — `none`, `HS256` and any
///   other algorithm are rejected (kills alg-confusion downgrades);
/// - when the token carries a `kid`, only keys with that id are tried;
/// - `exp`/`nbf` are enforced with a configurable [clockSkew];
/// - `iss`/`aud` are checked when [issuer]/[audience] are set.
///
/// For keys that rotate behind a JWKS endpoint, use `JwksTokenVerifier`.
class Rs256TokenVerifier implements TokenVerifier {
  final List<RsaPublicKey> keys;
  final Duration clockSkew;
  final String? issuer;
  final String? audience;

  Rs256TokenVerifier(
    this.keys, {
    this.clockSkew = const Duration(seconds: 30),
    this.issuer,
    this.audience,
  }) {
    if (keys.isEmpty) {
      throw ArgumentError('Rs256TokenVerifier needs at least one key');
    }
  }

  /// Convenience for a single key.
  Rs256TokenVerifier.single(
    RsaPublicKey key, {
    Duration clockSkew = const Duration(seconds: 30),
    String? issuer,
    String? audience,
  }) : this([key], clockSkew: clockSkew, issuer: issuer, audience: audience);

  @override
  Map<String, Object?> verify(String token) {
    final jwt = parseJwt(token);
    checkAlgorithm(jwt, 'RS256');
    checkRs256Signature(jwt, keys);
    return checkStandardClaims(jwt,
        clockSkew: clockSkew, issuer: issuer, audience: audience);
  }
}

/// Verifies [jwt]'s RS256 signature against [keys]: when the token carries
/// a `kid`, only keys with that id are candidates ("Unknown token key" if
/// none); otherwise every key is tried. Shared by [Rs256TokenVerifier] and
/// `JwksTokenVerifier`.
void checkRs256Signature(JwtParts jwt, List<RsaPublicKey> keys) {
  final kid = jwt.keyId;
  final candidates = kid == null
      ? keys
      : [
          for (final k in keys)
            if (k.keyId == kid) k
        ];
  if (candidates.isEmpty) {
    throw const InvalidCredentialsException('Unknown token key');
  }
  final message = utf8.encode(jwt.signingInput);
  for (final key in candidates) {
    if (rsaVerifyPkcs1Sha256(key, message, jwt.signature)) return;
  }
  throw const InvalidCredentialsException('Invalid token signature');
}
