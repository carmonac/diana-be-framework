import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:meta/meta.dart';

import 'events.dart';
import 'server.dart';

/// What the generated bootstrap hands to [DianaRuntime.run]: the server plus
/// the application lifecycle callbacks (and the event bus, when the app
/// declares `@EventListener` methods or injects `DianaEventPublisher`).
class DianaRunnable {
  final DianaServer server;
  final Future<void> Function() initialize;
  final Future<void> Function() dispose;
  final DianaEventBus? eventBus;

  DianaRunnable({
    required this.server,
    required this.initialize,
    required this.dispose,
    this.eventBus,
  });
}

/// Runs a Diana application with lifecycle and graceful shutdown:
/// bootstrap → `initialize()` (`@PostConstruct` in dependency order) →
/// `serve()` → wait for SIGINT/SIGTERM → `close()` (drains in-flight
/// requests) → `dispose()` (`@PreDestroy` in reverse order).
class DianaRuntime {
  static bool _isWorker = false;

  /// Whether this isolate is a Diana worker (spawned by multi-isolate
  /// serving). Dart statics are per-isolate, so this is `false` on the main
  /// isolate and in embedded/single-isolate use. `DianaScheduler` consults
  /// it to run leader-only `@Scheduled` tasks once per process.
  static bool get isWorkerIsolate => _isWorker;

  @visibleForTesting
  static set isWorkerIsolate(bool value) => _isWorker = value;

  /// How long shutdown waits for each worker isolate to close and dispose
  /// before killing it (a worker whose `@PreDestroy` hangs must not hang
  /// the whole process).
  static Duration workerShutdownTimeout = const Duration(seconds: 15);

  /// Runs [bootstrap] until shutdown is requested.
  ///
  /// Shutdown triggers: SIGINT/SIGTERM (unless [installSignalHandlers] is
  /// false; SIGTERM is skipped on Windows) or the completion of
  /// [shutdownTrigger] (the programmatic hook used by tests and embeddings).
  ///
  /// **Multi-isolate serving (experimental).** When [isolates] (or the
  /// `server.isolates` config key) is greater than 1, `n - 1` worker
  /// isolates are spawned, each running the full [bootstrap] — its own
  /// context, its own `initialize()` — and binding the same port with
  /// shared sockets. Everything captured by [bootstrap] must therefore be
  /// sendable across isolates (the generated bootstrap captures only
  /// `DianaConfig` and const overrides; live `DianaOverrides` instances are
  /// generally not sendable). The main isolate owns the signal handlers and
  /// coordinates worker shutdown.
  ///
  /// When the runnable carries an event bus, broadcast events are bridged
  /// hub-and-spoke: a worker's broadcast goes to the main isolate, which
  /// dispatches it locally and relays it to every other worker.
  ///
  /// Startup is coordinated and fail-closed: workers bootstrap and
  /// `initialize()` when spawned but only start accepting connections after
  /// every worker exists and the main isolate has initialized, so early
  /// traffic can neither reach an uninitialized context nor trigger a
  /// broadcast that misses a not-yet-spawned sibling. If any startup step
  /// throws, already-spawned workers are shut down before the error is
  /// rethrown — a failed startup never leaves orphan isolates serving.
  static Future<void> run(
    Future<DianaRunnable> Function() bootstrap, {
    int? isolates,
    bool installSignalHandlers = true,
    Future<void>? shutdownTrigger,
  }) async {
    final runnable = await bootstrap();
    final count = isolates ??
        runnable.server.config.get<int>('server.isolates', defaultValue: 1);
    final shared = count > 1;

    final workers = <_Worker>[];
    // In-flight remote-event dispatches, drained before dispose() so a
    // listener mid-run never sees its dependencies torn down underneath.
    final pendingDispatches = <Future<void>>{};
    void onWorkerEvent(_Worker source, Object event) {
      _trackDispatch(
          pendingDispatches, runnable.eventBus?.dispatchRemote(event));
      for (final worker in workers) {
        if (!identical(worker, source)) worker.sendEvent(event);
      }
    }

    try {
      for (var i = 1; i < count; i++) {
        workers.add(await _Worker.spawn(bootstrap, i, onEvent: onWorkerEvent));
      }
      if (runnable.eventBus != null && workers.isNotEmpty) {
        runnable.eventBus!.remoteSink = (event) {
          for (final worker in workers) {
            worker.sendEvent(event);
          }
        };
      }

      await runnable.initialize();
      // Workers wait for this signal to bind the shared socket: by now every
      // sibling is in [workers] and main has initialized, so a broadcast
      // triggered by the first request is dispatched and relayed correctly.
      await Future.wait([for (final worker in workers) worker.startServing()]);
      await runnable.server.serve(shared: shared);
    } catch (_) {
      await Future.wait([for (final worker in workers) worker.abort()]);
      rethrow;
    }

    final shutdown = Completer<void>();
    void requestShutdown() {
      if (!shutdown.isCompleted) shutdown.complete();
    }

    final subscriptions = <StreamSubscription<ProcessSignal>>[];
    if (installSignalHandlers) {
      subscriptions
          .add(ProcessSignal.sigint.watch().listen((_) => requestShutdown()));
      if (!Platform.isWindows) {
        subscriptions.add(
            ProcessSignal.sigterm.watch().listen((_) => requestShutdown()));
      }
    }
    unawaited(shutdownTrigger?.then((_) => requestShutdown(),
        onError: (Object error, StackTrace _) {
      // An erroring trigger must still shut the app down (and not surface
      // as an uncaught async error that kills the isolate).
      stderr.writeln('Diana: shutdownTrigger failed ($error); shutting down.');
      requestShutdown();
    }));

    await shutdown.future;
    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
    await Future.wait([for (final worker in workers) worker.shutdown()]);
    // Workers are gone (no new remote events can arrive); wait out any
    // dispatch still running before close/dispose.
    await Future.wait(pendingDispatches.toList());
    await runnable.server.close();
    await runnable.dispose();
  }
}

