/// gRPC support for the Diana backend framework.
///
/// Annotate classes extending your protoc-generated `XServiceBase` with
/// `@GrpcService()`; they join Diana's dependency injection graph, and the
/// generated `DianaApp` serves them on `grpc.port` alongside HTTP,
/// integrated with the application lifecycle (started after
/// `@PostConstruct`, stopped on graceful shutdown).
///
/// This is the **only** package in the Diana workspace that depends on
/// `package:grpc` (enforced by a boundary test) — HTTP-only applications
/// carry no gRPC dependency.
library;

import 'package:diana/diana.dart' show DianaConfig;
import 'package:grpc/grpc.dart';

export 'package:grpc/grpc.dart' show Interceptor, Service, ServiceCall;

/// Wraps a `package:grpc` server with Diana configuration and lifecycle.
///
/// Config keys: `grpc.enabled` (default `true`), `grpc.host` (default
/// `0.0.0.0`), `grpc.port` (default `9090`).
class DianaGrpcServer {
  final DianaConfig config;
  final List<Service> services;
  final List<Interceptor> interceptors;

  Server? _server;

  DianaGrpcServer(
    this.config, {
    required this.services,
    this.interceptors = const [],
  });

  /// Whether serving is enabled (`grpc.enabled`, default true).
  bool get enabled => config.get<bool>('grpc.enabled', defaultValue: true);

  /// Starts the gRPC server (no-op when [enabled] is false).
  ///
  /// Multi-isolate serving is not supported: gRPC's socket sharing across
  /// isolates is unverified, so this fails fast instead.
  Future<void> serve({int? port, bool quiet = false}) async {
    if (!enabled) return;
    if (config.get<int>('server.isolates', defaultValue: 1) > 1) {
      throw StateError(
        'gRPC serving supports a single isolate; set server.isolates to 1 '
        'or disable gRPC.',
      );
    }
    final host = config.get<String>('grpc.host', defaultValue: '0.0.0.0');
    _server = Server.create(services: services, interceptors: interceptors);
    await _server!.serve(
      address: host,
      port: port ?? config.get<int>('grpc.port', defaultValue: 9090),
    );
    if (!quiet) {
      // ignore: avoid_print
      print('[diana] gRPC listening on $host:${_server!.port}');
    }
  }

  /// The bound port, or `null` before [serve] (or when disabled).
  int? get port => _server?.port;

  /// Stops the server, waiting for in-flight calls.
  Future<void> shutdown() async {
    await _server?.shutdown();
    _server = null;
  }
}
