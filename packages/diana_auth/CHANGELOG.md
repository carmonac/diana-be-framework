# Changelog

## 0.6.0

- Version bump only (kept in lockstep with the workspace).

## 0.5.0

- Initial release: authentication and authorization for Diana (Spring
  Security analog).
- `AuthPrincipal`, the `Authenticator` strategy interface and
  `AuthenticationMiddleware` (strategy chain, principal stamping,
  `WWW-Authenticate` challenges, `authorizeMetadata` gRPC seam).
- Built-in strategies: `JwtAuthenticator` (in-package HS256 via
  `Hs256TokenVerifier`, pluggable `TokenVerifier`, `Hs256TokenSigner`),
  `BasicAuthenticator` (`UserStore`), `ApiKeyAuthenticator`
  (`ApiKeyValidator`).
- `SecuredGuard` / `RolesGuard` behind `@Secured` / `@RolesAllowed`.
- The only Diana package depending on `package:crypto`; never depends on
  `package:grpc`.
