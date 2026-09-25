# Authentication and authorization

Diana's Spring Security analog lives in the optional **`diana_auth`**
package: pluggable authentication strategies, an injectable principal, and
`@Secured` / `@RolesAllowed` guards the generator wires into your routes,
WebSocket handshakes and gRPC services.

The design splits **authentication** (who are you?) from **authorization**
(are you allowed?), exactly like Spring:

- An **`AuthenticationMiddleware`** runs a chain of strategies and stamps
  the authenticated principal onto the request. It never rejects anonymous
  requests — it only establishes identity.
- **Guards** (`@Secured`, `@RolesAllowed`) enforce access at each route.

## Setup

```yaml
# pubspec.yaml
dependencies:
  diana: ^0.15.0
  diana_auth: ^0.15.0
```

## Assembling the authentication filter

Subclass `AuthenticationMiddleware`, pick the strategies your app accepts,
and register it — usually as a `@GlobalMiddleware` so it runs before every
route:

```dart
import 'package:diana/diana.dart';
import 'package:diana_auth/diana_auth.dart';

@GlobalMiddleware(order: -100)
class AppAuth extends AuthenticationMiddleware {
  AppAuth(@Value('auth.jwt.secret') String secret)
      : super(authenticators: [
          JwtAuthenticator(Hs256TokenVerifier(secret)),
          ApiKeyAuthenticator(myKeyStore),
        ]);
}
```

Strategies run in order; the first one that recognizes credentials wins.
A strategy returns `null` when the request carries no credentials **for
its scheme** (the chain continues), or throws `InvalidCredentialsException`
when credentials are present but invalid — an immediate 401 with a
`WWW-Authenticate` challenge (a bad token is never silently downgraded to
anonymous). A request with no credentials at all passes through
anonymously; enforcement happens at the guards.

## Built-in strategies

All produce an `AuthPrincipal { String name; Set<String> roles;
Map<String, Object?> attributes; }` and implement the `Authenticator`
interface, so you can add your own.

### JWT (`Authorization: Bearer <token>`)

```dart
JwtAuthenticator(Hs256TokenVerifier(secret), rolesClaim: 'roles')
```

`Hs256TokenVerifier` validates HS256 signatures **in-package** (no
heavyweight dependency) and is hardened: it accepts only `alg: HS256`
(rejecting `none` and algorithm-confusion), compares signatures in
constant time, and enforces `exp`/`nbf` with a configurable clock skew
plus optional `iss`/`aud` checks. `sub` becomes the principal name; the
roles claim accepts a JSON list or a space-delimited string (covering
OAuth `scope`).

To mint tokens (login endpoints, tests) use `Hs256TokenSigner`:

```dart
final token = Hs256TokenSigner(secret)
    .sign(Hs256TokenSigner.claimsFor('ada', roles: {'admin'}));
```

### RS256 and JWKS (external identity providers)

For tokens minted by an IdP (Auth0, Keycloak, Cognito, Firebase, Entra ID)
verify RS256 **in-package** — RSA signature verification is pure Dart
(`BigInt.modPow` + an exact encode-then-compare of the PKCS#1 v1.5
padding), no new dependency:

```dart
// Keys rotate behind the IdP's JWKS endpoint (the common case):
JwtAuthenticator(JwksTokenVerifier(
  Uri.parse('https://idp.example.com/.well-known/jwks.json'),
  issuer: 'https://idp.example.com/',
  audience: 'my-api',
))

// Or a static public key — from a JWK or a PEM file:
JwtAuthenticator(Rs256TokenVerifier.single(
  RsaPublicKey.fromPem(pemString),   // BEGIN (RSA) PUBLIC KEY
))
```

`JwksTokenVerifier` fetches the key set lazily, caches it (`cacheTtl`,
default 10 min) and handles **rotation** the standard way: a token with an
unknown `kid` triggers one immediate re-fetch, rate-limited by
`refreshCooldown` (default 30 s) so bogus `kid`s cannot hammer the IdP.
When a refresh fails, previously cached keys keep serving
(stale-while-error). Call `close()` from `@PreDestroy` to release the HTTP
client.

Both verifiers enforce the same hardening as HS256: exact `alg: RS256`
(the RS→HS downgrade dies on the algorithm check before any key is used),
`exp`/`nbf` with clock skew, and optional `issuer`/`audience`. Malformed
tokens are rejected **before** any network fetch.

