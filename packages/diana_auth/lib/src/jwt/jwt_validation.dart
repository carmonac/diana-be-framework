/// Shared, hardened JWT parsing and claim validation used by every built-in
/// [TokenVerifier]. Keeping the checks in one place guarantees HS256 and
/// RS256 enforce identical semantics (exact `alg` match, `exp`/`nbf` with
/// clock skew, optional `iss`/`aud`).
library;

import 'dart:convert';

import '../authenticator.dart';

/// A compact JWT split into its parts, with the header decoded.
class JwtParts {
  /// `<header>.<payload>` — the input the signature covers.
  final String signingInput;
  final Map<String, Object?> header;
  final String payloadSegment;
  final List<int> signature;

  const JwtParts({
    required this.signingInput,
    required this.header,
    required this.payloadSegment,
    required this.signature,
  });

  /// The `kid` header when present and a string.
  String? get keyId => header['kid'] is String ? header['kid'] as String : null;
}

/// Splits and decodes a compact JWT, rejecting the token — never crashing —
/// on any malformation.
JwtParts parseJwt(String token) {
  final parts = token.split('.');
  if (parts.length != 3) {
    throw const InvalidCredentialsException('Malformed token');
  }
  return JwtParts(
    signingInput: '${parts[0]}.${parts[1]}',
    header: decodeJsonSegment(parts[0]),
    payloadSegment: parts[1],
    signature: decodeSegment(parts[2]),
  );
}

/// The `alg` header must be **exactly** [algorithm] — `none` and any other
/// algorithm are rejected (kills alg-confusion downgrades) — and `typ`,
/// when present, must be `JWT`.
void checkAlgorithm(JwtParts jwt, String algorithm) {
  if (jwt.header['alg'] != algorithm ||
      (jwt.header['typ'] != null && jwt.header['typ'] != 'JWT')) {
    throw const InvalidCredentialsException('Unexpected token algorithm');
  }
}

/// Decodes the payload and enforces the standard claims: `exp`/`nbf` with
/// [clockSkew], and `iss`/`aud` when [issuer]/[audience] are set. Returns
/// the claim set.
Map<String, Object?> checkStandardClaims(
  JwtParts jwt, {
  required Duration clockSkew,
  String? issuer,
  String? audience,
}) {
  final claims = decodeJsonSegment(jwt.payloadSegment);
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
  if (audience != null && !_audienceMatches(claims['aud'], audience)) {
    throw const InvalidCredentialsException('Unexpected token audience');
  }
  return claims;
}

bool _audienceMatches(Object? aud, String audience) => switch (aud) {
      String value => value == audience,
      List<Object?> values => values.contains(audience),
      _ => false,
    };

/// `null` only when the claim is absent. A present claim that is not a
/// finite number is malformed and REJECTED — silently skipping the check
/// would fail open on expiry, and `Infinity`/`NaN` would crash `round()`.
DateTime? _numericDate(Object? claim) {
  if (claim == null) return null;
  if (claim is! num || !claim.isFinite) {
    throw const InvalidCredentialsException('Malformed token claims');
  }
  return DateTime.fromMillisecondsSinceEpoch((claim * 1000).round());
}

Map<String, Object?> decodeJsonSegment(String segment) {
  final Object? decoded;
  try {
    decoded = jsonDecode(utf8.decode(decodeSegment(segment)));
  } on FormatException {
    throw const InvalidCredentialsException('Malformed token');
  }
  if (decoded is! Map) {
    throw const InvalidCredentialsException('Malformed token');
  }
  return decoded.cast<String, Object?>();
}

List<int> decodeSegment(String segment) {
  try {
    return base64Url.decode(base64Url.normalize(segment));
  } on FormatException {
    throw const InvalidCredentialsException('Malformed token');
  }
}

/// XOR-fold comparison: runtime independent of where the mismatch is.
bool constantTimeEquals(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}
