import 'package:diana/diana.dart';
import 'package:grpc/grpc.dart' show ServiceCall;

import '../src/generated/greeter.pbgrpc.dart';

/// A protoc-generated service wired through Diana: `@GrpcService` classes
/// extend their `XServiceBase` and join the DI graph (constructor
/// injection, `@Value`, lifecycle — everything applies).
@GrpcService()
class GreeterService extends GreeterServiceBase {
  final String greetingPrefix;

  GreeterService(
      @Value('app.greeting', defaultValue: 'Hello') this.greetingPrefix);

  @override
  Future<HelloReply> sayHello(ServiceCall call, HelloRequest request) async =>
      HelloReply()..message = '$greetingPrefix, ${request.name}!';
}
