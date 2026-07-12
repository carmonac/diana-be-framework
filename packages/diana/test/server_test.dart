import 'dart:convert';
import 'dart:io';

import 'package:diana/diana.dart';
import 'package:test/test.dart';

Future<(int, String)> httpGet(int port, String path,
    {Map<String, String> headers = const {}}) async {
  final client = HttpClient();
  try {
    final request =
        await client.getUrl(Uri.parse('http://127.0.0.1:$port$path'));
    headers.forEach(request.headers.add);
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    return (response.statusCode, body);
  } finally {
    client.close();
  }
}

void main() {
  group('DianaServer', () {
    late DianaServer server;

    setUp(() {
      server = DianaServer();
    });

    tearDown(() => server.close());

    test('serves a registered route', () async {
      server.register(
          HttpMethod.get, '/ping', (req) => const DianaResponse.text('pong'));
      await server.serve(port: 0);

      final (status, body) = await httpGet(server.port!, '/ping');
      expect(status, 200);
      expect(body, 'pong');
    });

    test('extracts path parameters and query parameters', () async {
      server.register(
        HttpMethod.get,
        '/users/:id',
        (req) => DianaResponse.json({
          'id': req.pathParameters['id'],
          'sort': req.queryParameters['sort'],
          'agent': req.header('X-Agent'),
        }),
      );
      await server.serve(port: 0);

      final (status, body) = await httpGet(
        server.port!,
        '/users/42?sort=asc',
        headers: {'x-agent': 'diana-test'},
      );
      expect(status, 200);
      expect(jsonDecode(body), {
        'id': '42',
        'sort': 'asc',
        'agent': 'diana-test',
      });
    });

    test('unknown routes return JSON 404', () async {
      server.register(
          HttpMethod.get, '/ping', (req) => const DianaResponse.text('pong'));
      await server.serve(port: 0);

      final (status, body) = await httpGet(server.port!, '/nope');
      expect(status, 404);
      expect(jsonDecode(body), containsPair('error', 'not_found'));
    });

    test('HttpException maps to its status code', () async {
      server.register(HttpMethod.get, '/missing',
          (req) => throw const NotFoundException('no such thing'));
      await server.serve(port: 0);

      final (status, body) = await httpGet(server.port!, '/missing');
      expect(status, 404);
      expect(jsonDecode(body), {
        'error': 'not_found',
        'message': 'no such thing',
      });
    });

    test('unhandled errors become opaque 500s', () async {
      Object? captured;
      server = DianaServer(onUnhandled: (e, st) => captured = e);
      server.register(
          HttpMethod.get, '/boom', (req) => throw StateError('secret'));
      await server.serve(port: 0);

      final (status, body) = await httpGet(server.port!, '/boom');
      expect(status, 500);
      expect(body, isNot(contains('secret')));
      expect(captured, isA<StateError>());
    });

    test('middleware wrap in order and can short-circuit', () async {
      final events = <String>[];
      server = DianaServer(globalMiddleware: [_Recorder('g1', events)]);
      server.register(
        HttpMethod.get,
        '/chain',
        (req) {
          events.add('handler');
          return const DianaResponse.text('ok');
        },
        middleware: [_Recorder('r1', events), _Guard()],
      );
      await server.serve(port: 0);

      final (status, _) = await httpGet(server.port!, '/chain');
      expect(status, 401);
      expect(events, ['g1:before', 'r1:before', 'r1:after', 'g1:after']);
    });
  });
}

class _Recorder implements Middleware {
  final String name;
  final List<String> events;
  _Recorder(this.name, this.events);

  @override
  Future<DianaResponse> handle(DianaRequest request, Next next) async {
    events.add('$name:before');
    final response = await next(request);
    events.add('$name:after');
    return response;
  }
}

class _Guard implements Middleware {
  @override
  Future<DianaResponse> handle(DianaRequest request, Next next) async =>
      DianaResponse.json({'error': 'unauthorized'}, statusCode: 401);
}