/// Tracks [dispatch] in [pending] until it completes, so shutdown can drain
/// in-flight remote dispatches. `dispatchRemote` never throws (listener
/// errors go to the bus's `onError`), so no error handling is needed here.
void _trackDispatch(Set<Future<void>> pending, Future<void>? dispatch) {
  if (dispatch == null) return;
  late final Future<void> tracked;
  tracked = dispatch.whenComplete(() => pending.remove(tracked));
  pending.add(tracked);
}

/// Envelope discriminating bridged events from the lifecycle protocol
/// messages (`SendPort` handshake, `'serve'`/`'serving'`, `'shutdown'`,
/// `'done'`). Workers share an isolate group with main, so the event
/// object travels as-is.
final class _RemoteEvent {
  final Object event;
  _RemoteEvent(this.event);
}

/// A worker isolate running the same bootstrap with shared sockets.
///
/// Protocol: the worker bootstraps and initializes, then hands back its
/// command port and waits; `'serve'` makes it bind the shared socket
/// (acked with `'serving'`), `'shutdown'` drains and disposes (acked with
/// `'done'`). Any failure surfaces as a `'worker failed: …'` string; the
/// `onExit` sentinel (`null`) marks the isolate dead.
class _Worker {
  final int index;
  final SendPort _commands;
  final Isolate _isolate;
  final ReceivePort _fromWorker;
  final ReceivePort _errors;
  final Stream<Object?> _messages;
  final StreamSubscription<Object?> _events;

  /// Set when the isolate exits (the `onExit` sentinel arrives as `null`).
  /// A dead worker is skipped by the event relay and by [shutdown] — without
  /// this, events would vanish silently and shutdown would hang forever.
  bool _dead = false;
  bool _shutdownRequested = false;

  _Worker._(this.index, this._commands, this._isolate, this._fromWorker,
      this._errors, this._messages, this._events);

  /// Relays a broadcast event to this worker (dropped once it died).
  void sendEvent(Object event) {
    if (!_dead) _commands.send(_RemoteEvent(event));
  }

  static Future<_Worker> spawn(
    Future<DianaRunnable> Function() bootstrap,
    int index, {
    void Function(_Worker worker, Object event)? onEvent,
  }) async {
    final fromWorker = ReceivePort();
    // Uncaught async errors are fatal to the isolate; this port logs them
    // (the `onExit` sentinel below then marks the worker dead).
    final errors = ReceivePort()
      ..listen((message) {
        final pair = message as List<Object?>;
        stderr.writeln(
            'Diana worker $index uncaught error: ${pair[0]}\n${pair[1]}');
      });
    final messages = fromWorker.asBroadcastStream();
    // Attached before the isolate exists so no envelope can be dropped
    // between the handshake and the runtime wiring. `worker` is assigned in
    // the microtask receiving the handshake, before any later port message
    // is delivered; only the exit sentinel can arrive earlier (spawn
    // failure), hence nullable instead of `late final`.
    _Worker? worker;
    final events = messages.listen((message) {
      final current = worker;
      if (current == null) return; // pre-handshake; spawn's await handles it
      if (message is _RemoteEvent) {
        onEvent?.call(current, message.event);
      } else if (message == null) {
        current._markDead();
      }
    });
    final isolate = await Isolate.spawn(
      _workerMain,
      (bootstrap, fromWorker.sendPort),
      debugName: 'diana-worker-$index',
      onExit: fromWorker.sendPort,
      onError: errors.sendPort,
    );
    final first =
        await messages.firstWhere((message) => message is! _RemoteEvent);
    if (first is SendPort) {
      worker = _Worker._(
          index, first, isolate, fromWorker, errors, messages, events);
      return worker;
    }
    await events.cancel();
    errors.close();
    fromWorker.close();
    throw StateError('Diana worker $index failed to start: $first');
  }

