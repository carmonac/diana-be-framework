import 'package:diana/diana.dart';
import 'package:diana_auth/diana_auth.dart';
import 'package:test/test.dart';

DianaRequest req({AuthPrincipal? principal}) {
  final request = DianaRequest(method: HttpMethod.get, uri: Uri.parse('/x'));
  if (principal != null) {
    request.attributes[principalAttributeKey] = principal;
  }
  return request;
}

DianaResponse ok(DianaRequest r) => const DianaResponse.text('ok');

void main() {
  test('SecuredGuard: anonymous → 401, authenticated → pass', () async {
    const guard = SecuredGuard();
    expect(() => guard.handle(req(), ok),
        throwsA(isA<UnauthorizedException>()));
    final res = await guard.handle(
        req(principal: const AuthPrincipal('ada')), ok);
    expect(res.statusCode, 200);
  });

  test('RolesGuard: 401 anonymous, 403 missing role, any-of passes',
      () async {
    const guard = RolesGuard(['admin', 'ops']);
    expect(() => guard.handle(req(), ok),
        throwsA(isA<UnauthorizedException>()));
    expect(
      () => guard.handle(
          req(principal: const AuthPrincipal('ada', roles: {'user'})), ok),
      throwsA(isA<ForbiddenException>()),
    );
    final res = await guard.handle(
        req(principal: const AuthPrincipal('ada', roles: {'ops'})), ok);
    expect(res.statusCode, 200);
  });
}
