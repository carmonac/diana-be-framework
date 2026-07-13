import 'dart:async';

import 'package:diana/diana.dart' show DianaRequest, UnauthorizedException;

import 'principal.dart';

/// A transport-agnostic, headers-only view of an incoming request.
///
/// One contract serves HTTP requests, WebSocket handshakes (both are
/// [DianaRequest]s) and gRPC metadata maps.
abstract interface class AuthRequest {
  /// First value of [name], case-insensitive; `null` when absent.
  String? header(String name);
}

/// [AuthRequest] over a plain map (gRPC metadata, tests).
class MapAuthRequest implements AuthRequest {
  final Map<String, String> _headers;

  MapAuthRequest(Map<String, String> headers)
      : _headers = {
          for (final e in headers.entries) e.key.toLowerCase(): e.value,
        };

  @override
  String? header(String name) => _headers[name.toLowerCase()];
}

/// [AuthRequest] over a [DianaRequest] (HTTP routes and WS handshakes).
class DianaAuthRequest implements AuthRequest {
  final DianaRequest _request;

  DianaAuthRequest(this._request);

  @override
  String? header(String name) => _request.header(name);
}

/// Thrown by an [Authenticator] when the request *does* carry credentials
/// for its scheme but they are invalid (bad signature, expired token,
/// wrong password, unknown API key…). Mapped to a **401** immediately —
/// invalid credentials are never silently degraded to anonymous.
class InvalidCredentialsException extends UnauthorizedException {
  const InvalidCredentialsException([super.message = 'Invalid credentials']);
}

/// One authentication strategy (Spring: an `AuthenticationProvider`).
///
/// Contract:
/// - Return `null` when the request carries **no credentials for this
///   scheme** — the chain moves on to the next strategy.
/// - Return an [AuthPrincipal] on success.
/// - Throw [InvalidCredentialsException] when credentials for this scheme
///   are present but invalid.
abstract interface class Authenticator {
  /// The `WWW-Authenticate` challenge advertised on 401 responses (e.g.
  /// `Bearer`, `Basic realm="api"`), or `null` for schemes without one.
  String? get challenge;

  FutureOr<AuthPrincipal?> authenticate(AuthRequest request);
}
