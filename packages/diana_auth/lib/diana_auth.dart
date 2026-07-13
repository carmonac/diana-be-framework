/// Authentication and authorization for the Diana backend framework
/// (Spring Security analog).
///
/// Assemble an [AuthenticationMiddleware] subclass with the strategies
/// your app accepts, register it (typically `@GlobalMiddleware`), and
/// protect routes with `@Secured()` / `@RolesAllowed([...])` — enforced by
/// guards the generator wires into each route. Handlers receive the
/// authenticated identity through `@Principal()` parameters.
///
/// This is the only Diana package that may import `package:crypto`
/// (enforced by a boundary test); it never touches `package:grpc` — the
/// gRPC seam is [AuthenticationMiddleware.authorizeMetadata].
library;

export 'src/api_key_authenticator.dart';
export 'src/authentication_middleware.dart';
export 'src/authenticator.dart';
export 'src/basic_authenticator.dart';
export 'src/guards.dart';
export 'src/jwt/jwt_authenticator.dart';
export 'src/jwt/jwt_signer.dart';
export 'src/jwt/token_verifier.dart';
export 'src/principal.dart';
