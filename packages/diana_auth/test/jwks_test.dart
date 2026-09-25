import 'dart:convert';
import 'dart:io';

import 'package:diana_auth/diana_auth.dart';
import 'package:test/test.dart';

import 'util/rsa_fixture.dart';

/// A hermetic JWKS endpoint: serves [document], counts requests, and can be
/// switched to failure mode.
class FakeJwksServer {
  late final HttpServer _server;
  Object? document;
  int requests = 0;
  bool failing = false;

  Uri get uri => Uri.parse('http://127.0.0.1:${_server.port}/jwks.json');

  static Future<FakeJwksServer> start(Object document) async {
    final s = FakeJwksServer()..document = document;
    s._server = await HttpServer.bind('127.0.0.1', 0);
    s._server.listen((request) {
      s.requests++;
      if (s.failing) {
        request.response.statusCode = 500;
      } else {
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(s.document));
      }
      request.response.close();
    });
    return s;
  }

  Future<void> close() => _server.close(force: true);
}

Object jwksDoc(List<Map<String, Object?>> keys) => {'keys': keys};

void main() {
  test('verifies against a fetched key and caches the document', () async {
    final server = await FakeJwksServer.start(jwksDoc([fixtureJwk(kid: 'k1')]));
    final verifier = JwksTokenVerifier(server.uri);
    addTearDown(() async {
      verifier.close();
      await server.close();
    });

    final first = await verifier.verify(signRs256(claims(), kid: 'k1'));
    expect(first['sub'], 'ada');
    await verifier.verify(signRs256(claims(sub: 'grace'), kid: 'k1'));
    expect(server.requests, 1, reason: 'second verify hits the cache');
  });

  test('an unknown kid triggers one re-fetch and picks up a rotated key',
      () async {
    final server = await FakeJwksServer.start(jwksDoc([fixtureJwk(kid: 'old')]));
    final verifier =
        JwksTokenVerifier(server.uri, refreshCooldown: Duration.zero);
    addTearDown(() async {
      verifier.close();
      await server.close();
    });

    await verifier.verify(signRs256(claims(), kid: 'old'));
    expect(server.requests, 1);

    // Rotate: the endpoint now serves the new kid.
    server.document = jwksDoc([fixtureJwk(kid: 'new')]);
    final result = await verifier.verify(signRs256(claims(), kid: 'new'));
    expect(result['sub'], 'ada');
    expect(server.requests, 2, reason: 'unknown kid re-fetched once');
  });

  test('the refresh cooldown rate-limits bogus-kid re-fetches', () async {
    final server = await FakeJwksServer.start(jwksDoc([fixtureJwk(kid: 'k1')]));
    final verifier = JwksTokenVerifier(server.uri,
        refreshCooldown: const Duration(minutes: 5));
    addTearDown(() async {
      verifier.close();
      await server.close();
    });

    await verifier.verify(signRs256(claims(), kid: 'k1'));
    for (var i = 0; i < 3; i++) {
      await expectLater(verifier.verify(signRs256(claims(), kid: 'bogus-$i')),
          throwsA(isA<InvalidCredentialsException>()));
    }
    expect(server.requests, 1,
        reason: 'bogus kids within the cooldown must not re-fetch');
  });

  test('keeps serving cached keys while the endpoint is failing', () async {
    final server = await FakeJwksServer.start(jwksDoc([fixtureJwk(kid: 'k1')]));
    final verifier = JwksTokenVerifier(server.uri,
        cacheTtl: Duration.zero, refreshCooldown: Duration.zero);
    addTearDown(() async {
      verifier.close();
      await server.close();
    });

    await verifier.verify(signRs256(claims(), kid: 'k1'));
    server.failing = true;
    // TTL zero forces a refresh attempt; it fails, the cache still serves.
    final result = await verifier.verify(signRs256(claims(), kid: 'k1'));
    expect(result['sub'], 'ada');
  });

  test('an unreachable endpoint with no cache yields 401, not a crash',
      () async {
    final server = await FakeJwksServer.start(jwksDoc([]));
    final uri = server.uri;
    await server.close();
    final verifier = JwksTokenVerifier(uri);
    addTearDown(verifier.close);

    await expectLater(verifier.verify(signRs256(claims(), kid: 'k1')),
        throwsA(isA<InvalidCredentialsException>().having(
            (e) => e.message, 'message', 'Unable to verify token')));
  });

  test('a failed first fetch retries after the cooldown, not the TTL',
      () async {
    final server = await FakeJwksServer.start(jwksDoc([fixtureJwk()]));
    server.failing = true;
    final verifier =
        JwksTokenVerifier(server.uri, refreshCooldown: Duration.zero);
    addTearDown(() async {
      verifier.close();
      await server.close();
    });

    // kid-less token: the unknown-kid re-fetch path does not apply.
    await expectLater(verifier.verify(signRs256(claims())),
        throwsA(isA<InvalidCredentialsException>()));
    server.failing = false;
    final result = await verifier.verify(signRs256(claims()));
    expect(result['sub'], 'ada');
    expect(server.requests, 2);
  });

  test('non-RSA, encryption-use and malformed JWKs are skipped', () async {
    final server = await FakeJwksServer.start(jwksDoc([
      {'kty': 'EC', 'crv': 'P-256', 'kid': 'ec'},
      {'kty': 'RSA', 'use': 'enc', 'n': fixtureN, 'e': fixtureE, 'kid': 'enc'},
      {'kty': 'RSA', 'n': '!!not-base64!!', 'e': 'AQAB', 'kid': 'bad'},
      fixtureJwk(kid: 'good'),
    ]));
    final verifier = JwksTokenVerifier(server.uri);
    addTearDown(() async {
      verifier.close();
      await server.close();
    });

    final result = await verifier.verify(signRs256(claims(), kid: 'good'));
    expect(result['sub'], 'ada');
    await expectLater(verifier.verify(signRs256(claims(), kid: 'enc')),
        throwsA(isA<InvalidCredentialsException>()));
  });

  test('garbage tokens are rejected before any fetch', () async {
    final server = await FakeJwksServer.start(jwksDoc([fixtureJwk(kid: 'k1')]));
    final verifier = JwksTokenVerifier(server.uri);
    addTearDown(() async {
      verifier.close();
      await server.close();
    });

    await expectLater(verifier.verify('not-a-jwt'),
        throwsA(isA<InvalidCredentialsException>()));
    final hs256 = Hs256TokenSigner('secret')
        .sign(Hs256TokenSigner.claimsFor('mallory'));
    await expectLater(verifier.verify(hs256),
        throwsA(isA<InvalidCredentialsException>()));
    expect(server.requests, 0,
        reason: 'malformed/wrong-alg tokens must not trigger I/O');
  });

  test('enforces issuer and audience like the static verifiers', () async {
    final server = await FakeJwksServer.start(jwksDoc([fixtureJwk(kid: 'k1')]));
    final verifier = JwksTokenVerifier(server.uri,
        issuer: 'https://idp', audience: 'api');
    addTearDown(() async {
      verifier.close();
      await server.close();
    });

    await expectLater(verifier.verify(signRs256(claims(), kid: 'k1')),
        throwsA(isA<InvalidCredentialsException>()));
    final ok = await verifier.verify(signRs256(
        claims(extra: {'iss': 'https://idp', 'aud': 'api'}),
        kid: 'k1'));
    expect(ok['sub'], 'ada');
  });
}
