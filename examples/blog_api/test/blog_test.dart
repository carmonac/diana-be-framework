import 'dart:convert';
import 'dart:io';

import 'package:blog_api/app.diana_app.dart';
import 'package:blog_api/caching/app_cache_store.dart';
import 'package:diana/diana.dart';
import 'package:test/test.dart';

late DianaApp appInstance;
late int port;

Future<(int, dynamic)> call(String method, String path, {Object? body}) async {
  final client = HttpClient();
  try {
    final req =
        await client.openUrl(method, Uri.parse('http://127.0.0.1:$port$path'));
    if (body != null) {
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode(body));
    }
    final res = await req.close();
    final text = await res.transform(utf8.decoder).join();
    return (res.statusCode, text.isEmpty ? null : jsonDecode(text));
  } finally {
    client.close();
  }
}

DianaConfig config() => DianaConfig({
      'server.port': 0,
      'management.enabled': true,
      'db.file': ':memory:',
      'db.migrations.dir': 'migrations',
    });

void main() {
  setUp(() async {
    // Fresh in-memory database per test.
    appInstance = await buildDianaApp(config: config());
    await appInstance.initialize();
    await appInstance.server.serve(quiet: true);
    port = appInstance.server.port!;
  });
  tearDown(() async {
    await appInstance.server.close();
    await appInstance.dispose();
  });

  test('migrations ran: the posts table is queryable and starts empty',
      () async {
    final (status, body) = await call('GET', '/posts');
    expect(status, 200);
    expect(body, isEmpty);
  });

  test('a @Transactional method commits both inserts', () async {
    final (status, body) = await call('POST', '/posts', body: {
      'first': {'title': 'a', 'body': 'aa'},
      'second': {'title': 'b', 'body': 'bb'},
    });
    expect(status, 201);
    expect(body, hasLength(2));

    final (_, all) = await call('GET', '/posts');
    expect(all, hasLength(2));
  });

  test('a throwing @Transactional method rolls back its insert', () async {
    final (status, _) =
        await call('POST', '/posts/fail', body: {'title': 'x', 'body': 'xx'});
    expect(status, 409);

    // The insert before the throw must have been undone.
    final (_, all) = await call('GET', '/posts');
    expect(all, isEmpty, reason: 'the transaction rolled back');
  });

  test('the database health indicator reports up', () async {
    final (status, body) = await call('GET', '/actuator/health');
    expect(status, 200);
    expect(body['components']['database']['status'], 'UP');
  });

  test('liveness and readiness endpoints respond', () async {
    expect((await call('GET', '/actuator/health/liveness')).$1, 200);
    expect((await call('GET', '/actuator/health/readiness')).$1, 200);
  });

  test('metrics endpoint scrapes as Prometheus text with expected series',
      () async {
    // Generate traffic across the observed surfaces.
    await call('POST', '/posts', body: {
      'first': {'title': 'a', 'body': 'aa'},
      'second': {'title': 'b', 'body': 'bb'},
    });
    await call('GET', '/posts');
    await call('GET', '/no/such/route'); // a 404

    final client = HttpClient();
    try {
      final res = await (await client.getUrl(
              Uri.parse('http://127.0.0.1:$port/actuator/metrics')))
          .close();
      expect(res.statusCode, 200);
      expect(res.headers.contentType?.value, contains('text/plain'));
      final text = await res.transform(utf8.decoder).join();
      // HTTP metrics labelled by route template, not concrete path.
      expect(text, contains('# TYPE diana_http_requests_total counter'));
      expect(text, contains('route="/posts"'));
      // Database and unmatched series populated.
      expect(text, contains('diana_db_queries_total'));
      expect(text, contains('diana_http_unmatched_total 1'));
      expect(text, contains('diana_process_resident_memory_bytes'));
    } finally {
      client.close();
    }
  });

  test('@Cacheable serves the cached count and @Timed feeds metrics',
      () async {
    await call('POST', '/posts', body: {
      'first': {'title': 'a', 'body': 'a'},
      'second': {'title': 'b', 'body': 'b'},
    });
    final (s1, first) = await call('GET', '/posts/stats/total');
    expect(s1, 200);
    expect(first['total'], 2);

    // New writes are invisible through the cache within the TTL.
    await call('POST', '/posts', body: {
      'first': {'title': 'c', 'body': 'c'},
      'second': {'title': 'd', 'body': 'd'},
    });
    final (s2, second) = await call('GET', '/posts/stats/total');
    expect(s2, 200);
    expect(second['total'], 2, reason: 'cache hit skips the database');

    final client = HttpClient();
    final res = await (await client
            .getUrl(Uri.parse('http://127.0.0.1:$port/actuator/metrics')))
        .close();
    final scrape = await res.transform(utf8.decoder).join();
    client.close();
    expect(scrape, contains('diana_method_duration_seconds'));
    expect(
        scrape,
        contains('diana_method_calls_total'
            '{method="BlogService.totalPosts",result="success"}'));
  });

  test('@Retryable + @Transactional commits exactly once after retries',
      () async {
    final (status, article) =
        await call('POST', '/posts/flaky', body: {'title': 'f', 'body': 'x'});
    expect(status, 201);
    expect(article['title'], 'f');

    final (_, posts) = await call('GET', '/posts');
    final flaky = (posts as List).where((p) => p['title'] == 'f');
    expect(flaky, hasLength(1),
        reason: 'each failed attempt must roll its insert back; only the '
            'successful attempt commits');
  });

  test('@CircuitBreaker opens after the threshold', () async {
    expect((await call('GET', '/posts/unstable/ping')).$1, 409);
    expect((await call('GET', '/posts/unstable/ping')).$1, 409);
    // Third call: the open circuit rejects without invoking the method —
    // CircuitOpenException surfaces as an opaque 500.
    expect((await call('GET', '/posts/unstable/ping')).$1, 500);
  });

  test('@Cacheable routes through the pluggable DianaCacheStore', () async {
    // A fresh app wired with a known store instance so the test can observe
    // that the custom store — not the built-in cache — actually intercepts.
    final store = AppCacheStore();
    final app = await buildDianaApp(
      config: config(),
      overrides: DianaOverrides(appCacheStore: store),
    );
    await app.initialize();
    await app.server.serve(quiet: true);
    final storePort = app.server.port!;
    addTearDown(() async {
      await app.server.close();
      await app.dispose();
    });

    Future<(int, dynamic)> get(String path) async {
      final client = HttpClient();
      try {
        final res = await (await client
                .getUrl(Uri.parse('http://127.0.0.1:$storePort$path')))
            .close();
        final text = await res.transform(utf8.decoder).join();
        return (res.statusCode, text.isEmpty ? null : jsonDecode(text));
      } finally {
        client.close();
      }
    }

    final (s1, first) = await get('/posts/stats/total');
    expect(s1, 200);
    expect(first['total'], 0);
    expect(store.runs, greaterThan(0),
        reason: 'the custom store must intercept the @Cacheable call');

    // Cache semantics survive through the custom store: a write is invisible
    // within the TTL because the store returns the cached value.
    final runsAfterFirst = store.runs;
    final (s2, second) = await get('/posts/stats/total');
    expect(s2, 200);
    expect(second['total'], 0, reason: 'served from the store cache');
    expect(store.runs, greaterThan(runsAfterFirst),
        reason: 'every cached call still consults the store (which decides '
            'hit vs miss)');
  });
}
