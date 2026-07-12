import 'dart:io';

import 'package:diana/diana.dart' show DianaConfig;
import 'package:diana_grpc/diana_grpc.dart';
import 'package:grpc/grpc.dart' as grpc;
import 'package:test/test.dart';

/// A minimal hand-written unary service (protoc output not needed to test
/// the wrapper): method `/echo.Echo/Say` echoes bytes back upper-cased.
class EchoService extends Service {
  @override
  String get $name => 'echo.Echo';

  EchoService() {
    $addMethod(grpc.ServiceMethod<List<int>, List<int>>(
      'Say',
      (grpc.ServiceCall call, Stream<List<int>> request) async* {
        await for (final message in request) {
          yield String.fromCharCodes(message).toUpperCase().codeUnits;
        }
      },
      true,
      true,
      (List<int> bytes) => bytes,
      (List<int> bytes) => bytes,
    ));
  }
}

void main() {
  test('serves a Service and shuts down cleanly', () async {
    final server = DianaGrpcServer(
      const DianaConfig.empty(),
      services: [EchoService()],
    );
    await server.serve(port: 0, quiet: true);
    expect(server.port, isNotNull);

    final channel = grpc.ClientChannel(
      '127.0.0.1',
      port: server.port!,
      options: const grpc.ChannelOptions(
        credentials: grpc.ChannelCredentials.insecure(),
      ),
    );
    final client = grpc.Client(channel);
    final method = grpc.ClientMethod<List<int>, List<int>>(
      '/echo.Echo/Say',
      (List<int> bytes) => bytes,
      (List<int> bytes) => bytes,
    );
    final response = await client
        .$createStreamingCall(method, Stream.value('hola'.codeUnits))
        .single;
    expect(String.fromCharCodes(response), 'HOLA');

    await channel.shutdown();
    await server.shutdown();
    expect(server.port, isNull);
  });

  test('grpc.enabled: false skips serving', () async {
    final server = DianaGrpcServer(
      DianaConfig({'grpc.enabled': false}),
      services: [EchoService()],
    );
    await server.serve(quiet: true);
    expect(server.port, isNull);
  });

  test('multi-isolate config fails fast', () async {
    final server = DianaGrpcServer(
      DianaConfig({'server.isolates': 4}),
      services: [EchoService()],
    );
    await expectLater(
      server.serve(quiet: true),
      throwsA(isA<StateError>().having(
        (e) => e.message,
        'message',
        'gRPC serving supports a single isolate; set server.isolates to 1 '
            'or disable gRPC.',
      )),
    );
  });

  test('only diana_grpc imports package:grpc (boundary)', () {
    final offenders = <String>[];
    for (final package in ['diana', 'diana_annotation', 'diana_generator']) {
      final dir = Directory('../$package/lib');
      for (final entity in dir.listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        if (entity.readAsStringSync().contains("import 'package:grpc")) {
          offenders.add(entity.path);
        }
      }
    }
    expect(offenders, isEmpty);
  });
}
