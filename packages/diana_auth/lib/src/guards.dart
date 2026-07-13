import 'dart:async';

import 'package:diana/diana.dart';

import 'principal.dart';

/// Route guard behind `@Secured()`: rejects anonymous requests with a 401.
///
/// The generated composition root appends guards as the **last** element
/// of a route's middleware chain, so they always run after the
/// application's `AuthenticationMiddleware` (global, controller or route
/// level) and immediately before the handler. Fail-closed: without any
/// authentication middleware every request is anonymous and gets a 401.
class SecuredGuard implements Middleware {
  const SecuredGuard();

  @override
  FutureOr<DianaResponse> handle(DianaRequest request, Next next) {
    if (request.attributes[principalAttributeKey] is! AuthPrincipal) {
      throw const UnauthorizedException();
    }
    return next(request);
  }
}

/// Route guard behind `@RolesAllowed([...])`: 401 for anonymous requests,
/// 403 when the principal holds **none** of [roles] (JSR-250 any-of
/// semantics). Subsumes [SecuredGuard].
class RolesGuard implements Middleware {
  final List<String> roles;

  const RolesGuard(this.roles);

  @override
  FutureOr<DianaResponse> handle(DianaRequest request, Next next) {
    final principal = request.attributes[principalAttributeKey];
    if (principal is! AuthPrincipal) {
      throw const UnauthorizedException();
    }
    if (!roles.any(principal.hasRole)) {
      throw ForbiddenException(
        'Requires any of roles: ${roles.join(', ')}.',
      );
    }
    return next(request);
  }
}
