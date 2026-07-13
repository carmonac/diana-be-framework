import 'dart:async';

import 'package:diana/diana.dart';

import 'authenticator.dart';
import 'principal.dart';

/// Runs a chain of [Authenticator] strategies and stamps the resulting
/// principal onto the request (Spring: the authentication filter).
///
/// Register it by subclassing — the subclass picks the strategies and is a
/// regular Diana middleware:
///
/// ```dart
/// @GlobalMiddleware(order: -100)
/// class AppAuth extends AuthenticationMiddleware {
///   AppAuth(@Value('auth.jwt.secret') String secret)
///       : super(authenticators: [
///           JwtAuthenticator(Hs256TokenVerifier(secret)),
///         ]);
/// }
/// ```
///
/// Semantics:
/// - Strategies run in order; the first non-null principal wins and is
///   stored under [principalAttributeKey] (the `package:diana` contract
///   read by guards and `@Principal()` parameters).
/// - A strategy throwing [InvalidCredentialsException] short-circuits to
///   an immediate 401 with a `WWW-Authenticate` challenge — invalid
///   credentials are never degraded to an anonymous request.
/// - No credentials at all → the request continues anonymously;
///   enforcement happens at `@Secured`/`@RolesAllowed` guards.
/// - Downstream 401 responses get the `WWW-Authenticate` challenge
///   attached (disable with [challengeOnUnauthorized]).
class AuthenticationMiddleware implements Middleware {
  final List<Authenticator> authenticators;

  /// Attach `WWW-Authenticate` challenges to 401 responses.
  final bool challengeOnUnauthorized;

  const AuthenticationMiddleware({
    required this.authenticators,
    this.challengeOnUnauthorized = true,
  });

  /// Runs the strategy chain. Returns the first principal, `null` when no
  /// strategy recognized credentials; rethrows invalid-credential errors.
  Future<AuthPrincipal?> authenticate(AuthRequest request) async {
    for (final authenticator in authenticators) {
      final principal = await authenticator.authenticate(request);
      if (principal != null) return principal;
    }
    return null;
  }

  /// The gRPC seam: authenticates a metadata map and returns the
  /// principal's roles, or `null` when anonymous **or** the credentials
  /// are invalid (gRPC has no challenge channel; both map to
  /// UNAUTHENTICATED at the interceptor).
  Future<Set<String>?> authorizeMetadata(Map<String, String> metadata) async {
    try {
      return (await authenticate(MapAuthRequest(metadata)))?.roles;
    } on InvalidCredentialsException {
      return null;
    }
  }

  String get _challengeHeader => [
        for (final authenticator in authenticators)
          if (authenticator.challenge != null) authenticator.challenge!,
      ].join(', ');

  DianaResponse _withChallenge(DianaResponse response) {
    final challenge = _challengeHeader;
    if (!challengeOnUnauthorized ||
        challenge.isEmpty ||
        response.headers.containsKey('www-authenticate')) {
      return response;
    }
    return response.copyWith(
      headers: {...response.headers, 'www-authenticate': challenge},
    );
  }

  @override
  Future<DianaResponse> handle(DianaRequest request, Next next) async {
    final AuthPrincipal? principal;
    try {
      principal = await authenticate(DianaAuthRequest(request));
    } on InvalidCredentialsException catch (e) {
      return _withChallenge(
        DianaResponse.json(
          {'error': 'unauthorized', 'message': e.message},
          statusCode: 401,
        ),
      );
    }
    if (principal != null) {
      request.attributes[principalAttributeKey] = principal;
    }
    final response = await next(request);
    return response.statusCode == 401 ? _withChallenge(response) : response;
  }
}