  void _markDead() {
    if (_dead) return;
    _dead = true;
    if (!_shutdownRequested) {
      stderr.writeln('Diana worker $index exited unexpectedly; '
          'broadcast events no longer reach it.');
    }
  }

  /// Tells the worker (already bootstrapped and initialized) to bind the
  /// shared socket; completes once it is serving. A worker that died or
  /// reports a failure fails startup (the caller aborts its siblings).
  Future<void> startServing() async {
    _commands.send('serve');
    final reply = await _messages
        .firstWhere((message) => message is String || message == null);
    if (reply != 'serving') {
      // Failed or exited: its isolate is gone, so no further command will
      // ever be acknowledged — mark dead so abort() skips it (the thrown
      // error already reports it; no extra stderr line).
      _shutdownRequested = true;
      _markDead();
      throw StateError(reply == null
          ? 'Diana worker $index died before serving'
          : 'Diana worker $index failed to serve: $reply');
    }
  }

  /// Startup-failure teardown: a bounded graceful shutdown that never
  /// masks the original startup error.
  Future<void> abort() async {
    try {
      await shutdown();
    } catch (_) {
      // Unresponsive worker: shutdown() already killed it; move on.
    }
  }

  /// Sentinel for a worker that ignored the shutdown command.
  static const Object _timedOut = 'diana-worker-shutdown-timeout';

  /// Asks the worker to close and dispose. Never hangs: completes on its
  /// `'done'`, on a reported dispose failure (logged), on isolate exit, or
  /// — after [DianaRuntime.workerShutdownTimeout] — by killing the isolate.
  Future<void> shutdown() async {
    _shutdownRequested = true;
    if (!_dead) {
      _commands.send('shutdown');
      final reply = await _messages
          .firstWhere((message) =>
              message == 'done' ||
              message == null ||
              (message is String && message.startsWith('worker failed')))
          .timeout(DianaRuntime.workerShutdownTimeout,
              onTimeout: () => _timedOut);
      if (identical(reply, _timedOut)) {
        stderr.writeln('Diana worker $index did not shut down within '
            '${DianaRuntime.workerShutdownTimeout.inMilliseconds}ms; '
            'killing it.');
        _isolate.kill(priority: Isolate.immediate);
      } else if (reply is String && reply.startsWith('worker failed')) {
        stderr.writeln('Diana worker $index shutdown: $reply');
      }
    }
    await _events.cancel();
    _errors.close();
    _fromWorker.close();
  }

  static Future<void> _workerMain(
    (Future<DianaRunnable> Function(), SendPort) args,
  ) async {
    final (bootstrap, toMain) = args;
    final commands = ReceivePort();
    try {
      // Before bootstrap() so anything constructed during it (including the
      // scheduler) already sees this isolate as a worker.
      DianaRuntime._isWorker = true;
      final runnable = await bootstrap();
      await runnable.initialize();
      toMain.send(commands.sendPort);
      final pendingDispatches = <Future<void>>{};
      await for (final message in commands) {
        if (message == 'shutdown') break;
        if (message == 'serve') {
          // Deferred to the coordinator's signal so no request lands before
          // every isolate is up. The sink is wired only now: a broadcast
          // during this worker's own initialize() delivers locally only
          // (documented).
          await runnable.server.serve(shared: true, quiet: true);
          runnable.eventBus?.remoteSink =
              (event) => toMain.send(_RemoteEvent(event));
          toMain.send('serving');
        }
        if (message is _RemoteEvent) {
          _trackDispatch(pendingDispatches,
              runnable.eventBus?.dispatchRemote(message.event));
        }
      }
      // Drain in-flight remote dispatches before tearing the context down.
      await Future.wait(pendingDispatches.toList());
      await runnable.server.close();
      await runnable.dispose();
      toMain.send('done');
    } catch (error, stackTrace) {
      toMain.send('worker failed: $error\n$stackTrace');
    } finally {
      commands.close();
    }
  }
}
