import 'dart:async';
import 'dart:io';

import 'package:diana/diana.dart';
import 'package:test/test.dart';

/// Records every observation the runtime reports.
class RecordingObserver extends DianaObserver {
  final List<(String method, String route, int status)> http = [];
  var unmatched = 0;
  final List<(String op, Duration d)> queries = [];
  final List<(String? name, bool success)> scheduled = [];
  final List<String> events = [];

  @override
  FutureOr<DianaResponse> observeHttp(HttpMethod method, String routeTemplate,
      DianaRequest request, DianaHandler next) async {
    final res = await next(request);
    http.add((method.name, routeTemplate, res.statusCode));
    return res;
  }

  @override
  void observeUnmatched() => unmatched++;

  @override
  FutureOr<T> observeQuery<T>(String operation, FutureOr<T> Function() run) {
    queries.add((operation, Duration.zero));
    return run();
  }

  @override
  void observeScheduledRun(String? name, Duration elapsed,
          {required bool success}) =>
      scheduled.add((name, success));

  @override
  void observeEventDispatch(String eventType, Duration elapsed) =>
      events.add(eventType);
}

Future<int> statusOf(int port, String path, {String method = 'GET'}) async {
  final client = HttpClient();
  try {
    final req =
        await client.openUrl(method, Uri.parse('http://127.0.0.1:$port$path'));
    final res = await req.close();
    await res.drain<void>();
    return res.statusCode;
  } finally {
    client.close();
  }
}

void main() {
  group('HTTP observation', () {
    late RecordingObserver obs;
    late DianaServer server;

    setUp(() => obs = RecordingObserver());
    tearDown(() => server.close());

    test('reports method, route template and final status', () async {
      server = DianaServer(observer: obs)
        ..register(HttpMethod.get, '/todos/:id',
            (req) => const DianaResponse.text('ok'));
      await server.serve(port: 0);
      await statusOf(server.port!, '/todos/42');
      expect(obs.http, [('get', '/todos/:id', 200)]);
    });

    test('sees error-boundary status (500), not an exception', () async {
      server = DianaServer(observer: obs, onUnhandled: (_, __) {})
        ..register(
            HttpMethod.get, '/boom', (req) => throw StateError('kaboom'));
      await server.serve(port: 0);
      final status = await statusOf(server.port!, '/boom');
      expect(status, 500);
      expect(obs.http, [('get', '/boom', 500)]);
    });

    test('counts unmatched (404) requests', () async {
      server = DianaServer(observer: obs);
      await server.serve(port: 0);
      await statusOf(server.port!, '/nope');
      expect(obs.unmatched, 1);
      expect(obs.http, isEmpty);
    });

    test('a null observer adds no wrapping', () async {
      server = DianaServer()
        ..register(
            HttpMethod.get, '/x', (req) => const DianaResponse.text('x'));
      await server.serve(port: 0);
      expect(await statusOf(server.port!, '/x'), 200);
    });
  });

  test('liveness is a trivial UP; readiness aggregates indicators', () async {
    final liveness = livenessEndpointHandler();
    final live = await liveness(DianaRequest(
        method: HttpMethod.get, uri: Uri.parse('/actuator/health/liveness')));
    expect(live.statusCode, 200);

    final readiness = readinessEndpointHandler([_DownIndicator()]);
    final ready = await readiness(DianaRequest(
        method: HttpMethod.get, uri: Uri.parse('/actuator/health/readiness')));
    expect(ready.statusCode, 503);
  });

  group('scheduler observation', () {
    test('reports run name, duration and success/failure', () async {
      final obs = RecordingObserver();
      final scheduler = DianaScheduler(observer: obs, onError: (_, __) {})
        ..schedule(task: () async {}, fixedDelayMs: 10, name: 'Job.ok')
        ..schedule(
            task: () async => throw StateError('x'),
            fixedRateMs: 10,
            name: 'Job.fail')
        ..start();
      await Future<void>.delayed(const Duration(milliseconds: 40));
      await scheduler.stop();
      expect(obs.scheduled, contains(('Job.ok', true)));
      expect(obs.scheduled, contains(('Job.fail', false)));
    });

    test('a failed run keeps the original stack trace for onError', () async {
      final trace = StackTrace.fromString('the-original-frame');
      StackTrace? seen;
      final scheduler = DianaScheduler(
          observer: RecordingObserver(), onError: (_, st) => seen = st)
        ..schedule(
            task: () async => Error.throwWithStackTrace(StateError('x'), trace),
            fixedDelayMs: 5,
            name: 'Job.fail')
        ..start();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await scheduler.stop();
      expect('$seen', contains('the-original-frame'));
    });
  });

  test('event bus reports dispatch by runtime type', () async {
    final obs = RecordingObserver();
    final bus = DianaEventBus(observer: obs)..on<String>((e) {});
    await bus.publish('hello');
    expect(obs.events, ['String']);
  });

  test('event bus reports a dispatch whose listener throws', () async {
    final obs = RecordingObserver();
    final bus = DianaEventBus(observer: obs)
      ..on<String>((e) => throw StateError('listener'));
    await expectLater(bus.publish('hello'), throwsStateError);
    expect(obs.events, ['String']);
  });
}

class _DownIndicator implements HealthIndicator {
  @override
  String get name => 'db';
  @override
  Future<HealthStatus> health() async => const HealthStatus.down();
}
