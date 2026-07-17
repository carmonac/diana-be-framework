/// Runtime for `@Scheduled` tasks: generated code registers tasks, the
/// application lifecycle starts and stops them.
library;

import 'dart:async';

import 'cron.dart';
import 'observer.dart';
import 'runtime.dart';

/// Schedules and runs recurring tasks.
///
/// `fixedRateMs` tasks tick on a periodic timer and **skip a tick** while
/// the previous run is still in flight; `fixedDelayMs` tasks re-arm after
/// each run completes. Task errors go to [onError] (default: printed) and
/// never stop the schedule.
///
/// **Multi-isolate semantics**: tasks run once per process — [start] skips
/// them in worker isolates ([DianaRuntime.isWorkerIsolate]) so a schedule
/// never multiplies with `server.isolates`. A task registered with
/// `perIsolate: true` opts out and runs in every isolate (e.g. refreshing
/// an isolate-local cache). Single-isolate serving and embedded use
/// (calling `initialize()` yourself) are unaffected.
class DianaScheduler {
  final void Function(Object error, StackTrace stackTrace) onError;

  /// Observes each task run (duration, success). `null` costs nothing.
  final DianaObserver? observer;

  final List<_Task> _tasks = [];
  var _started = false;
  var _stopped = false;

  DianaScheduler({
    void Function(Object error, StackTrace stackTrace)? onError,
    this.observer,
  }) : onError = onError ?? _defaultOnError;

  /// Registers a task. Call before [start]; provide exactly one of
  /// [fixedRateMs]/[fixedDelayMs]/[cron]. A [cron] task fires at each
  /// expression match (next occurrence computed after the previous run
  /// completes, so runs never overlap); [initialDelayMs] is ignored for it.
  /// [perIsolate] tasks run in every isolate; by default a task runs only
  /// in the main isolate. [name] (`Class.method`) labels observability
  /// metrics.
  void schedule({
    required Future<void> Function() task,
    int? fixedRateMs,
    int? fixedDelayMs,
    String? cron,
    int initialDelayMs = 0,
    bool perIsolate = false,
    String? name,
  }) {
    final provided =
        [fixedRateMs, fixedDelayMs, cron].where((v) => v != null).length;
    if (provided != 1) {
      throw ArgumentError(
          'Provide exactly one of fixedRateMs, fixedDelayMs or cron.');
    }
    _tasks.add(_Task(
      task,
      fixedRateMs,
      fixedDelayMs,
      initialDelayMs,
      cron: cron == null ? null : CronExpression.parse(cron),
      perIsolate: perIsolate,
      name: name,
    ));
  }

  /// Starts every registered task (leader-only tasks are skipped in worker
  /// isolates).
  void start() {
    if (_started) return;
    _started = true;
    for (final task in _tasks) {
      if (!task.perIsolate && DianaRuntime.isWorkerIsolate) continue;
      if (task.cron != null) {
        _scheduleCron(task); // absolute schedule; initialDelay does not apply
        continue;
      }
      // Each task owns exactly one live timer slot; re-arms REPLACE it (a
      // grow-only timer list would leak one Timer per fixedDelay run).
      task.timer = Timer(Duration(milliseconds: task.initialDelayMs), () {
        if (_stopped) return;
        if (task.fixedRateMs != null) {
          _runGuarded(task); // first tick fires at initialDelay
          task.timer = Timer.periodic(
            Duration(milliseconds: task.fixedRateMs!),
            (_) => _runGuarded(task),
          );
        } else {
          _runFixedDelay(task);
        }
      });
    }
  }

  /// Cancels all timers and waits for in-flight runs to finish.
  Future<void> stop() async {
    _stopped = true;
    for (final task in _tasks) {
      task.timer?.cancel();
    }
    await Future.wait([
      for (final task in _tasks)
        if (task.inFlight != null) task.inFlight!,
    ]);
  }

  /// Runs [task], reporting duration and success/failure to [observer].
  /// `Future.sync`: a task that throws before returning its future must land
  /// in the schedule's error path, not escape the timer callback (which
  /// would kill the isolate).
  Future<void> _measuredRun(_Task task) {
    if (observer == null) return Future.sync(task.run);
    final sw = Stopwatch()..start();
    return Future.sync(task.run).then(
      (_) => observer!.observeScheduledRun(task.name, sw.elapsed, success: true),
      onError: (Object e, StackTrace st) {
        observer!.observeScheduledRun(task.name, sw.elapsed, success: false);
        Error.throwWithStackTrace(e, st);
      },
    );
  }

  void _runGuarded(_Task task) {
    if (_stopped || task.inFlight != null) return; // skip overlapping tick
    task.inFlight = _measuredRun(task).catchError((Object e, StackTrace st) {
      onError(e, st);
    }).whenComplete(() => task.inFlight = null);
  }

  void _runFixedDelay(_Task task) {
    if (_stopped) return;
    task.inFlight = _measuredRun(task).catchError((Object e, StackTrace st) {
      onError(e, st);
    }).whenComplete(() {
      task.inFlight = null;
      if (_stopped) return;
      task.timer = Timer(
        Duration(milliseconds: task.fixedDelayMs!),
        () => _runFixedDelay(task),
      );
    });
  }

  /// Arms the one-shot timer for a cron task's next occurrence; on fire it
  /// runs the task and re-arms from the completion time (so a slow run
  /// never overlaps the next, matching Spring's single-threaded cron).
  void _scheduleCron(_Task task) {
    if (_stopped) return;
    final now = DateTime.now();
    final next = task.cron!.nextAfter(now);
    if (next == null) return; // impossible expression: never fires
    final delay = next.difference(now);
    task.timer = Timer(delay.isNegative ? Duration.zero : delay, () {
      if (_stopped) return;
      task.inFlight = _measuredRun(task).catchError((Object e, StackTrace st) {
        onError(e, st);
      }).whenComplete(() {
        task.inFlight = null;
        if (_stopped) return;
        _scheduleCron(task);
      });
    });
  }

  static void _defaultOnError(Object error, StackTrace stackTrace) {
    // ignore: avoid_print
    print('[diana] Scheduled task failed: $error\n$stackTrace');
  }
}

class _Task {
  final Future<void> Function() run;
  final int? fixedRateMs;
  final int? fixedDelayMs;
  final int initialDelayMs;
  final CronExpression? cron;
  final bool perIsolate;
  final String? name;
  Future<void>? inFlight;

  /// The single live timer for this task (initial delay, then the periodic
  /// or re-armed one).
  Timer? timer;

  _Task(this.run, this.fixedRateMs, this.fixedDelayMs, this.initialDelayMs,
      {this.cron, required this.perIsolate, this.name});
}
