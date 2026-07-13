import 'dart:convert';
import 'dart:io';

import 'package:diana/diana.dart';
import 'package:test/test.dart';
import 'package:todo_api/app.diana_app.dart';
import 'package:todo_api/events/todo_created.dart';

void main() {
  test('publishing delivers to @EventListener methods through the app',
      () async {
    final app = await buildDianaApp(
      config: DianaConfig({
        'server.port': 0,
        'api.key': 'secret',
        'app.info.name': 'test',
        'app.info.version': '0.0.0',
      }),
    );
    await app.initialize();
    addTearDown(app.dispose);
    await app.server.serve(quiet: true);
    addTearDown(app.server.close);

    final client = HttpClient();
    final req = await client
        .postUrl(Uri.parse('http://127.0.0.1:${app.server.port}/todos'));
    req.headers.contentType = ContentType.json;
    req.write(jsonEncode({'title': 'listen to events'}));
    final res = await req.close();
    expect(res.statusCode, 201);
    await res.drain<void>();
    client.close();

    // publish() is awaited inside TodoService.create, so by the time the
    // response arrived the listener has already run.
    expect(app.context.todoAuditListener.seen, ['listen to events']);
  });

  test('registration is lazy: a publish constructs the listener on demand',
      () async {
    // Context only — initialize() not called, so no singleton has been
    // constructed yet. The registered closure must construct the listener
    // when the first event fires, not before.
    final ctx = buildDianaContext(
      config: DianaConfig({
        'api.key': 'secret',
        'app.info.name': 'test',
        'app.info.version': '0.0.0',
      }),
    );
    await ctx.eventBus.publish(const TodoCreated(7, 'lazy'));
    expect(ctx.todoAuditListener.seen, ['lazy']);
  });
}
