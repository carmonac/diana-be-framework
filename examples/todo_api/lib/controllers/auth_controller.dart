import 'package:diana/diana.dart';
import 'package:diana_auth/diana_auth.dart';

part 'auth_controller.diana.dart';

/// Login credentials. Demo only — any username authenticates with the
/// password `password`; `ada` additionally receives the `admin` role.
@Json()
class LoginRequest {
  @NotBlank()
  final String username;

  @NotBlank()
  final String password;

  const LoginRequest({required this.username, required this.password});
}

/// Issues and inspects tokens.
@RestController('/auth')
class AuthController {
  final String secret;

  AuthController(
      @Value('auth.jwt.secret', defaultValue: 'insecure-dev-secret')
      this.secret);

  /// Mints an HS256 JWT for valid credentials.
  @Post('/login')
  Map<String, dynamic> login(@Body() LoginRequest body) {
    if (body.password != 'password') {
      throw const UnauthorizedException('Bad username or password.');
    }
    final roles = body.username == 'ada' ? {'admin'} : <String>{'user'};
    final token = Hs256TokenSigner(secret)
        .sign(Hs256TokenSigner.claimsFor(body.username, roles: roles));
    return {'token': token};
  }

  /// Echoes the authenticated identity — demonstrates `@Principal` binding.
  @Get('/me')
  @Secured()
  Map<String, dynamic> me(@Principal() AuthPrincipal user) =>
      {'name': user.name, 'roles': user.roles.toList()};
}