`TokenVerifier.verify` returns `FutureOr`, so custom verifiers may be
async; the built-in HS256/RS256 ones stay synchronous.

### HTTP Basic

```dart
BasicAuthenticator(myUserStore, realm: 'api')
```

Provide a `UserStore { Future<AuthPrincipal?> verify(String username,
String password); }`. The store owns password hashing — Diana never sees a
hash.

### API key

```dart
ApiKeyAuthenticator(myValidator, headerName: 'X-API-Key')
```

Provide an `ApiKeyValidator { Future<AuthPrincipal?> validate(String key); }`.

## Authorizing routes

Annotate controllers or methods (method-level replaces controller-level,
like `@CrossOrigin`):

```dart
@RestController('/admin')
@Secured()                              // every route requires auth
class AdminController {
  @Get('/stats')
  Stats stats() => ...;

  @Delete('/users/:id')
  @RolesAllowed(['admin'])              // ...and this one, the admin role
  void deleteUser(@PathParam() int id) => ...;
}
```

- `@Secured()` → **401** for anonymous requests.
- `@RolesAllowed([...])` → 401 for anonymous, **403** when the principal
  holds **none** of the listed roles (any-of semantics). It implies
  `@Secured`.

The generator appends the matching guard as the **last** middleware of the
route, so it runs after your authentication filter and immediately before
the handler. Fail-closed: with no authentication middleware present, every
request is anonymous and secured routes return 401.

A security annotation placed where it would have no effect (a `@Service`, a
non-route method) is a **build error** — a silently ignored guard is a hole
you think is closed.

## Reading the principal

Bind it with `@Principal()`:

```dart
@Get('/me')
@Secured()
Profile me(@Principal() AuthPrincipal user) => Profile(user.name, user.roles);
```

A non-nullable parameter throws 401 when unauthenticated; a nullable one
(`AuthPrincipal?`) receives `null`. In middleware or raw handlers, read
`request.attributes[principalAttributeKey]` directly (the constant is
exported from `package:diana`).

## WebSockets

Authentication is applied at the **handshake**. Global middleware do **not**
run on handshakes, so list the authentication middleware explicitly and add
a guard:

```dart
@WebSocketController('/ws/chat/:room')
@UseMiddleware([AppAuth])   // authenticate the upgrade
@Secured()                  // reject anonymous upgrades with 401
class ChatHandler extends BaseWebSocketHandler {
  @override
  void onOpen(WebSocketSession session) {
    final principal = session.attributes[principalAttributeKey];
    // ...the authenticated principal is copied into the session.
  }
}
```

## gRPC

gRPC services are secured the same way — `@Secured` / `@RolesAllowed` on the
`@GrpcService` class. The generator discovers your `AuthenticationMiddleware`
provider and installs a `package:grpc` interceptor that authorizes calls
from their metadata (`authorizeMetadata`), returning `UNAUTHENTICATED` or
`PERMISSION_DENIED`.

Limitations (v1): gRPC interceptors are **server-wide**, so every
`@GrpcService` must declare identical security (a build error otherwise);
principal injection into service methods is not yet available.

## Configuration

`diana_auth` reads no keys itself — your middleware pulls them via `@Value`.
By convention:

| Key | Meaning |
|---|---|
| `auth.jwt.secret` | HS256 signing/verification secret (env `AUTH_JWT_SECRET`) |
| `auth.jwt.jwksUri` | JWKS endpoint of the identity provider (env `AUTH_JWT_JWKSURI`) |
| `auth.jwt.issuer` / `auth.jwt.audience` | Expected `iss`/`aud` claims |

## Extending

- Implement `Authenticator` for a custom scheme and add it to the chain.
- Implement `TokenVerifier` for other algorithms (ES256, EdDSA) or an
  external JWT library — `verify` may be async.
- Subclass `AuthPrincipal` for a richer identity — `@Principal` binds any
  class type.

## See also

- [Middleware](middleware.md) — the pipeline guards and filters run in
- [WebSockets](websockets.md) — handshake interceptors
- [gRPC](grpc.md) — serving gRPC
- [Build diagnostics](../reference/build-diagnostics.md) — the auth errors
