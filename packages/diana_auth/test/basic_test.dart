import 'dart:convert';

import 'package:diana_auth/diana_auth.dart';
import 'package:test/test.dart';

class FixedStore implements UserStore {
  @override
  Future<AuthPrincipal?> verify(String username, String password) async =>
      username == 'ada' && password == 's3cret'
          ? const AuthPrincipal('ada', roles: {'admin'})
          : null;
}

String basic(String userPass) =>
    'Basic ${base64.encode(utf8.encode(userPass))}';

void main() {
  final authenticator = BasicAuthenticator(FixedStore(), realm: 'api');

  test('valid credentials build the principal', () async {
    final principal = await authenticator
        .authenticate(MapAuthRequest({'authorization': basic('ada:s3cret')}));
    expect(principal!.name, 'ada');
    expect(principal.roles, {'admin'});
  });

  test('password containing colons survives the split', () async {
    final store = _RecordingStore();
    await BasicAuthenticator(store)
        .authenticate(MapAuthRequest({'authorization': basic('ada:a:b:c')}));
    expect(store.lastPassword, 'a:b:c');
  });

  test('no header or non-Basic scheme is not-my-scheme', () async {
    expect(await authenticator.authenticate(MapAuthRequest({})), isNull);
    expect(
      await authenticator
          .authenticate(MapAuthRequest({'authorization': 'Bearer x'})),
      isNull,
    );
  });

  test('wrong password and malformed base64 are invalid credentials', () {
    expect(
      () => authenticator
          .authenticate(MapAuthRequest({'authorization': basic('ada:wrong')})),
      throwsA(isA<InvalidCredentialsException>()),
    );
    expect(
      () => authenticator
          .authenticate(MapAuthRequest({'authorization': 'Basic !!!'})),
      throwsA(isA<InvalidCredentialsException>()),
    );
    expect(
      () => authenticator.authenticate(MapAuthRequest(
          {'authorization': 'Basic ${base64.encode(utf8.encode('nocolon'))}'})),
      throwsA(isA<InvalidCredentialsException>()),
    );
  });

  test('advertises the realm challenge', () {
    expect(authenticator.challenge, 'Basic realm="api"');
  });
}

class _RecordingStore implements UserStore {
  String? lastPassword;

  @override
  Future<AuthPrincipal?> verify(String username, String password) async {
    lastPassword = password;
    return AuthPrincipal(username);
  }
}
