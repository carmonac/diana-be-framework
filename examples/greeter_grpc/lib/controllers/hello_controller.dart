import 'package:diana/diana.dart';

part 'hello_controller.diana.dart';

/// HTTP and gRPC share the same context: this controller and the
/// GreeterService are wired from one DI graph, served on two ports.
@RestController('/hello')
class HelloController {
  @Get()
  Map<String, dynamic> hello() => {'transport': 'http'};
}
