# gRPC

Diana serves gRPC next to HTTP from the same dependency injection graph:
annotate a class extending your protoc-generated service base with
`@GrpcService()` and the generated `DianaApp` runs a gRPC server on its
own port, integrated with the application lifecycle.

gRPC support lives in a separate package, **`diana_grpc`** — the only
Diana package that depends on `package:grpc`. HTTP-only applications carry
no gRPC dependency.

## Setup

```yaml
# pubspec.yaml
dependencies:
  diana: ^0.15.1
  diana_grpc: ^0.15.1
  grpc: ^5.0.0
  protobuf: ^6.0.0
```

Generate Dart code from your `.proto` (commit the output — it's source):

```bash
dart pub global activate protoc_plugin
protoc --dart_out=grpc:lib/src/generated -Iprotos protos/greeter.proto
```

## Writing a service

Extend the generated `XServiceBase` and annotate it. The class is a
regular singleton injectable — constructor injection, `@Value`,
`@PostConstruct`, everything applies:

```dart
import 'package:diana/diana.dart';
import 'package:grpc/grpc.dart' show ServiceCall;

import '../src/generated/greeter.pbgrpc.dart';

@GrpcService()
class GreeterService extends GreeterServiceBase {
  final String greetingPrefix;

  GreeterService(
      @Value('app.greeting', defaultValue: 'Hello') this.greetingPrefix);

  @override
  Future<HelloReply> sayHello(ServiceCall call, HelloRequest request) async =>
      HelloReply()..message = '$greetingPrefix, ${request.name}!';
}
```

The class must extend a `package:grpc` `Service` (your protoc-generated
base does) — anything else is a build error. `@GrpcService` cannot be
combined with other role annotations (`@Service`, `@RestController`, …).

## What the generator wires

With at least one `@GrpcService` class, the composition root gains a
`DianaGrpcServer` holding every service, exposed as `app.grpcServer`:

- `initialize()` starts gRPC after `@PostConstruct` hooks ran.
- Graceful shutdown stops gRPC **first** (waiting for in-flight calls),
  then HTTP.
- `app.grpcServer.port` is the bound port (useful with `grpc.port: 0` in
  tests).

Without `@GrpcService` classes nothing is emitted and `diana_grpc` isn't
referenced.

## Configuration

| Key | Default | Meaning |
|---|---|---|
| `grpc.enabled` | `true` | Serve gRPC (`false` skips serving; `grpcServer` stays null-op) |
| `grpc.host` | `0.0.0.0` | Bind address |
| `grpc.port` | `9090` | Port (`0` for ephemeral in tests) |

Standard HTTP keys are untouched — the servers are independent.

## Limitations (v0.3)

- **Single isolate only**: with `server.isolates > 1`, `serve()` fails
  fast (`gRPC serving supports a single isolate; set server.isolates to 1
  or disable gRPC.`). Socket sharing across isolates for gRPC is
  unverified.
- Interceptors can be passed to a hand-constructed `DianaGrpcServer` but
  are not yet discoverable through DI.
- No TLS for the gRPC listener yet (put a proxy in front, or serve
  HTTP-only behind the same proxy).

## Trying it

The [greeter_grpc example](../../examples/greeter_grpc) is a complete
HTTP+gRPC app with committed protoc output and end-to-end tests. With
[grpcurl](https://github.com/fullstorydev/grpcurl):

```bash
grpcurl -plaintext -import-path protos -proto greeter.proto \
    -d '{"name": "Diana"}' localhost:9090 greeter.Greeter/SayHello
```

## See also

- [Application lifecycle](lifecycle.md) — startup/shutdown ordering
- [Configuration keys](../reference/config-keys.md) — the `grpc.*` keys
- [Build diagnostics](../reference/build-diagnostics.md) — `@GrpcService` errors
