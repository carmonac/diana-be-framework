# Changelog

## 0.9.0

- Version bump only (kept in lockstep with the workspace).

## 0.8.1

- JWT claim hardening: numeric `sub` accepted, malformed `sub` rejects as
  401; a present but non-numeric (or non-finite) `exp`/`nbf` now rejects
  instead of crashing (500) or being silently skipped (fail-open).

## 0.8.0

- Version bump only (kept in lockstep with the workspace).

## 0.7.0

- Version bump only (kept in lockstep with the workspace).

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
