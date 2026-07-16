import 'package:diana_observability/diana_observability.dart';
import 'package:test/test.dart';

void main() {
  test('counter renders type/help and a labelled series', () {
    final reg = MeterRegistry();
    final c = reg.counter('http_requests_total', 'Total requests.', ['route']);
    c.inc(['/a']);
    c.inc(['/a']);
    c.inc(['/b'], 3);
    expect(reg.scrape(), '''
# HELP http_requests_total Total requests.
# TYPE http_requests_total counter
http_requests_total{route="/a"} 2
http_requests_total{route="/b"} 3
''');
  });

  test('unlabelled counter always exposes a zero series', () {
    final reg = MeterRegistry();
    reg.counter('boots_total', 'Boots.');
    expect(reg.scrape(), contains('boots_total 0\n'));
  });

  test('gauge renders the latest value', () {
    final reg = MeterRegistry();
    reg.gauge('temp', 'Temperature.')..set(21.5)..set(19);
    expect(reg.scrape(), contains('temp 19\n'));
  });

  test('histogram renders cumulative buckets, +Inf, sum and count', () {
    final reg = MeterRegistry();
    final h = reg.histogram('lat', 'Latency.', const [], [0.1, 0.5, 1.0]);
    h.observe(0.05);
    h.observe(0.3);
    h.observe(2.0);
    final out = reg.scrape();
    expect(out, contains('lat_bucket{le="0.1"} 1'));
    expect(out, contains('lat_bucket{le="0.5"} 2'));
    expect(out, contains('lat_bucket{le="1"} 2'));
    expect(out, contains('lat_bucket{le="+Inf"} 3'));
    expect(out, contains('lat_sum 2.35'));
    expect(out, contains('lat_count 3'));
  });

  test('label values are escaped', () {
    final reg = MeterRegistry();
    reg.counter('m', 'help', ['path']).inc([r'a"b\c']);
    expect(reg.scrape(), contains(r'm{path="a\"b\\c"} 1'));
  });

  test('mismatched label count throws', () {
    final c = MeterRegistry().counter('m', 'h', ['a', 'b']);
    expect(() => c.inc(['only-one']), throwsArgumentError);
  });
}
