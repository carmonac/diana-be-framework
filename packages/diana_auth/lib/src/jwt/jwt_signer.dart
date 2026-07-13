import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Mints HS256 JWTs — for login endpoints and tests. Pass the complete
/// claim set (add `exp`/`sub`/roles yourself; see [claimsFor]).
class Hs256TokenSigner {
  final List<int> _secret;

  Hs256TokenSigner(String secret) : _secret = utf8.encode(secret);

  String sign(Map<String, Object?> claims) {
    String encode(Object value) =>
        base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
    final head = encode(const {'alg': 'HS256', 'typ': 'JWT'});
    final body = encode(claims);
    final signature = base64Url
        .encode(Hmac(sha256, _secret).convert(utf8.encode('$head.$body')).bytes)
        .replaceAll('=', '');
    return '$head.$body.$signature';
  }

  /// Convenience claim set: `sub`, roles, `iat` and `exp` from [ttl].
  static Map<String, Object?> claimsFor(
    String subject, {
    Set<String> roles = const {},
    Duration ttl = const Duration(hours: 1),
    String rolesClaim = 'roles',
  }) {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return {
      'sub': subject,
      if (roles.isNotEmpty) rolesClaim: roles.toList(),
      'iat': now,
      'exp': now + ttl.inSeconds,
    };
  }
}
