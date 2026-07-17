import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../authenticator.dart';

/// Verifies a compact JWT and returns its claim set — the seam for
/// plugging RS256/JWKS or any external JWT library.
///
/// Implementations throw [InvalidCredentialsException] (or a subclass) on
/// ANY failure: malformed token, unexpected algorithm, bad signature,
/// expired/not-yet-valid, wrong issuer/audience.
abstract interface class TokenVerifier {
  Map<String, Object?> verify(String token);
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
    final parts = token.split('.');
    if (parts.length != 3) {
      throw const InvalidCredentialsException('Malformed token');
    }
    final header = _decodeJsonSegment(parts[0]);
    if (header['alg'] != 'HS256' ||
        (header['typ'] != null && header['typ'] != 'JWT')) {
      throw const InvalidCredentialsException('Unexpected token algorithm');
    }

    final expected =
        Hmac(sha256, _secret).convert(utf8.encode('${parts[0]}.${parts[1]}'));
    if (!_constantTimeEquals(expected.bytes, _decodeSegment(parts[2]))) {
      throw const InvalidCredentialsException('Invalid token signature');
    }

    final claims = _decodeJsonSegment(parts[1]);
    final now = DateTime.now();
    final exp = _numericDate(claims['exp']);
    if (exp != null && now.subtract(clockSkew).isAfter(exp)) {
      throw const InvalidCredentialsException('Token expired');
    }
    final nbf = _numericDate(claims['nbf']);
    if (nbf != null && now.add(clockSkew).isBefore(nbf)) {
      throw const InvalidCredentialsException('Token not yet valid');
    }
    if (issuer != null && claims['iss'] != issuer) {
      throw const InvalidCredentialsException('Unexpected token issuer');
    }
    if (audience != null && !_audienceMatches(claims['aud'])) {
      throw const InvalidCredentialsException('Unexpected token audience');
    }
    return claims;
  }

  bool _audienceMatches(Object? aud) => switch (aud) {
        String value => value == audience,
        List<Object?> values => values.contains(audience),
        _ => false,
      };

  /// `null` only when the claim is absent. A present claim that is not a
  /// finite number is malformed and REJECTED — silently skipping the check
  /// would fail open on expiry, and `Infinity`/`NaN` would crash `round()`.
  static DateTime? _numericDate(Object? claim) {
    if (claim == null) return null;
    if (claim is! num || !claim.isFinite) {
      throw const InvalidCredentialsException('Malformed token claims');
    }
    return DateTime.fromMillisecondsSinceEpoch((claim * 1000).round());
  }

  static Map<String, Object?> _decodeJsonSegment(String segment) {
    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(_decodeSegment(segment)));
    } on FormatException {
      throw const InvalidCredentialsException('Malformed token');
    }
    if (decoded is! Map) {
      throw const InvalidCredentialsException('Malformed token');
    }
    return decoded.cast<String, Object?>();
  }

  static List<int> _decodeSegment(String segment) {
    try {
      return base64Url.decode(base64Url.normalize(segment));
    } on FormatException {
      throw const InvalidCredentialsException('Malformed token');
    }
  }

  /// XOR-fold comparison: runtime independent of where the mismatch is.
  static bool _constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}
