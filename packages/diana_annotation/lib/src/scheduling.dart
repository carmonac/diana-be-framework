import 'package:meta/meta_meta.dart';

/// Runs a method on a fixed schedule (Spring: `@Scheduled`), started after
/// application initialization and stopped during graceful shutdown.
///
/// Exactly one of [fixedRate]/[fixedDelay]/[cron] is required:
///
/// - `fixedRate` (ms): ticks on a periodic timer; a tick is **skipped**
///   while the previous run is still in flight (no unbounded queueing).
/// - `fixedDelay` (ms): re-arms the timer after each run completes.
/// - `cron`: a 6-field cron expression (`second minute hour day-of-month
///   month day-of-week`, Spring style) or a macro (`@daily`, `@hourly`, …).
///   Fires at each match; the next occurrence is computed after the
///   previous run completes, so runs never overlap. Evaluated in the
///   process's local time — run with `TZ=UTC` to pin the schedule.
///   `initialDelay` does not apply to a cron task.
///
/// The method must be a public instance method with no parameters returning
/// `void` or `Future<void>`, on a singleton provider.
@Target({TargetKind.method})
class Scheduled {
  /// Period in milliseconds (tick-based).
  final int? fixedRate;

  /// Delay in milliseconds after each completed run.
  final int? fixedDelay;

  /// A 6-field cron expression or a macro (`@daily`, `@hourly`, …).
  final String? cron;

  /// Delay in milliseconds before the first run (ignored for `cron`).
  final int initialDelay;

  /// Run this task in **every** isolate when serving with
  /// `server.isolates > 1` (e.g. to refresh an isolate-local cache). By
  /// default a task runs only in the main isolate — once per process.
  final bool perIsolate;

  const Scheduled({
    this.fixedRate,
    this.fixedDelay,
    this.cron,
    this.initialDelay = 0,
    this.perIsolate = false,
  });
}
