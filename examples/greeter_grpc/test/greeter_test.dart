import 'dart:convert';
import 'dart:io';

import 'package:diana/diana.dart';
import 'package:greeter_grpc/app.diana_app.dart';
import 'package:greeter_grpc/src/generated/greeter.pbgrpc.dart';
import 'package:grpc/grpc.dart' as grpc;
import 'package:test/test.dart';

void main() {
  test('serves gRPC and HTTP side by side from one DI graph', () async {
    final app = await buildDianaApp(
      config: DianaConfig({
        'grpc.port': 0,
        'app.greeting': 'Hola',
      }),
    );
    await app.initialize(); // starts the gRPC server
    await app.server.serve(port: 0, quiet: true);
    addTearDown(() async {
      await app.server.close();
      await app.dispose();
    });

    // gRPC call through the protoc-generated client.
    final channel = grpc.ClientChannel(
      '127.0.0.1',
      port: app.grpcServer.port!,
      options: const grpc.ChannelOptions(
        credentials: grpc.ChannelCredentials.insecure(),
      ),
    );
    final reply =
        await GreeterClient(channel).sayHello(HelloRequest()..name = 'Diana');
    expect(reply.message, 'Hola, Diana!');
    await channel.shutdown();

    // HTTP still works on its own port.
    final http = HttpClient();
    final res = await (await http.getUrl(
            Uri.parse('http://127.0.0.1:${app.server.port}/hello')))
        .close();
    expect(jsonDecode(await res.transform(utf8.decoder).join()),
        {'transport': 'http'});
    http.close();
  });

  test('grpc.enabled: false skips the gRPC server', () async {
    final app = await buildDianaApp(
      config: DianaConfig({'grpc.enabled': false}),
    );
    await app.initialize();
    addTearDown(app.dispose);
    expect(app.grpcServer.port, isNull);
  });
}
