# Changelog

## 0.12.0

- Version bump only (kept in lockstep with the workspace).

## 0.11.0

- Version bump only (kept in lockstep with the workspace).

## 0.10.0

- Version bump only (kept in lockstep with the workspace).

## 0.9.0

- Version bump only (kept in lockstep with the workspace).

## 0.8.1

- Version bump only (kept in lockstep with the workspace).

## 0.8.0

- Version bump only (kept in lockstep with the workspace).

## 0.7.0

- Version bump only (kept in lockstep with the workspace).

## 0.6.0

- Version bump only (kept in lockstep with the workspace).

## 0.5.0

- Added `grpcAuthInterceptor` — a server-wide `package:grpc` interceptor
  that authorizes calls from their metadata (UNAUTHENTICATED /
  PERMISSION_DENIED), wired by the generator from a `diana_auth`
  `AuthenticationMiddleware`.

## 0.4.0

- Version bump only (kept in lockstep with the Diana workspace).

## 0.3.0

- Initial release: `DianaGrpcServer` wraps `package:grpc`'s server with
  Diana configuration (`grpc.enabled`, `grpc.host`, `grpc.port`) and
  lifecycle (`serve()`/`shutdown()`/`port`). Used by the generator to serve
  `@GrpcService` classes next to the HTTP server. Single-isolate only:
  `serve()` fails fast when `server.isolates > 1`.
