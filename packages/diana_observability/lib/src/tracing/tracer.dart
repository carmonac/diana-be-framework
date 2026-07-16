/// OpenTelemetry tracing wiring — the only file importing `package:opentelemetry`.
///
/// paso-0 findings (opentelemetry 0.18.11): the global `trace` helper handles
/// span start, Context attach via a forked Zone, `setStatus`/`recordException`
/// on throw and `span.end()` in a finally — so callers just wrap their work.
/// Child spans call `trace` again and inherit `Context.current` automatically.
/// This Zone usage is independent of Diana's own `#dianaDataTx` Zone key
/// (different keys nest cleanly). `trace` is marked experimental upstream; it
/// is the intended public entry point, so the file opts out of that lint.
library;

// ignore_for_file: experimental_member_use

import 'package:diana/diana.dart' show DianaRequest;
import 'package:opentelemetry/api.dart' as otel;
import 'package:opentelemetry/sdk.dart' as otel_sdk;

/// How tracing exports spans. When [endpoint] is set, spans go to an OTLP
/// collector; otherwise they print via the console exporter (useful for
/// local development and tests without a collector).
class TracingOptions {
  final String? endpoint;
  final String serviceName;

  const TracingOptions({this.endpoint, this.serviceName = 'diana'});
}

/// Creates spans for requests and database operations, exporting via OTLP or
/// the console. Registered globally so the `trace<T>` helper resolves it.
class DianaTracer {
  final otel.W3CTraceContextPropagator _propagator =
      otel.W3CTraceContextPropagator();
  final otel_sdk.TracerProviderBase _provider;

  DianaTracer(TracingOptions options)
      : _provider = otel_sdk.TracerProviderBase(
          processors: [
            otel_sdk.BatchSpanProcessor(
              options.endpoint != null
                  ? otel_sdk.CollectorExporter(Uri.parse(options.endpoint!))
                  : otel_sdk.ConsoleExporter(),
            ),
          ],
          resource: otel_sdk.Resource([
            otel.Attribute.fromString('service.name', options.serviceName),
          ]),
        ) {
    otel.registerGlobalTracerProvider(_provider);
    otel.registerGlobalTextMapPropagator(_propagator);
  }

  /// Runs [fn] in a server span named [name], continuing any trace carried by
  /// the request's `traceparent` header.
  Future<T> traceRequest<T>(
    String name,
    DianaRequest request,
    Future<T> Function() fn, {
    List<otel.Attribute> attributes = const [],
  }) {
    final parent =
        _propagator.extract(otel.Context.root, request, const _HeaderGetter());
    return otel.trace(name, fn,
        context: parent,
        spanKind: otel.SpanKind.server,
        spanAttributes: attributes);
  }

  /// Runs [fn] in a child span of the current context (e.g. a DB query).
  Future<T> traceChild<T>(String name, Future<T> Function() fn) =>
      otel.trace(name, fn, spanKind: otel.SpanKind.client);

  /// Flushes and shuts the exporters down (graceful shutdown).
  void close() => _provider.shutdown();
}

/// Reads `traceparent`/`tracestate` from a [DianaRequest]'s headers.
class _HeaderGetter implements otel.TextMapGetter<DianaRequest> {
  const _HeaderGetter();

  @override
  String? get(DianaRequest carrier, String key) => carrier.header(key);

  @override
  Iterable<String> keys(DianaRequest carrier) =>
      const ['traceparent', 'tracestate'];
}
