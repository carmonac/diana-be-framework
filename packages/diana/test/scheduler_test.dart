import 'dart:async';

import 'package:diana/diana.dart';
import 'package:test/test.dart';

void main() {
  test('fixedRate skips ticks while a run is in flight', () async {
    var runs = 0;
    final scheduler = DianaScheduler()
      ..schedule(
        task: () async {
          runs++;
          await Future<void>.delayed(const Duration(milliseconds: 120));
        },
        fixedRateMs: 40,
      )
      ..start();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await scheduler.stop();
    // ~7 ticks elapsed but overlapping runs were skipped.
    expect(runs, inInclusiveRange(2, 4));
  });

  test('a task that throws synchronously lands in onError, not the zone',
      () async {
    final errors = <Object>[];
    var laterRuns = 0;
    Future<void> syncBoom() {
      throw StateError('sync throw'); // before returning any future
    }

    final scheduler = DianaScheduler(onError: (e, st) => errors.add(e))
      ..schedule(task: syncBoom, fixedDelayMs: 20)
      ..schedule(task: () async => laterRuns++, fixedDelayMs: 20)
      ..start();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await scheduler.stop();

    expect(errors, isNotEmpty,
        reason: 'a synchronous throw must reach onError — escaping the '
            'timer callback would kill the isolate');
    expect(laterRuns, greaterThan(0));
  });

  test('errors are reported and do not stop the schedule', () async {
    final errors = <Object>[];
    var runs = 0;
    final scheduler = DianaScheduler(onError: (e, st) => errors.add(e))
      ..schedule(
        task: () async {
          runs++;
          throw StateError('boom');
        },
        fixedDelayMs: 30,
      )
      ..start();
    await Future<void>.delayed(const Duration(milliseconds: 150));
    await scheduler.stop();
    expect(runs, greaterThanOrEqualTo(2));
    expect(errors, isNotEmpty);
    expect(errors.first, isA<StateError>());
  });

  test('stop awaits the in-flight run', () async {
    final completer = Completer<void>();
    var finished = false;
    final scheduler = DianaScheduler()
      ..schedule(
        task: () async {
          await completer.future;
          finished = true;
        },
        fixedDelayMs: 10,
      )
      ..start();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final stopping = scheduler.stop();
    completer.complete();
    await stopping;
    expect(finished, isTrue);
  });

  test('leader-only tasks do not start in a worker isolate', () async {
    DianaRuntime.isWorkerIsolate = true;
    addTearDown(() => DianaRuntime.isWorkerIsolate = false);

    var leaderRuns = 0;
    final scheduler = DianaScheduler()
      ..schedule(
        task: () async => leaderRuns++,
        fixedDelayMs: 10,
      )
      ..start();
    await Future<void>.delayed(const Duration(milliseconds: 60));
    await scheduler.stop();
    expect(leaderRuns, 0,
        reason: 'default (leader-only) tasks must not run in workers');
  });

  test('perIsolate tasks run in worker isolates', () async {
    DianaRuntime.isWorkerIsolate = true;
    addTearDown(() => DianaRuntime.isWorkerIsolate = false);

    var runs = 0;
    final scheduler = DianaScheduler()
      ..schedule(
        task: () async => runs++,
        fixedDelayMs: 10,
        perIsolate: true,
      )
      ..start();
    await Future<void>.delayed(const Duration(milliseconds: 60));
    await scheduler.stop();
    expect(runs, greaterThan(0));
  });
}
