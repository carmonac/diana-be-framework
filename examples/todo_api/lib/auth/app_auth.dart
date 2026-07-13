import 'package:diana/diana.dart';
import 'package:diana_auth/diana_auth.dart';

/// The application's authentication filter (Spring: the security filter
/// chain). Registered as a global middleware so it runs before every HTTP
/// route; also listed via `@UseMiddleware` on the WebSocket controller
/// (global middleware do not run on handshakes).
///
/// It accepts two credential schemes: a JWT `Authorization: Bearer` token
/// (minted by `/auth/login`) and a static API key (`X-API-Key`). Neither
/// is required — routes opt into enforcement with `@Secured` /
/// `@RolesAllowed`.
@GlobalMiddleware(order: -100)
class AppAuth extends AuthenticationMiddleware {
  AppAuth(
      @Value('auth.jwt.secret', defaultValue: 'insecure-dev-secret')
      String secret)
      : super(authenticators: [
          JwtAuthenticator(Hs256TokenVerifier(secret)),
          ApiKeyAuthenticator(const _DemoApiKeys()),
        ]);
}

/// A trivial in-memory key store: the single demo key grants the admin role.
/// A real app would look keys up in a database and hash them.
class _DemoApiKeys implements ApiKeyValidator {
  const _DemoApiKeys();

  @override
  Future<AuthPrincipal?> validate(String key) async => key == 'secret'
      ? const AuthPrincipal('key-holder', roles: {'admin'})
      : null;
}
