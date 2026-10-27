import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:diana_auth/diana_auth.dart';
import 'package:test/test.dart';

const secret = 'a-test-secret-of-decent-length';

String seg(Object value) =>
    base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');

/// Signs a raw JSON payload text — for claim shapes `jsonEncode` cannot
/// produce (e.g. the `1e999` literal, which decodes to `double.infinity`).
String signRaw(String payloadJson) {
  final head = seg({'alg': 'HS256', 'typ': 'JWT'});
  final payload =
      base64Url.encode(utf8.encode(payloadJson)).replaceAll('=', '');
  final mac =
      Hmac(sha256, utf8.encode(secret)).convert(utf8.encode('$head.$payload'));
  return '$head.$payload.${base64Url.encode(mac.bytes).replaceAll('=', '')}';
}

Future<AuthPrincipal?> auth(String token,
    {Hs256TokenVerifier? verifier, String rolesClaim = 'roles'}) async {
  final authenticator = JwtAuthenticator(
    verifier ?? Hs256TokenVerifier(secret),
    rolesClaim: rolesClaim,
  );
  return authenticator
      .authenticate(MapAuthRequest({'authorization': 'Bearer $token'}));
}

void main() {
  final signer = Hs256TokenSigner(secret);

  test('sign → verify round-trip builds the principal', () async {
    final token = signer.sign(Hs256TokenSigner.claimsFor(
      'ada',
      roles: {'admin', 'user'},
    ));
    final principal = await auth(token);
    expect(principal!.name, 'ada');
    expect(principal.roles, {'admin', 'user'});
    expect(principal.attributes['sub'], 'ada');
  });

  test('no Authorization header or non-Bearer scheme is not-my-scheme',
      () async {
    final jwt = JwtAuthenticator(Hs256TokenVerifier(secret));
    expect(await jwt.authenticate(MapAuthRequest({})), isNull);
    expect(
      await jwt.authenticate(MapAuthRequest({'authorization': 'Basic abc'})),
      isNull,
    );
  });

  test('tampered payload is rejected', () {
    final token = signer.sign(Hs256TokenSigner.claimsFor('ada'));
    final parts = token.split('.');
    final tampered =
        '${parts[0]}.${seg({'sub': 'eve', 'exp': 9999999999})}.${parts[2]}';
    expect(() => auth(tampered), throwsA(isA<InvalidCredentialsException>()));
  });

  test('tampered signature is rejected', () {
    final token = signer.sign(Hs256TokenSigner.claimsFor('ada'));
    final parts = token.split('.');
    final flipped = parts[2].substring(0, parts[2].length - 2) +
        (parts[2].endsWith('AA') ? 'BB' : 'AA');
    expect(() => auth('${parts[0]}.${parts[1]}.$flipped'),
        throwsA(isA<InvalidCredentialsException>()));
  });

  test('alg none and alg swaps are rejected', () {
    final claims = seg(Hs256TokenSigner.claimsFor('ada'));
    for (final alg in ['none', 'HS512', 'RS256']) {
      final head = seg({'alg': alg, 'typ': 'JWT'});
      expect(
        () => auth('$head.$claims.'),
        throwsA(isA<InvalidCredentialsException>()),
        reason: 'alg $alg must be rejected',
      );
    }
  });

  test('a numeric sub builds the principal (common IdP shape)', () async {
    final principal = await auth(signer.sign({'sub': 12345}));
    expect(principal!.name, '12345');
  });

  test('a sub that is neither string nor number is a clean 401', () {
    expect(() => auth(signer.sign({'sub': true})),
        throwsA(isA<InvalidCredentialsException>()));
  });

  test('malformed exp/nbf claims reject cleanly — never crash or fail open',
      () {
    // A present but non-numeric expiry must NOT be silently skipped (that
    // would accept a should-be-expired token forever), and a non-finite
    // number must not crash round() into a 500.
    for (final claims in [
      {'sub': 'ada', 'exp': '1'},
      {'sub': 'ada', 'exp': true},
      {'sub': 'ada', 'nbf': 'soon'},
    ]) {
      expect(() => auth(signer.sign(claims)),
          throwsA(isA<InvalidCredentialsException>()),
          reason: 'claims $claims must be rejected');
    }
    expect(() => auth(signRaw('{"sub":"ada","exp":1e999}')),
        throwsA(isA<InvalidCredentialsException>()),
        reason: 'an Infinity exp must be rejected, not crash');
  });

  test('expired and not-yet-valid tokens are rejected; skew is tolerated', () {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    expect(
      () => auth(signer.sign({'sub': 'ada', 'exp': now - 300})),
      throwsA(isA<InvalidCredentialsException>()),
    );
    expect(
      () => auth(signer.sign({'sub': 'ada', 'nbf': now + 300})),
      throwsA(isA<InvalidCredentialsException>()),
    );
    // Within the default 30s skew: accepted.
    expect(auth(signer.sign({'sub': 'ada', 'exp': now - 10})), completes);
    expect(auth(signer.sign({'sub': 'ada', 'nbf': now + 10})), completes);
  });

  test('issuer and audience are enforced when configured', () {
    final verifier = Hs256TokenVerifier(
      secret,
      issuer: 'https://issuer',
      audience: 'my-api',
    );
    final good = signer.sign({
      ...Hs256TokenSigner.claimsFor('ada'),
      'iss': 'https://issuer',
      'aud': ['other', 'my-api'],
    });
    expect(auth(good, verifier: verifier), completes);

    final badIss = signer.sign({
      ...Hs256TokenSigner.claimsFor('ada'),
      'iss': 'https://evil',
      'aud': 'my-api',
    });
    expect(() => auth(badIss, verifier: verifier),
        throwsA(isA<InvalidCredentialsException>()));

    final badAud = signer.sign({
      ...Hs256TokenSigner.claimsFor('ada'),
      'iss': 'https://issuer',
      'aud': 'other-api',
    });
    expect(() => auth(badAud, verifier: verifier),
        throwsA(isA<InvalidCredentialsException>()));
  });

  test('roles from a space-delimited scope claim', () async {
    final token = signer.sign({
      ...Hs256TokenSigner.claimsFor('ada'),
      'scope': 'read write admin',
    });
    final principal = await auth(token, rolesClaim: 'scope');
    expect(principal!.roles, {'read', 'write', 'admin'});
  });

  test('malformed tokens are rejected, never crash', () {
    for (final bad in [
      'garbage',
      'a.b',
      'a.b.c.d',
      '!!!.???.***',
      '${seg({'alg': 'HS256'})}.not-base64!.sig',
      'Bearerless',
      '..',
    ]) {
      expect(
        () => auth(bad),
        throwsA(isA<InvalidCredentialsException>()),
        reason: 'token "$bad" must be rejected cleanly',
      );
    }
  });

  test('empty bearer token is invalid credentials, not anonymous', () {
    final jwt = JwtAuthenticator(Hs256TokenVerifier(secret));
    expect(
      () => jwt.authenticate(MapAuthRequest({'authorization': 'Bearer '})),
      throwsA(isA<InvalidCredentialsException>()),
    );
  });
}
