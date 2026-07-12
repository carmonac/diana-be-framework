# greeter_grpc

Diana example serving **gRPC and HTTP side by side** from one dependency
injection graph: a protoc-generated `Greeter` service annotated with
`@GrpcService()` (constructor injection, `@Value` config, lifecycle) plus a
regular `@RestController`.

```bash
dart run build_runner build
dart run bin/server.dart
# HTTP  → http://localhost:8080/hello
# gRPC  → localhost:9090 (greeter.Greeter/SayHello)
```

Try it with [grpcurl](https://github.com/fullstorydev/grpcurl):

```bash
grpcurl -plaintext -import-path protos -proto greeter.proto \
    -d '{"name": "Diana"}' localhost:9090 greeter.Greeter/SayHello
```

## Regenerating the protos

The protoc output under `lib/src/generated/` is committed. To regenerate:

```bash
dart pub global activate protoc_plugin
protoc --dart_out=grpc:lib/src/generated -Iprotos protos/greeter.proto
```

Config keys: `grpc.enabled` (default true), `grpc.host`, `grpc.port`
(default 9090). Note: gRPC serving requires `server.isolates: 1`.
