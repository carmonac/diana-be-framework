import 'package:diana/diana.dart';
import 'package:diana_observability/diana_observability.dart';
import 'package:test/test.dart';

DianaRequest req({Map<String, List<String>> headers = const {}}) =>
    DianaRequest(method: HttpMethod.get, uri: Uri.parse('/x'), headers: headers);

void main() {
  test('@Timed hook records duration and result labels', () async {
    final obs = DianaObservability();
    addTearDown(obs.close);

    expect(obs.scrape(), contains('diana_method_calls_total'),
        reason: 'series registered before the first observation');
    expect(obs.scrape(), contains('diana_method_duration_seconds'));

    expect(await obs.observeTimedMethod('Svc.ok', () async => 42), 42);
    await expectLater(
      Future.sync(() =>
          obs.observeTimedMethod<void>('Svc.bad', () async {
            throw StateError('boom');
          })),
      throwsStateError,
    );

    final text = obs.scrape();
    expect(
        text,
        contains(
            'diana_method_calls_total{method="Svc.ok",result="success"} 1'));
    expect(
        text,
        contains(
            'diana_method_calls_total{method="Svc.bad",result="failure"} 1'));
    expect(text, contains('diana_method_duration_seconds_count{method="Svc.ok"} 1'));
  });

  test('HTTP observation records a labelled counter and duration', () async {
    final obs = DianaObservability();
    await obs.observeHttp(HttpMethod.get, '/todos/:id', req(),
        (r) async => const DianaResponse.text('ok'));
    final out = obs.scrape();
    expect(
      out,
      contains(
          'diana_http_requests_total{method="get",route="/todos/:id",status="200"} 1'),
    );
    expect(out, contains('diana_http_request_duration_seconds_count'));
  });

  test('unmatched, db, scheduled and event series accumulate', () async {
    final obs = DianaObservability();
    obs.observeUnmatched();
    await obs.observeQuery('select', () async => 1);
    obs.observeScheduledRun('Job.beat', Duration.zero, success: true);
    obs.observeScheduledRun('Job.beat', Duration.zero, success: false);
    obs.observeEventDispatch('OrderCreated', Duration.zero);
    final out = obs.scrape();
    expect(out, contains('diana_http_unmatched_total 1'));
    expect(out, contains('diana_db_queries_total{operation="select"} 1'));
    expect(out,
        contains('diana_scheduled_runs_total{task="Job.beat",result="success"} 1'));
    expect(out,
        contains('diana_scheduled_runs_total{task="Job.beat",result="failure"} 1'));
    expect(out,
        contains('diana_events_dispatched_total{type="OrderCreated"} 1'));
    expect(out, contains('diana_process_resident_memory_bytes'));
  });

  test('metricsEndpointHandler serves the 0.0.4 text format', () async {
    final obs = DianaObservability();
    final res = await metricsEndpointHandler(obs)(req());
    expect(res.statusCode, 200);
    expect(res.mimeType, contains('version=0.0.4'));
    expect(res.bodyText, contains('# TYPE diana_http_requests_total counter'));
  });

  group('tracing (console exporter, no collector)', () {
    test('a traced request and nested db query complete without error',
        () async {
      final obs =
          DianaObservability(tracing: const TracingOptions(serviceName: 't'));
      addTearDown(obs.close);
      // A request span with a nested DB span; the otel Zone must coexist
      // with Diana's own transaction Zone key without interference.
      final res = await obs.observeHttp(
        HttpMethod.get,
        '/orders/:id',
        req(headers: {
          'traceparent': [
            '00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01'
          ],
        }),
        (r) async {
          await obs.observeQuery('select', () async => const <int>[]);
          return const DianaResponse.text('ok');
        },
      );
      expect(res.statusCode, 200);
      expect(obs.scrape(),
          contains('diana_db_queries_total{operation="select"} 1'));
    });
  });
}
