# Changelog

## 0.3.0

- Initial release: `DianaGrpcServer` wraps `package:grpc`'s server with
  Diana configuration (`grpc.enabled`, `grpc.host`, `grpc.port`) and
  lifecycle (`serve()`/`shutdown()`/`port`). Used by the generator to serve
  `@GrpcService` classes next to the HTTP server. Single-isolate only:
  `serve()` fails fast when `server.isolates > 1`.
