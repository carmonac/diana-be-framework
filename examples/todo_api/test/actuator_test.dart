import 'dart:convert';
import 'dart:io';

import 'package:diana/diana.dart';
import 'package:test/test.dart';
import 'package:todo_api/app.diana_app.dart';

Future<(int, dynamic)> get(int port, String path) async {
  final client = HttpClient();
  try {
    final res = await (await client
            .getUrl(Uri.parse('http://127.0.0.1:$port$path')))
        .close();
    final text = await res.transform(utf8.decoder).join();
    return (res.statusCode, text.isEmpty ? null : jsonDecode(text));
  } finally {
    client.close();
  }
}

void main() {
  final config = DianaConfig({
    'app.info.name': 'test',
    'app.info.version': '0.0.0',
    'management.enabled': true,
    'info.app.description': 'todo example',
    'info.team': 'diana',
  });

  test('health aggregates indicators and reflects DOWN with 503', () async {
    final app = await buildDianaApp(config: config);
    await app.server.serve(port: 0, quiet: true);
    addTearDown(app.server.close);

    // Before initialize the repository is not warmed up -> DOWN.
    final (downStatus, down) = await get(app.server.port!, '/actuator/health');
    expect(downStatus, 503);
    expect(down['status'], 'DOWN');

    await app.initialize();
    final (upStatus, up) = await get(app.server.port!, '/actuator/health');
    expect(upStatus, 200);
    expect(up['status'], 'UP');
    expect(up['components']['todoRepository']['status'], 'UP');
    expect(up['components']['todoRepository']['details']['todos'], 1);
  });

  test('info serves the nested info.* config section', () async {
    final app = await buildDianaApp(config: config);
    await app.initialize();
    await app.server.serve(port: 0, quiet: true);
    addTearDown(app.server.close);

    final (status, body) = await get(app.server.port!, '/actuator/info');
    expect(status, 200);
    expect(body, {
      'app': {'description': 'todo example'},
      'team': 'diana',
    });
  });

  test('actuator endpoints are absent when management.enabled is false',
      () async {
    final app = await buildDianaApp(
      config: DianaConfig({
        'app.info.name': 'test',
        'app.info.version': '0.0.0',
      }),
    );
    await app.initialize();
    await app.server.serve(port: 0, quiet: true);
    addTearDown(app.server.close);

    final (status, _) = await get(app.server.port!, '/actuator/health');
    expect(status, 404);
  });
}
