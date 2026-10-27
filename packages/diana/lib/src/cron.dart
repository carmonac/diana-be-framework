/// A dependency-free cron expression parser and next-fire calculator, used
/// by `@Scheduled(cron: ...)`. Six space-separated fields (Spring style):
///
/// ```
/// ┌─ second       (0-59)
/// │ ┌─ minute     (0-59)
/// │ │ ┌─ hour     (0-23)
/// │ │ │ ┌─ day-of-month (1-31)
/// │ │ │ │ ┌─ month (1-12 or JAN-DEC)
/// │ │ │ │ │ ┌─ day-of-week (0-7 or SUN-SAT; 0 and 7 are Sunday)
/// │ │ │ │ │ │
/// * * * * * *
/// ```
///
/// Each field supports `*`, a value, `a-b` ranges, `*/s` or `a-b/s` steps,
/// and `a,b,c` lists. Month and day-of-week accept three-letter names
/// (case-insensitive). Macros: `@yearly`/`@annually`, `@monthly`,
/// `@weekly`, `@daily`/`@midnight`, `@hourly`.
///
/// Expressions are evaluated in the **process's local time** (`DateTime`
/// without a UTC flag). Run the process with `TZ=UTC` (or your target zone)
/// to pin the schedule; there is no per-expression time zone.
library;

const Map<String, String> _macros = {
  '@yearly': '0 0 0 1 1 *',
  '@annually': '0 0 0 1 1 *',
  '@monthly': '0 0 0 1 * *',
  '@weekly': '0 0 0 * * 0',
  '@daily': '0 0 0 * * *',
  '@midnight': '0 0 0 * * *',
  '@hourly': '0 0 * * * *',
};

const Map<String, int> _monthNames = {
  'JAN': 1,
  'FEB': 2,
  'MAR': 3,
  'APR': 4,
  'MAY': 5,
  'JUN': 6,
  'JUL': 7,
  'AUG': 8,
  'SEP': 9,
  'OCT': 10,
  'NOV': 11,
  'DEC': 12,
};

const Map<String, int> _weekdayNames = {
  'SUN': 0,
  'MON': 1,
  'TUE': 2,
  'WED': 3,
  'THU': 4,
  'FRI': 5,
  'SAT': 6,
};

/// A parsed cron expression. Build with [CronExpression.parse]; query the
/// next fire time with [nextAfter].
class CronExpression {
  final Set<int> _seconds;
  final Set<int> _minutes;
  final Set<int> _hours;
  final Set<int> _daysOfMonth;
  final Set<int> _months;
  final Set<int> _daysOfWeek;
  final bool _domRestricted;
  final bool _dowRestricted;

  /// The normalized source expression (macros expanded).
  final String source;

  CronExpression._(
    this._seconds,
    this._minutes,
    this._hours,
    this._daysOfMonth,
    this._months,
    this._daysOfWeek, {
    required bool domRestricted,
    required bool dowRestricted,
    required this.source,
  })  : _domRestricted = domRestricted,
        _dowRestricted = dowRestricted;

  /// Parses a 6-field cron [expression] (or a macro). Throws
  /// [FormatException] with a specific message on any malformed field —
  /// callers surface it (the generator turns it into a build error).
  factory CronExpression.parse(String expression) {
    final trimmed = expression.trim();
    final expanded = _macros[trimmed.toLowerCase()] ?? trimmed;
    final fields = expanded.split(RegExp(r'\s+'));
    if (fields.length != 6) {
      throw FormatException(
          'cron expression must have 6 fields (second minute hour '
          'day-of-month month day-of-week) or be a macro like @daily; '
          'got ${fields.length} in "$expression".');
    }
    final domRestricted = fields[3] != '*' && fields[3] != '?';
    final dowRestricted = fields[5] != '*' && fields[5] != '?';
    return CronExpression._(
      _parseField(fields[0], 0, 59, 'second', null),
      _parseField(fields[1], 0, 59, 'minute', null),
      _parseField(fields[2], 0, 23, 'hour', null),
      _parseField(fields[3], 1, 31, 'day-of-month', null),
      _parseField(fields[4], 1, 12, 'month', _monthNames),
      _normalizeWeekdays(
          _parseField(fields[5], 0, 7, 'day-of-week', _weekdayNames)),
      domRestricted: domRestricted,
      dowRestricted: dowRestricted,
      source: expanded,
    );
  }

