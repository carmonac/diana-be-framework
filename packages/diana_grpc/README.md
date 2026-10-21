# diana_grpc

gRPC support for the [Diana framework](https://github.com/carmonac/diana-be-framework):
annotate a class extending your protoc-generated service base with
`@GrpcService()` and the generated `DianaApp` serves it on its own port,
from the same dependency injection graph and lifecycle as your HTTP
controllers.

```yaml
dependencies:
  diana: ^0.15.0
  diana_grpc: ^0.15.0
```

This is the only Diana package that depends on `package:grpc`; HTTP-only
apps carry no gRPC dependency.

Read the [gRPC guide](https://carmonac.github.io/diana-be-framework/guides/grpc/).
