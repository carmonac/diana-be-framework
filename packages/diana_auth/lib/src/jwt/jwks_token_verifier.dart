import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../authenticator.dart';
import 'jwt_validation.dart';
import 'rs256_token_verifier.dart';
import 'rsa.dart';
import 'token_verifier.dart';

/// RS256 [TokenVerifier] whose public keys come from a JWKS endpoint
/// (RFC 7517) — the shape every major IdP exposes (Auth0, Keycloak,
/// Cognito, Firebase, Entra ID) at
/// `.../.well-known/jwks.json` or `.../protocol/openid-connect/certs`.
///
/// Keys are fetched lazily on first use and cached for [cacheTtl].
/// **Rotation** is handled the standard way: a token whose `kid` is not in
/// the cache triggers one immediate re-fetch (rate-limited to one per
/// [refreshCooldown], so a flood of bogus `kid`s cannot hammer the IdP).
/// When a refresh fails and cached keys exist, the cache keeps serving
/// (stale-while-error); with no cache at all, verification fails with 401.
///
/// Token validation itself is identical to [Rs256TokenVerifier] (exact
/// `alg` match, `exp`/`nbf` with [clockSkew], optional [issuer]/
/// [audience]).
class JwksTokenVerifier implements TokenVerifier {
  final Uri jwksUri;
  final Duration cacheTtl;
  final Duration refreshCooldown;
  final Duration requestTimeout;
  final Duration clockSkew;
  final String? issuer;
  final String? audience;

  final HttpClient _client = HttpClient();
  List<RsaPublicKey> _keys = const [];
  DateTime? _fetchedAt;
  Future<void>? _inFlight;

  JwksTokenVerifier(
    this.jwksUri, {
    this.cacheTtl = const Duration(minutes: 10),
    this.refreshCooldown = const Duration(seconds: 30),
    this.requestTimeout = const Duration(seconds: 5),
    this.clockSkew = const Duration(seconds: 30),
    this.issuer,
    this.audience,
  });

  @override
  Future<Map<String, Object?>> verify(String token) async {
    // Parse and check the algorithm BEFORE any I/O: garbage tokens must
    // not trigger network fetches.
    final jwt = parseJwt(token);
    checkAlgorithm(jwt, 'RS256');

    var keys = await _currentKeys();
    final kid = jwt.keyId;
    if (kid != null &&
        !keys.any((k) => k.keyId == kid) &&
        _cooldownElapsed()) {
      // Possibly a freshly-rotated key: one immediate re-fetch.
      await _refresh();
      keys = _keys;
    }
    if (keys.isEmpty) {
      throw const InvalidCredentialsException('Unable to verify token');
    }
    checkRs256Signature(jwt, keys);
    return checkStandardClaims(jwt,
        clockSkew: clockSkew, issuer: issuer, audience: audience);
  }

  /// Closes the underlying HTTP client (call from `@PreDestroy` or tests).
  void close() => _client.close(force: true);

  Future<List<RsaPublicKey>> _currentKeys() async {
    final fetchedAt = _fetchedAt;
    // An empty cache (e.g. the IdP was down at startup) retries on the
    // cooldown, not the TTL — otherwise every token 401s for a full TTL.
    if (fetchedAt == null ||
        DateTime.now().difference(fetchedAt) > cacheTtl ||
        (_keys.isEmpty && _cooldownElapsed())) {
      await _refresh();
    }
    return _keys;
  }

  bool _cooldownElapsed() {
    final fetchedAt = _fetchedAt;
    return fetchedAt == null ||
        DateTime.now().difference(fetchedAt) >= refreshCooldown;
  }

  /// Fetches the JWKS, deduplicating concurrent callers onto one request.
  /// Failures keep previously cached keys (stale-while-error).
  Future<void> _refresh() {
    return _inFlight ??= _fetch().whenComplete(() => _inFlight = null);
  }

  Future<void> _fetch() async {
    List<RsaPublicKey> fetched;
    try {
      final request =
          await _client.getUrl(jwksUri).timeout(requestTimeout);
      final response = await request.close().timeout(requestTimeout);
      if (response.statusCode != 200) {
        throw HttpException('JWKS endpoint returned ${response.statusCode}');
      }
      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(requestTimeout);
      fetched = _parseJwks(body);
    } catch (_) {
      // Stale-while-error: keep whatever we had. The cooldown clock still
      // advances so a broken IdP is not hammered on every request.
      _fetchedAt = DateTime.now();
      return;
    }
    _keys = fetched;
    _fetchedAt = DateTime.now();
  }

  /// RSA signature keys only; individually malformed JWKs are skipped so
  /// one bad entry cannot take down the whole key set.
  static List<RsaPublicKey> _parseJwks(String body) {
    final Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      throw const FormatException('JWKS document is not valid JSON');
    }
    if (decoded is! Map || decoded['keys'] is! List) {
      throw const FormatException('JWKS document has no "keys" list');
    }
    final keys = <RsaPublicKey>[];
    for (final entry in decoded['keys'] as List) {
      if (entry is! Map) continue;
      final jwk = entry.cast<String, Object?>();
      if (jwk['kty'] != 'RSA') continue;
      if (jwk['use'] != null && jwk['use'] != 'sig') continue;
      if (jwk['alg'] != null && jwk['alg'] != 'RS256') continue;
      try {
        keys.add(RsaPublicKey.fromJwk(jwk));
      } on FormatException {
        continue;
      }
    }
    return keys;
  }
}