  /// The first instant strictly after [from] that matches, or `null` when
  /// none occurs within five years (an impossible expression, e.g. Feb 30).
  DateTime? nextAfter(DateTime from) {
    // Second-boundary start, one second past [from].
    var t = DateTime(from.year, from.month, from.day, from.hour, from.minute,
        from.second + 1);
    final limit = DateTime(from.year + 5);
    while (t.isBefore(limit)) {
      if (!_months.contains(t.month)) {
        t = DateTime(t.year, t.month + 1, 1); // next month at 00:00:00
        continue;
      }
      if (!_dayMatches(t)) {
        t = DateTime(t.year, t.month, t.day + 1); // next day at 00:00:00
        continue;
      }
      if (!_hours.contains(t.hour)) {
        t = DateTime(t.year, t.month, t.day, t.hour + 1);
        continue;
      }
      if (!_minutes.contains(t.minute)) {
        t = DateTime(t.year, t.month, t.day, t.hour, t.minute + 1);
        continue;
      }
      if (!_seconds.contains(t.second)) {
        t = DateTime(t.year, t.month, t.day, t.hour, t.minute, t.second + 1);
        continue;
      }
      return t;
    }
    return null;
  }

  /// Day-of-month and day-of-week combine like Vixie cron: when both are
  /// restricted a day matches if **either** does; otherwise the restricted
  /// field (if any) decides.
  bool _dayMatches(DateTime t) {
    final domOk = _daysOfMonth.contains(t.day);
    final dowOk = _daysOfWeek.contains(t.weekday % 7); // Mon..Sun 1..7 → 1..0
    if (_domRestricted && _dowRestricted) return domOk || dowOk;
    if (_domRestricted) return domOk;
    if (_dowRestricted) return dowOk;
    return true;
  }

  static Set<int> _normalizeWeekdays(Set<int> values) =>
      {for (final v in values) v == 7 ? 0 : v};

  static Set<int> _parseField(
    String field,
    int min,
    int max,
    String name,
    Map<String, int>? names,
  ) {
    if (field == '?') field = '*'; // Quartz "no specific value" ≈ any
    final result = <int>{};
    for (final part in field.split(',')) {
      _parsePart(part, min, max, name, names, result);
    }
    if (result.isEmpty) {
      throw FormatException('cron $name field "$field" matches nothing.');
    }
    return result;
  }

  static void _parsePart(
    String part,
    int min,
    int max,
    String name,
    Map<String, int>? names,
    Set<int> into,
  ) {
    var step = 1;
    var range = part;
    final slash = part.indexOf('/');
    if (slash != -1) {
      range = part.substring(0, slash);
      step = int.tryParse(part.substring(slash + 1)) ??
          (throw FormatException(
              'cron $name step "${part.substring(slash + 1)}" is not a '
              'number.'));
      if (step < 1) {
        throw FormatException('cron $name step must be >= 1; got $step.');
      }
    }

    int lo;
    int hi;
    if (range == '*') {
      lo = min;
      hi = max;
    } else {
      final dash = range.indexOf('-');
      if (dash > 0) {
        lo = _value(range.substring(0, dash), min, max, name, names);
        hi = _value(range.substring(dash + 1), min, max, name, names);
      } else {
        lo = _value(range, min, max, name, names);
        hi = slash != -1 ? max : lo; // `n/s` means n, n+s, … up to max
      }
    }
    if (lo > hi) {
      throw FormatException(
          'cron $name range "$range" is descending ($lo > $hi).');
    }
    for (var v = lo; v <= hi; v += step) {
      into.add(v);
    }
  }

  static int _value(
      String token, int min, int max, String name, Map<String, int>? names) {
    final named = names?[token.toUpperCase()];
    final value = named ?? int.tryParse(token);
    if (value == null) {
      throw FormatException('cron $name value "$token" is not valid.');
    }
    if (value < min || value > max) {
      throw FormatException(
          'cron $name value $value is out of range ($min-$max).');
    }
    return value;
  }
}
