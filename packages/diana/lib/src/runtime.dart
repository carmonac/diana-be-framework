import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'server.dart';

/// What the generated bootstrap hands to [DianaRuntime.run]: the server plus
/// the application lifecycle callbacks.
class DianaRunnable {
  final DianaServer server;
  final Future<void> Function() initialize;
  final Future<void> Function() dispose;

  DianaRunnable({
    required this.server,
    required this.initialize,
    required this.dispose,
  });
}

/// Runs a Diana application with lifecycle and graceful shutdown:
/// bootstrap → `initialize()` (`@PostConstruct` in dependency order) →
/// `serve()` → wait for SIGINT/SIGTERM → `close()` (drains in-flight
/// requests) → `dispose()` (`@PreDestroy` in reverse order).
class DianaRuntime {
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
    for (var i = 1; i < count; i++) {
      workers.add(await _Worker.spawn(bootstrap, i));
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

/// A worker isolate running the same bootstrap with shared sockets.
class _Worker {
  final SendPort _commands;
  final ReceivePort _fromWorker;
  final Stream<Object?> _messages;

  _Worker._(this._commands, this._fromWorker, this._messages);

  static Future<_Worker> spawn(
    Future<DianaRunnable> Function() bootstrap,
    int index,
  ) async {
    final fromWorker = ReceivePort();
    final messages = fromWorker.asBroadcastStream();
    await Isolate.spawn(
      _workerMain,
      (bootstrap, fromWorker.sendPort),
      debugName: 'diana-worker-$index',
    );
    final first = await messages.first;
    if (first is SendPort) {
      return _Worker._(first, fromWorker, messages);
    }
    fromWorker.close();
    throw StateError('Diana worker $index failed to start: $first');
  }

  Future<void> shutdown() async {
    _commands.send('shutdown');
    await _messages.firstWhere((message) => message == 'done');
    _fromWorker.close();
  }

  static Future<void> _workerMain(
    (Future<DianaRunnable> Function(), SendPort) args,
  ) async {
    final (bootstrap, toMain) = args;
    final commands = ReceivePort();
    try {
      final runnable = await bootstrap();
      await runnable.initialize();
      await runnable.server.serve(shared: true, quiet: true);
      toMain.send(commands.sendPort);
      await commands.firstWhere((message) => message == 'shutdown');
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
