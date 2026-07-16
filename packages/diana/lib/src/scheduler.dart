/// Runtime for `@Scheduled` tasks: generated code registers tasks, the
/// application lifecycle starts and stops them.
library;

import 'dart:async';

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

  final List<_Task> _tasks = [];
  final List<Timer> _timers = [];
  var _started = false;
  var _stopped = false;

  DianaScheduler({
    void Function(Object error, StackTrace stackTrace)? onError,
  }) : onError = onError ?? _defaultOnError;

  /// Registers a task. Call before [start]; exactly one of
  /// [fixedRateMs]/[fixedDelayMs] must be provided. [perIsolate] tasks run
  /// in every isolate; by default a task runs only in the main isolate.
  void schedule({
    required Future<void> Function() task,
    int? fixedRateMs,
    int? fixedDelayMs,
    int initialDelayMs = 0,
    bool perIsolate = false,
  }) {
    if ((fixedRateMs == null) == (fixedDelayMs == null)) {
      throw ArgumentError(
          'Provide exactly one of fixedRateMs or fixedDelayMs.');
    }
    _tasks.add(_Task(task, fixedRateMs, fixedDelayMs, initialDelayMs,
        perIsolate: perIsolate));
  }

  /// Starts every registered task (leader-only tasks are skipped in worker
  /// isolates).
  void start() {
    if (_started) return;
    _started = true;
    for (final task in _tasks) {
      if (!task.perIsolate && DianaRuntime.isWorkerIsolate) continue;
      _timers.add(Timer(Duration(milliseconds: task.initialDelayMs), () {
        if (_stopped) return;
        if (task.fixedRateMs != null) {
          _runGuarded(task); // first tick fires at initialDelay
          _timers.add(Timer.periodic(
            Duration(milliseconds: task.fixedRateMs!),
            (_) => _runGuarded(task),
          ));
        } else {
          _runFixedDelay(task);
        }
      }));
    }
  }

  /// Cancels all timers and waits for in-flight runs to finish.
  Future<void> stop() async {
    _stopped = true;
    for (final timer in _timers) {
      timer.cancel();
    }
    await Future.wait([
      for (final task in _tasks)
        if (task.inFlight != null) task.inFlight!,
    ]);
  }

  void _runGuarded(_Task task) {
    if (_stopped || task.inFlight != null) return; // skip overlapping tick
    task.inFlight = task.run().catchError((Object e, StackTrace st) {
      onError(e, st);
    }).whenComplete(() => task.inFlight = null);
  }

  void _runFixedDelay(_Task task) {
    if (_stopped) return;
    task.inFlight = task.run().catchError((Object e, StackTrace st) {
      onError(e, st);
    }).whenComplete(() {
      task.inFlight = null;
      if (_stopped) return;
      _timers.add(Timer(
        Duration(milliseconds: task.fixedDelayMs!),
        () => _runFixedDelay(task),
      ));
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
  final bool perIsolate;
  Future<void>? inFlight;

  _Task(this.run, this.fixedRateMs, this.fixedDelayMs, this.initialDelayMs,
      {required this.perIsolate});
}
