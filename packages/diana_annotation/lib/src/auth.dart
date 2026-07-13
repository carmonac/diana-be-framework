import 'package:meta/meta_meta.dart';

/// Requires an authenticated principal to access the route(s).
///
/// On a controller it applies to every route; on a method it **replaces**
/// the controller-level declaration. Anonymous requests get a **401**.
/// Also valid on `@WebSocketController` classes (blocks the handshake) and
/// `@GrpcService` classes (server-wide interceptor; see the auth guide).
///
/// Authentication itself is performed by an `AuthenticationMiddleware`
/// (package `diana_auth`) registered by the application — typically as
/// `@GlobalMiddleware`. `@Secured` only enforces that it succeeded.
@Target({TargetKind.classType, TargetKind.method})
class Secured {
  const Secured();
}

/// Requires an authenticated principal holding **any** of [roles]
/// (JSR-250 semantics). Implies [Secured]: anonymous → 401, authenticated
/// but missing every role → 403.
///
/// Same targets and method-replaces-controller precedence as [Secured].
@Target({TargetKind.classType, TargetKind.method})
class RolesAllowed {
  final List<String> roles;
  const RolesAllowed(this.roles);
}

/// Binds the authenticated principal to a route-method parameter (Spring:
/// `@AuthenticationPrincipal`).
///
/// A non-nullable parameter throws a 401 when no principal is present; a
/// nullable parameter receives `null`. The parameter type is the type your
/// authenticators produce (`AuthPrincipal` or a subclass).
@Target({TargetKind.parameter})
class Principal {
  const Principal();
}
