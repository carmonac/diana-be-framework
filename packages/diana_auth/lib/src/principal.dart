/// An authenticated identity.
///
/// Produced by an `Authenticator`, stamped onto the request by
/// `AuthenticationMiddleware` and consumed by guards and `@Principal()`
/// parameters. Subclass it if your application needs a richer identity.
class AuthPrincipal {
  /// Stable identifier of the caller (JWT `sub`, Basic username, …).
  final String name;

  /// Granted roles, checked by `@RolesAllowed` (any-of semantics).
  final Set<String> roles;

  /// Scheme-specific extras (e.g. the full JWT claim set).
  final Map<String, Object?> attributes;

  const AuthPrincipal(
    this.name, {
    this.roles = const {},
    this.attributes = const {},
  });

  bool hasRole(String role) => roles.contains(role);

  @override
  String toString() => 'AuthPrincipal($name, roles: $roles)';
}
