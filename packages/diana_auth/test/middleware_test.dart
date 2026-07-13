import 'dart:async';

import 'package:diana/diana.dart';
import 'package:diana_auth/diana_auth.dart';
import 'package:test/test.dart';

DianaRequest req({Map<String, List<String>> headers = const {}}) =>
    DianaRequest(
      method: HttpMethod.get,
      uri: Uri.parse('/x'),
      headers: headers,
    );

/// Recognizes `x-fake: <name>[:bad]`.
class FakeAuthenticator implements Authenticator {
  final String? challengeValue;
  final List<String> calls = [];

  FakeAuthenticator({this.challengeValue});

  @override
  String? get challenge => challengeValue;

  @override
  FutureOr<AuthPrincipal?> authenticate(AuthRequest request) {
    final value = request.header('x-fake');
    calls.add(value ?? '(none)');
    if (value == null) return null;
    if (value.endsWith(':bad')) {
      throw const InvalidCredentialsException('bad fake credentials');
    }
    return AuthPrincipal(value, roles: const {'user'});
  }
}

void main() {
  test('runs strategies in order; first principal wins', () async {
    final first = FakeAuthenticator();
    final second = FakeAuthenticator();
    final auth =
        AuthenticationMiddleware(authenticators: [first, second]);
    final principal = await auth.authenticate(
      MapAuthRequest({'x-fake': 'ada'}),
    );
    expect(principal!.name, 'ada');
    expect(first.calls, ['ada']);
    expect(second.calls, isEmpty, reason: 'chain stops at the first match');
  });

  test('stamps the principal under the package:diana contract key',
      () async {
    final auth = AuthenticationMiddleware(
      authenticators: [FakeAuthenticator()],
    );
    final r = req(headers: {
      'x-fake': ['ada'],
    });
    await auth.handle(r, (rq) => const DianaResponse.text('ok'));
    final stamped = r.attributes[principalAttributeKey];
    expect(stamped, isA<AuthPrincipal>());
    expect((stamped as AuthPrincipal).name, 'ada');
  });

  test('no credentials pass through anonymously', () async {
    final auth = AuthenticationMiddleware(
      authenticators: [FakeAuthenticator()],
    );
    final r = req();
    final res = await auth.handle(r, (rq) => const DianaResponse.text('ok'));
    expect(res.statusCode, 200);
    expect(r.attributes.containsKey(principalAttributeKey), isFalse);
  });

  test('invalid credentials short-circuit to 401 with WWW-Authenticate',
      () async {
    final auth = AuthenticationMiddleware(
      authenticators: [FakeAuthenticator(challengeValue: 'Fake realm="t"')],
    );
    var reached = false;
    final res = await auth.handle(
      req(headers: {
        'x-fake': ['eve:bad'],
      }),
      (rq) {
        reached = true;
        return const DianaResponse.text('ok');
      },
    );
    expect(res.statusCode, 401);
    expect(res.headers['www-authenticate'], 'Fake realm="t"');
    expect(reached, isFalse);
  });

  test('attaches the challenge to downstream 401s (and can be disabled)',
      () async {
    final authenticators = [FakeAuthenticator(challengeValue: 'Fake')];
    final auth = AuthenticationMiddleware(authenticators: authenticators);
    final res = await auth.handle(
      req(),
      (rq) => const DianaResponse(statusCode: 401),
    );
    expect(res.headers['www-authenticate'], 'Fake');

    final quiet = AuthenticationMiddleware(
      authenticators: authenticators,
      challengeOnUnauthorized: false,
    );
    final quietRes = await quiet.handle(
      req(),
      (rq) => const DianaResponse(statusCode: 401),
    );
    expect(quietRes.headers.containsKey('www-authenticate'), isFalse);
  });

  test('authorizeMetadata: roles for valid, null for anonymous or invalid',
      () async {
    final auth = AuthenticationMiddleware(
      authenticators: [FakeAuthenticator()],
    );
    expect(await auth.authorizeMetadata({'x-fake': 'ada'}), {'user'});
    expect(await auth.authorizeMetadata({}), isNull);
    expect(await auth.authorizeMetadata({'x-fake': 'eve:bad'}), isNull);
  });
}
