import 'package:meta/meta_meta.dart';

/// Registers a class extending a protoc-generated `XServiceBase`
/// (`package:grpc`'s `Service`) as a gRPC service.
///
/// The class joins the dependency injection graph as a singleton
/// (constructor injection works as usual). The generated `DianaApp` serves
/// all `@GrpcService` classes on `grpc.port` (default 9090) through
/// `package:diana_grpc`, started after initialization and stopped on
/// graceful shutdown. Requires a dependency on `diana_grpc`.
@Target({TargetKind.classType})
class GrpcService {
  const GrpcService();
}
