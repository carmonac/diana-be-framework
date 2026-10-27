import 'dart:convert';

import 'package:diana_auth/diana_auth.dart';
import 'package:test/test.dart';

import 'util/rsa_fixture.dart';

void main() {
  group('RsaPublicKey', () {
    test('fromJwk parses n/e and kid', () {
      final key = fixtureKey(kid: 'k1');
      expect(key.keyId, 'k1');
      expect(key.octetLength, 256); // 2048-bit
      expect(key.exponent, BigInt.from(65537));
    });

    test('fromPem parses SPKI and PKCS#1 to the same key', () {
      final spki = RsaPublicKey.fromPem(fixtureSpkiPem);
      final pkcs1 = RsaPublicKey.fromPem(fixturePkcs1Pem);
      final jwk = fixtureKey();
      expect(spki.modulus, jwk.modulus);
      expect(pkcs1.modulus, jwk.modulus);
      expect(spki.exponent, jwk.exponent);
    });

    test('rejects non-RSA JWKs and malformed input', () {
      expect(() => RsaPublicKey.fromJwk({'kty': 'EC'}), throwsFormatException);
      expect(() => RsaPublicKey.fromJwk({'kty': 'RSA', 'n': fixtureN}),
          throwsFormatException);
      expect(() => RsaPublicKey.fromJwk({'kty': 'RSA', 'n': '!!', 'e': 'AQAB'}),
          throwsFormatException);
      expect(() => RsaPublicKey.fromPem('not a pem'), throwsFormatException);
      expect(
          () => RsaPublicKey.fromPem(
              '-----BEGIN PUBLIC KEY-----\nAAAA\n-----END PUBLIC KEY-----'),
          throwsFormatException);
    });
  });

  group('Rs256TokenVerifier', () {
    final verifier = Rs256TokenVerifier.single(fixtureKey());

    Matcher rejects() => throwsA(isA<InvalidCredentialsException>());

    test('verifies a valid token and returns its claims', () {
      final result = verifier.verify(signRs256(claims(sub: 'ada')));
      expect(result['sub'], 'ada');
    });

    test('rejects a tampered payload', () {
      final token = signRs256(claims());
      final parts = token.split('.');
      final tampered = base64Url
          .encode(utf8.encode(jsonEncode({'sub': 'mallory'})))
          .replaceAll('=', '');
      expect(() => verifier.verify('${parts[0]}.$tampered.${parts[2]}'),
          rejects());
    });

    test('rejects a truncated signature', () {
      final token = signRs256(claims());
      expect(() => verifier.verify(token.substring(0, token.length - 8)),
          rejects());
    });

    test('rejects alg none / HS256 (alg confusion)', () {
      for (final alg in ['none', 'HS256', 'RS512', 'ES256']) {
        final token = signRs256(claims(), header: {'alg': alg, 'typ': 'JWT'});
        expect(() => verifier.verify(token), rejects(),
            reason: 'alg $alg must be rejected');
      }
      // A genuine HS256 token signed with the modulus as HMAC secret — the
      // classic RS→HS downgrade — dies on the alg check, before any key use.
      final hsToken = Hs256TokenSigner(fixtureN)
          .sign(Hs256TokenSigner.claimsFor('mallory'));
      expect(() => verifier.verify(hsToken), rejects());
    });

    test('kid selection: mismatched kid is rejected, matching verifies', () {
      final keyed = Rs256TokenVerifier([fixtureKey(kid: 'good')]);
      expect(keyed.verify(signRs256(claims(), kid: 'good'))['sub'], 'ada');
      expect(
          () => keyed.verify(signRs256(claims(), kid: 'other')),
          throwsA(isA<InvalidCredentialsException>()
              .having((e) => e.message, 'message', 'Unknown token key')));
      // No kid on the token: every key is tried.
      expect(keyed.verify(signRs256(claims()))['sub'], 'ada');
    });

    test('enforces exp, iss and aud like HS256', () {
      expect(
          () => verifier
              .verify(signRs256(claims(ttl: const Duration(hours: -2)))),
          rejects());
      final strict = Rs256TokenVerifier.single(fixtureKey(),
          issuer: 'https://idp', audience: 'api');
      expect(() => strict.verify(signRs256(claims())), rejects());
      final ok = strict.verify(
          signRs256(claims(extra: {'iss': 'https://idp', 'aud': 'api'})));
      expect(ok['sub'], 'ada');
    });

    test('an empty key list is a configuration error', () {
      expect(() => Rs256TokenVerifier(const []), throwsArgumentError);
    });

    test('plugs into JwtAuthenticator end to end', () async {
      final auth = JwtAuthenticator(verifier);
      final token = signRs256(claims(sub: 'ada', extra: {
        'roles': ['admin']
      }));
      final principal = await auth
          .authenticate(MapAuthRequest({'authorization': 'Bearer $token'}));
      expect(principal!.name, 'ada');
      expect(principal.roles, {'admin'});
    });
  });
}
