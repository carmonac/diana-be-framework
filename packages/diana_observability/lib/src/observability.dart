import 'dart:async';
import 'dart:io';

import 'package:diana/diana.dart';
import 'package:opentelemetry/api.dart' as otel;

import 'metrics/metrics.dart';
import 'tracing/tracer.dart';

/// The observability provider: a [DianaObserver] that records Prometheus
/// metrics for every observed surface and (optionally) OpenTelemetry spans.
///
/// Assemble it like the other Diana add-ons — subclass and register it as a
/// `@Component`, reading config through `@Value`:
///
/// ```dart
/// @Component()
/// class AppObservability extends DianaObservability {
///   AppObservability(
///       @Value('observability.tracing.endpoint', defaultValue: '') String ep)
///       : super(
///           tracing: ep.isEmpty
///               ? null
///               : TracingOptions(endpoint: ep, serviceName: 'my-api'),
///         );
/// }
/// ```
///
/// The generated composition root discovers it, wires it into the server,
/// scheduler, event bus and database, and serves `/actuator/metrics`.
/// Services may inject it to record their own metrics via [meters].
class DianaObservability extends DianaObserver {
  /// Registry for both the built-in series and application metrics.
  final MeterRegistry meters = MeterRegistry();

  final DianaTracer? _tracer;

  late final Counter _httpRequests = meters.counter('diana_http_requests_total',
      'Total HTTP requests.', ['method', 'route', 'status']);
  late final Histogram _httpDuration = meters.histogram(
      'diana_http_request_duration_seconds',
      'HTTP request duration.',
      ['method', 'route']);
  late final Counter _unmatched = meters.counter(
      'diana_http_unmatched_total', 'Requests that matched no route.');
  late final Counter _dbQueries = meters
      .counter('diana_db_queries_total', 'Database operations.', ['operation']);
  late final Histogram _dbDuration = meters.histogram(
      'diana_db_query_duration_seconds',
      'Database operation duration.',
      ['operation']);
  late final Counter _methodCalls = meters.counter('diana_method_calls_total',
      '@Timed method invocations.', ['method', 'result']);
  late final Histogram _methodDuration = meters.histogram(
      'diana_method_duration_seconds', '@Timed method duration.', ['method']);
  late final Counter _scheduledRuns = meters.counter(
      'diana_scheduled_runs_total', 'Scheduled task runs.', ['task', 'result']);
  late final Counter _events = meters.counter('diana_events_dispatched_total',
      'Application events dispatched.', ['type']);
  late final Gauge _rss =
      meters.gauge('diana_process_resident_memory_bytes', 'Resident set size.');

  DianaObservability({TracingOptions? tracing})
      : _tracer = tracing == null ? null : DianaTracer(tracing) {
    // Touch every family so it registers up front and appears in a scrape
    // even before the first observation.
    [
      _httpRequests,
      _httpDuration,
      _unmatched,
      _dbQueries,
      _dbDuration,
      _methodCalls,
      _methodDuration,
      _scheduledRuns,
      _events,
      _rss,
    ];
  }

  @override
  FutureOr<DianaResponse> observeHttp(HttpMethod method, String routeTemplate,
      DianaRequest request, DianaHandler next) async {
    final sw = Stopwatch()..start();
    Future<DianaResponse> run() async => await next(request);
    final tracer = _tracer;
    final response = tracer == null
        ? await run()
        : await tracer.traceRequest(
            '${method.name.toUpperCase()} $routeTemplate', request, run,
            attributes: [
                otel.Attribute.fromString('http.method', method.name),
                otel.Attribute.fromString('http.route', routeTemplate),
              ]);
    _httpRequests.inc([method.name, routeTemplate, '${response.statusCode}']);
    _httpDuration
        .observe(sw.elapsedMicroseconds / 1e6, [method.name, routeTemplate]);
    return response;
  }

  @override
  void observeUnmatched() => _unmatched.inc();

  @override
  FutureOr<T> observeQuery<T>(String operation, FutureOr<T> Function() run) {
    final sw = Stopwatch()..start();
    Future<T> measured() async {
      try {
        return await run();
      } finally {
        _dbQueries.inc([operation]);
        _dbDuration.observe(sw.elapsedMicroseconds / 1e6, [operation]);
      }
    }

    final tracer = _tracer;
    return tracer == null
        ? measured()
        : tracer.traceChild('db.$operation', measured);
  }

  @override
  FutureOr<T> observeTimedMethod<T>(String name, FutureOr<T> Function() run) {
    final sw = Stopwatch()..start();
    Future<T> measured() async {
      var success = false;
      try {
        final result = await run();
        success = true;
        return result;
      } finally {
        _methodCalls.inc([name, success ? 'success' : 'failure']);
        _methodDuration.observe(sw.elapsedMicroseconds / 1e6, [name]);
      }
    }

    final tracer = _tracer;
    return tracer == null
        ? measured()
        : tracer.traceChild('method.$name', measured);
  }

  @override
  void observeScheduledRun(String? name, Duration elapsed,
          {required bool success}) =>
      _scheduledRuns
          .inc([name ?? 'anonymous', success ? 'success' : 'failure']);

  @override
  void observeEventDispatch(String eventType, Duration elapsed) =>
      _events.inc([eventType]);

  /// Refreshes process-level gauges and renders the exposition text.
  String scrape() {
    _rss.set(ProcessInfo.currentRss.toDouble());
    return meters.scrape();
  }

  /// Flushes and shuts down the tracer, if any (call from `@PreDestroy`).
  void close() => _tracer?.close();
}

/// The `/actuator/metrics` handler: renders [observability] as Prometheus
/// text.
DianaHandler metricsEndpointHandler(DianaObservability observability) {
  return (request) => DianaResponse(
        statusCode: 200,
        bodyText: observability.scrape(),
        mimeType: 'text/plain; version=0.0.4; charset=utf-8',
      );
}
