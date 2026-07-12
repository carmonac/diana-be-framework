import 'package:meta/meta_meta.dart';

/// Runs a method on a fixed schedule (Spring: `@Scheduled`), started after
/// application initialization and stopped during graceful shutdown.
///
/// Exactly one of [fixedRate]/[fixedDelay] is required (milliseconds):
///
/// - `fixedRate`: ticks on a periodic timer; a tick is **skipped** while the
///   previous run is still in flight (no unbounded queueing).
/// - `fixedDelay`: re-arms the timer after each run completes.
///
/// The method must be a public instance method with no parameters returning
/// `void` or `Future<void>`, on a singleton provider. Cron expressions are
/// not supported yet.
@Target({TargetKind.method})
class Scheduled {
  /// Period in milliseconds (tick-based).
  final int? fixedRate;

  /// Delay in milliseconds after each completed run.
  final int? fixedDelay;

  /// Delay in milliseconds before the first run.
  final int initialDelay;

  const Scheduled({this.fixedRate, this.fixedDelay, this.initialDelay = 0});
}
