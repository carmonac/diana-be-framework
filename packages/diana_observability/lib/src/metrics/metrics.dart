/// A minimal, dependency-free Prometheus metrics core.
///
/// Implements just enough of the client model — counters, gauges,
/// histograms, labels and the 0.0.4 text exposition format — for Diana's
/// automatic and manual metrics. The text format has been stable for years,
/// so reimplementing it avoids an ageing dependency.
library;

/// Base type for a registered metric family.
abstract class _Metric {
  final String name;
  final String help;
  final List<String> labelNames;

  _Metric(this.name, this.help, this.labelNames);

  String get _type;

  /// Emits the `# HELP`/`# TYPE` header plus every sample line.
  void _writeTo(StringBuffer out);

  void _writeHeader(StringBuffer out) {
    out.writeln('# HELP $name ${_escapeHelp(help)}');
    out.writeln('# TYPE $name $_type');
  }
}

/// A monotonically increasing counter.
class Counter extends _Metric {
  final Map<String, double> _values = {};

  Counter(super.name, super.help, [super.labelNames = const []]);

  /// Increments the series identified by [labels] (in [labelNames] order).
  void inc([List<String> labels = const [], double amount = 1]) {
    final key = _seriesKey(labelNames, labels);
    _values[key] = (_values[key] ?? 0) + amount;
  }

  @override
  String get _type => 'counter';

  @override
  void _writeTo(StringBuffer out) {
    _writeHeader(out);
    // Ensure a zero series exists even before the first increment when
    // there are no labels, so scrapers always see the metric.
    if (labelNames.isEmpty && _values.isEmpty) _values[''] = 0;
    for (final entry in _sorted(_values)) {
      out.writeln('$name${entry.key} ${_formatValue(entry.value)}');
    }
  }
}

/// A value that can go up or down.
class Gauge extends _Metric {
  final Map<String, double> _values = {};

  Gauge(super.name, super.help, [super.labelNames = const []]);

  void set(double value, [List<String> labels = const []]) =>
      _values[_seriesKey(labelNames, labels)] = value;

  @override
  String get _type => 'gauge';

  @override
  void _writeTo(StringBuffer out) {
    _writeHeader(out);
    for (final entry in _sorted(_values)) {
      out.writeln('$name${entry.key} ${_formatValue(entry.value)}');
    }
  }
}

/// A histogram of observations bucketed by upper bound.
class Histogram extends _Metric {
  /// Default buckets in seconds (Prometheus client defaults).
  static const List<double> defaultBuckets = [
    0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10,
  ];

  final List<double> buckets;
  final Map<String, List<int>> _bucketCounts = {};
  final Map<String, double> _sums = {};
  final Map<String, int> _counts = {};

  Histogram(super.name, super.help,
      [super.labelNames = const [], List<double>? buckets])
      : buckets =
            List.unmodifiable(List<double>.of(buckets ?? defaultBuckets)..sort());

  /// Records [value] (seconds) for the series identified by [labels]. Each
  /// bucket count is kept cumulative (observations `<= le`).
  void observe(double value, [List<String> labels = const []]) {
    final key = _seriesKey(labelNames, labels);
    final counts =
        _bucketCounts.putIfAbsent(key, () => List.filled(buckets.length, 0));
    for (var i = 0; i < buckets.length; i++) {
      if (value <= buckets[i]) counts[i]++;
    }
    _sums[key] = (_sums[key] ?? 0) + value;
    _counts[key] = (_counts[key] ?? 0) + 1;
  }

  @override
  String get _type => 'histogram';

  @override
  void _writeTo(StringBuffer out) {
    _writeHeader(out);
    for (final key in _counts.keys.toList()..sort()) {
      final counts = _bucketCounts[key]!;
      for (var i = 0; i < buckets.length; i++) {
        out.writeln('${name}_bucket${_withLe(key, _formatValue(buckets[i]))} '
            '${counts[i]}');
      }
      out.writeln('${name}_bucket${_withLe(key, '+Inf')} ${_counts[key]}');
      out.writeln('${name}_sum$key ${_formatValue(_sums[key]!)}');
      out.writeln('${name}_count$key ${_counts[key]}');
    }
  }

  /// Inserts a `le` label into an existing `{...}` series key.
  String _withLe(String seriesKey, String le) {
    final le0 = 'le="$le"';
    if (seriesKey.isEmpty) return '{$le0}';
    return '${seriesKey.substring(0, seriesKey.length - 1)},$le0}';
  }
}

/// Owns a set of metrics and renders them in the Prometheus text format.
class MeterRegistry {
  final List<_Metric> _metrics = [];

  Counter counter(String name, String help, [List<String> labels = const []]) {
    final m = Counter(name, help, labels);
    _metrics.add(m);
    return m;
  }

  Gauge gauge(String name, String help, [List<String> labels = const []]) {
    final m = Gauge(name, help, labels);
    _metrics.add(m);
    return m;
  }

  Histogram histogram(String name, String help,
      [List<String> labels = const [], List<double>? buckets]) {
    final m = Histogram(name, help, labels, buckets);
    _metrics.add(m);
    return m;
  }

  /// Renders every metric in the 0.0.4 text exposition format.
  String scrape() {
    final out = StringBuffer();
    for (final metric in _metrics) {
      metric._writeTo(out);
    }
    return out.toString();
  }
}

// ---- helpers ----

/// Builds the `{label="v",...}` suffix for a series (empty when no labels).
String _seriesKey(List<String> names, List<String> values) {
  if (names.isEmpty) return '';
  if (values.length != names.length) {
    throw ArgumentError(
        'Expected ${names.length} label values, got ${values.length}.');
  }
  final parts = [
    for (var i = 0; i < names.length; i++)
      '${names[i]}="${_escapeLabel(values[i])}"',
  ];
  return '{${parts.join(',')}}';
}

Iterable<MapEntry<String, double>> _sorted(Map<String, double> m) =>
    m.entries.toList()..sort((a, b) => a.key.compareTo(b.key));

String _escapeLabel(String v) =>
    v.replaceAll('\\', r'\\').replaceAll('"', r'\"').replaceAll('\n', r'\n');

String _escapeHelp(String v) =>
    v.replaceAll('\\', r'\\').replaceAll('\n', r'\n');

String _formatValue(double v) {
  if (v == v.roundToDouble() && v.abs() < 1e15) return v.toInt().toString();
  return v.toString();
}
