# diana_auth example

```yaml
dependencies:
  diana: ^0.15.0
  diana_auth: ^0.15.0
```

Register one authentication filter with the strategies your app accepts —
strategies run in order and the first that recognizes credentials wins:

```dart
import 'package:diana/diana.dart';
import 'package:diana_auth/diana_auth.dart';

@GlobalMiddleware(order: -100)
class AppAuth extends AuthenticationMiddleware {
  AppAuth(@Value('auth.jwt.secret') String secret)
      : super(authenticators: [
          JwtAuthenticator(Hs256TokenVerifier(secret)),
        ]);
}
```

Then guard routes and bind the authenticated principal:

```dart
import 'package:diana/diana.dart';
import 'package:diana_auth/diana_auth.dart';

part 'admin_controller.diana.dart';

@RestController('/admin')
@Secured() // every route requires an authenticated request (401 otherwise)
class AdminController {
  @Get('/me')
  Map<String, Object?> me(@Principal() AuthPrincipal user) =>
      {'name': user.name, 'roles': user.roles.toList()};

  @Delete('/users/:id')
  @RolesAllowed(['admin']) // 403 unless the principal has the admin role
  void deleteUser(@PathParam() int id) {}
}
```

See the [authentication & authorization guide](https://carmonac.github.io/diana-be-framework/guides/auth/)
for Basic and API-key strategies, RS256/JWKS verification and WebSocket and
gRPC security.
