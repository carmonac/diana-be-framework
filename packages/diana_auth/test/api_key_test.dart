import 'package:diana_auth/diana_auth.dart';
import 'package:test/test.dart';

class FixedValidator implements ApiKeyValidator {
  @override
  Future<AuthPrincipal?> validate(String key) async =>
      key == 'k-123' ? const AuthPrincipal('service-a', roles: {'svc'}) : null;
}

void main() {
  final authenticator = ApiKeyAuthenticator(FixedValidator());

  test('valid key builds the principal (default X-API-Key header)', () async {
    final principal = await authenticator
        .authenticate(MapAuthRequest({'x-api-key': 'k-123'}));
    expect(principal!.name, 'service-a');
    expect(principal.roles, {'svc'});
  });

  test('missing or empty key is not-my-scheme', () async {
    expect(await authenticator.authenticate(MapAuthRequest({})), isNull);
    expect(
      await authenticator.authenticate(MapAuthRequest({'x-api-key': ''})),
      isNull,
    );
  });

  test('unknown key is invalid credentials', () {
    expect(
      () => authenticator.authenticate(MapAuthRequest({'x-api-key': 'nope'})),
      throwsA(isA<InvalidCredentialsException>()),
    );
  });

  test('custom header name', () async {
    final custom =
        ApiKeyAuthenticator(FixedValidator(), headerName: 'X-Custom');
    expect(
      (await custom.authenticate(MapAuthRequest({'x-custom': 'k-123'})))!.name,
      'service-a',
    );
  });

  test('a three-strategy chain composes (JWT + Basic + API key)', () async {
    final signer = Hs256TokenSigner('chain-secret');
    final auth = AuthenticationMiddleware(authenticators: [
      JwtAuthenticator(Hs256TokenVerifier('chain-secret')),
      BasicAuthenticator(_NoUsers()),
      ApiKeyAuthenticator(FixedValidator()),
    ]);
    final viaJwt = await auth.authenticate(MapAuthRequest({
      'authorization':
          'Bearer ${signer.sign(Hs256TokenSigner.claimsFor('ada'))}',
    }));
    expect(viaJwt!.name, 'ada');
    final viaKey =
        await auth.authenticate(MapAuthRequest({'x-api-key': 'k-123'}));
    expect(viaKey!.name, 'service-a');
    expect(await auth.authenticate(MapAuthRequest({})), isNull);
  });
}

class _NoUsers implements UserStore {
  @override
  Future<AuthPrincipal?> verify(String username, String password) async =>
      null;
}
