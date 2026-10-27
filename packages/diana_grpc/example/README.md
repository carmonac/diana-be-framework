# diana_grpc example

```yaml
dependencies:
  diana: ^0.15.0
  diana_grpc: ^0.15.0
  grpc: ^5.0.0
  protobuf: ^6.0.0
```

Generate Dart code from your `.proto`, then extend the generated service
base. It is a regular singleton injectable — constructor injection,
`@Value` and lifecycle hooks all apply — and the generated `DianaApp`
serves it on its own port next to your HTTP controllers:

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

A complete app serving gRPC and HTTP side by side is in
[examples/greeter_grpc](https://github.com/carmonac/diana-be-framework/tree/main/examples/greeter_grpc).
See the [gRPC guide](https://carmonac.github.io/diana-be-framework/guides/grpc/).
