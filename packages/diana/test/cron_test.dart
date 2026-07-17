import 'package:diana/diana.dart';
import 'package:test/test.dart';

/// A local-time DateTime the same way CronExpression evaluates.
DateTime at(int y, int mo, int d, [int h = 0, int mi = 0, int s = 0]) =>
    DateTime(y, mo, d, h, mi, s);

void main() {
  group('CronExpression.parse — valid', () {
    test('every-second wildcard fires one second later', () {
      final cron = CronExpression.parse('* * * * * *');
      expect(cron.nextAfter(at(2026, 1, 1, 0, 0, 0)), at(2026, 1, 1, 0, 0, 1));
    });

    test('a specific time of day', () {
      final cron = CronExpression.parse('0 30 9 * * *');
      expect(cron.nextAfter(at(2026, 3, 10, 8, 0, 0)),
          at(2026, 3, 10, 9, 30, 0));
      // Already past today → tomorrow.
      expect(cron.nextAfter(at(2026, 3, 10, 10, 0, 0)),
          at(2026, 3, 11, 9, 30, 0));
    });

    test('step values', () {
      final cron = CronExpression.parse('0 */15 * * * *');
      expect(cron.nextAfter(at(2026, 1, 1, 0, 0, 0)), at(2026, 1, 1, 0, 15, 0));
      expect(cron.nextAfter(at(2026, 1, 1, 0, 50, 0)), at(2026, 1, 1, 1, 0, 0));
    });

    test('ranges and lists', () {
      final cron = CronExpression.parse('0 0 9-17 * * *');
      expect(cron.nextAfter(at(2026, 1, 1, 18, 0, 0)),
          at(2026, 1, 2, 9, 0, 0));
      final list = CronExpression.parse('0 0 0 1,15 * *');
      expect(list.nextAfter(at(2026, 1, 2)), at(2026, 1, 15));
      expect(list.nextAfter(at(2026, 1, 20)), at(2026, 2, 1));
    });

    test('month and weekday names', () {
      final cron = CronExpression.parse('0 0 0 * JAN-FEB *');
      expect(cron.nextAfter(at(2026, 3, 1)), at(2027, 1, 1));
      // Weekday name: next Monday 08:00.
      final mon = CronExpression.parse('0 0 8 * * MON');
      // 2026-01-01 is a Thursday; next Monday is 2026-01-05.
      expect(mon.nextAfter(at(2026, 1, 1, 12, 0, 0)), at(2026, 1, 5, 8, 0, 0));
    });

    test('Sunday is both 0 and 7', () {
      final zero = CronExpression.parse('0 0 0 * * 0');
      final seven = CronExpression.parse('0 0 0 * * 7');
      final from = at(2026, 1, 1); // Thursday
      // 2026-01-04 is the first Sunday.
      expect(zero.nextAfter(from), at(2026, 1, 4));
      expect(seven.nextAfter(from), zero.nextAfter(from));
    });

    test('day-of-month OR day-of-week when both restricted', () {
      // The 15th OR any Monday.
      final cron = CronExpression.parse('0 0 0 15 * MON');
      // 2026-01-01 Thu → next Monday 2026-01-05 comes before the 15th.
      expect(cron.nextAfter(at(2026, 1, 1)), at(2026, 1, 5));
      // From the 6th, the 15th comes before the next Monday (the 12th)? No —
      // 2026-01-12 is a Monday, before the 15th.
      expect(cron.nextAfter(at(2026, 1, 6)), at(2026, 1, 12));
    });

    test('macros expand', () {
      expect(CronExpression.parse('@daily').source, '0 0 0 * * *');
      expect(CronExpression.parse('@hourly').source, '0 0 * * * *');
      expect(CronExpression.parse('@weekly').source, '0 0 0 * * 0');
      expect(CronExpression.parse('@YEARLY').source, '0 0 0 1 1 *');
    });

    test('rolls over year boundaries', () {
      final cron = CronExpression.parse('0 0 0 1 1 *'); // Jan 1, midnight
      expect(cron.nextAfter(at(2026, 6, 1)), at(2027, 1, 1));
    });

    test('impossible expression (Feb 30) yields null', () {
      final cron = CronExpression.parse('0 0 0 30 2 *');
      expect(cron.nextAfter(at(2026, 1, 1)), isNull);
    });
  });

  group('CronExpression.parse — invalid', () {
    void expectError(String expr, Object messageMatch) {
      expect(
        () => CronExpression.parse(expr),
        throwsA(isA<FormatException>()
            .having((e) => e.message, 'message', messageMatch)),
      );
    }

    test('wrong field count', () {
      expectError('* * * * *', contains('must have 6 fields'));
      expectError('0 0 0 0 0 0 0', contains('must have 6 fields'));
    });

    test('out-of-range values', () {
      expectError('60 0 0 * * *', contains('second value 60 is out of range'));
      expectError('0 0 24 * * *', contains('hour value 24 is out of range'));
      expectError('0 0 0 32 * *',
          contains('day-of-month value 32 is out of range'));
      expectError('0 0 0 * 13 *', contains('month value 13 is out of range'));
      expectError(
          '0 0 0 * * 8', contains('day-of-week value 8 is out of range'));
    });

    test('non-numeric and bad steps', () {
      expectError('x * * * * *', contains('second value "x" is not valid'));
      expectError('0 0 0 * * MOO',
          contains('day-of-week value "MOO" is not valid'));
      expectError('*/0 * * * * *', contains('step must be >= 1'));
      expectError('0 5-3 * * * *', contains('descending'));
    });
  });
}
