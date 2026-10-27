# diana_auth

Authentication and authorization for the [Diana framework](https://github.com/carmonac/diana-be-framework):
a chain of pluggable authentication strategies (JWT HS256/RS256 with JWKS,
HTTP Basic, API key), an injectable principal, and Spring-style
`@Secured` / `@RolesAllowed` guards that the generator wires into routes,
WebSocket handshakes and gRPC services at compile time.

```yaml
dependencies:
  diana: ^0.15.1
  diana_auth: ^0.15.1
```

This is the only Diana package that depends on `package:crypto`; apps that
don't need security don't carry it.

Read the [authentication & authorization guide](https://carmonac.github.io/diana-be-framework/guides/auth/).
