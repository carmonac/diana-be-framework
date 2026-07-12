import 'dart:convert';
import 'dart:io';

import 'package:diana/diana.dart';
import 'package:test/test.dart';
import 'package:todo_api/app.diana_app.dart';
import 'package:todo_api/dto/todo_dto.dart';
import 'package:todo_api/repositories/todo_repository.dart';

class FakeTodoRepository implements InMemoryTodoRepository {
  @override
  bool warmedUp = false;

  @override
  bool shutDown = false;

  @override
  Future<void> warmUp() async => warmedUp = true;

  @override
  void shutdown() => shutDown = true;

  @override
  List<TodoDto> findAll({int limit = 20}) =>
      const [TodoDto(id: 99, title: 'fake todo')];

  @override
  TodoDto? find(int id) => null;

  @override
  TodoDto save(String title) => TodoDto(id: 100, title: title);

  @override
  bool delete(int id) => false;
}

void main() {
  // initialize() constructs @ConfigurationProperties eagerly, so tests must
  // provide the required keys (fail-at-startup semantics working as designed).
  final testConfig = DianaConfig({
    'app.info.name': 'test',
    'app.info.version': '0.0.0',
  });

  test('initialize runs @PostConstruct, dispose runs @PreDestroy', () async {
    final app = await buildDianaApp(config: testConfig);
    expect(app.context.inMemoryTodoRepository.warmedUp, isFalse);
    await app.initialize();
    expect(app.context.inMemoryTodoRepository.warmedUp, isTrue);
    expect(app.context.inMemoryTodoRepository.shutDown, isFalse);
    await app.dispose();
    expect(app.context.inMemoryTodoRepository.shutDown, isTrue);
  });

  test('DianaOverrides replaces a provider everywhere', () {
    final fake = FakeTodoRepository();
    final ctx = buildDianaContext(
      overrides: DianaOverrides(inMemoryTodoRepository: fake),
    );
    expect(identical(ctx.todoService.repo, fake), isTrue);
    expect(ctx.todoService.list(10).single.title, 'fake todo');
  });

  test('request-scoped providers get a fresh instance per request',
      () async {
    final app = await buildDianaApp(config: testConfig);
    await app.initialize();
    await app.server.serve(port: 0, quiet: true);
    addTearDown(() async {
      await app.server.close();
      await app.dispose();
    });

    Future<int> requestId() async {
      final client = HttpClient();
      try {
        final res = await (await client.getUrl(
                Uri.parse('http://127.0.0.1:${app.server.port}/audit')))
            .close();
        final body = jsonDecode(await res.transform(utf8.decoder).join());
        return body['requestId'] as int;
      } finally {
        client.close();
      }
    }

    final first = await requestId();
    final second = await requestId();
    expect(first, isNot(second));
  });
}
