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
    void onWorkerEvent(_Worker source, Object event) {
      unawaited(
          runnable.eventBus?.dispatchRemote(event) ?? Future<void>.value());
      for (final worker in workers) {
        if (!identical(worker, source)) worker.sendEvent(event);
      }
    }

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
    await runnable.server.serve(shared: shared);

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
    unawaited(shutdownTrigger?.then((_) => requestShutdown()));

    await shutdown.future;
    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
    await Future.wait([for (final worker in workers) worker.shutdown()]);
    await runnable.server.close();
    await runnable.dispose();
  }
}

/// Envelope discriminating bridged events from the lifecycle protocol
/// messages (`SendPort` handshake, `'shutdown'`, `'done'`). Workers share an
/// isolate group with main, so the event object travels as-is.
final class _RemoteEvent {
  final Object event;
  _RemoteEvent(this.event);
}

/// A worker isolate running the same bootstrap with shared sockets.
class _Worker {
  final SendPort _commands;
  final ReceivePort _fromWorker;
  final Stream<Object?> _messages;
  final StreamSubscription<Object?> _events;

  _Worker._(this._commands, this._fromWorker, this._messages, this._events);

  /// Relays a broadcast event to this worker.
  void sendEvent(Object event) => _commands.send(_RemoteEvent(event));

  static Future<_Worker> spawn(
    Future<DianaRunnable> Function() bootstrap,
    int index, {
    void Function(_Worker worker, Object event)? onEvent,
  }) async {
    final fromWorker = ReceivePort();
    final messages = fromWorker.asBroadcastStream();
    // Attached before the isolate exists so no envelope can be dropped
    // between the handshake and the runtime wiring.
    late final _Worker worker;
    final events = messages.listen((message) {
      if (message is _RemoteEvent) onEvent?.call(worker, message.event);
    });
    await Isolate.spawn(
      _workerMain,
      (bootstrap, fromWorker.sendPort),
      debugName: 'diana-worker-$index',
    );
    final first = await messages.firstWhere((message) => message is! _RemoteEvent);
    if (first is SendPort) {
      worker = _Worker._(first, fromWorker, messages, events);
      return worker;
    }
    await events.cancel();
    fromWorker.close();
    throw StateError('Diana worker $index failed to start: $first');
  }

  Future<void> shutdown() async {
    _commands.send('shutdown');
    await _messages.firstWhere((message) => message == 'done');
    await _events.cancel();
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
      await runnable.server.serve(shared: true, quiet: true);
      toMain.send(commands.sendPort);
      // The sink is wired only after the handshake: a broadcast during this
      // worker's own initialize() delivers locally only (documented).
      runnable.eventBus?.remoteSink =
          (event) => toMain.send(_RemoteEvent(event));
      await for (final message in commands) {
        if (message == 'shutdown') break;
        if (message is _RemoteEvent) {
          unawaited(runnable.eventBus?.dispatchRemote(message.event) ??
              Future<void>.value());
        }
      }
      await runnable.server.close();
      await runnable.dispose();
      toMain.send('done');
    } catch (error) {
      toMain.send('worker failed: $error');
    } finally {
      commands.close();
    }
  }
}
