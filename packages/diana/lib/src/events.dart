/// Application events (Spring: `ApplicationEventPublisher`).
///
/// Providers annotate handler methods with `@EventListener` and inject
/// [DianaEventPublisher]; the generated context registers every listener on
/// a [DianaEventBus] before `initialize()` runs. Local dispatch is
/// synchronous and awaited; [DianaEventPublisher.broadcast] additionally
/// relays the event to every other isolate (fire-and-forget) when the app
/// serves with `server.isolates > 1`.
library;

import 'dart:async';

import 'observer.dart';

/// Publishes application events to `@EventListener` methods.
///
/// Inject this interface (not the concrete bus) into any provider via
/// constructor parameter.
abstract interface class DianaEventPublisher {
  /// Delivers [event] to every matching local listener, in registration
  /// order, awaiting each one. A listener throwing propagates to the caller
  /// and skips the remaining listeners.
  Future<void> publish(Object event);

  /// Like [publish], but first relays [event] to every other isolate
  /// (fire-and-forget; remote listener errors never reach the caller).
  ///
  /// The event must be sendable across isolates — plain data, no
  /// `ReceivePort`s, sockets or other native resources. An unsendable event
  /// throws [ArgumentError] before any local listener runs. With a single
  /// isolate this is identical to [publish].
  Future<void> broadcast(Object event);
}

/// The event bus behind [DianaEventPublisher].
///
/// The generated `DianaContext` owns one instance and registers every
/// `@EventListener` method on it; `DianaRuntime` wires [remoteSink] when
/// serving with multiple isolates. Constructible directly in tests.
class DianaEventBus implements DianaEventPublisher {
  final void Function(Object error, StackTrace stackTrace) _onError;

  /// Observes each local dispatch (type, duration). `null` costs nothing.
  final DianaObserver? observer;

  final List<_Registration> _registrations = [];

  /// Where broadcast events are handed off for cross-isolate relay; set by
  /// the runtime, `null` in single-isolate mode.
  void Function(Object event)? remoteSink;

  DianaEventBus({
    void Function(Object error, StackTrace stackTrace)? onError,
    this.observer,
  }) : _onError = onError ?? _defaultOnError;

  static void _defaultOnError(Object error, StackTrace stackTrace) {
    // ignore: avoid_print
    print('[diana] Event listener failed for remote event: $error\n'
        '$stackTrace');
  }

  /// Registers [listener] for events of type [T] (and subtypes). Generated
  /// code calls this from the context constructor; tests may call it
  /// directly.
  void on<T extends Object>(FutureOr<void> Function(T event) listener) {
    _registrations.add(_Registration(
      matches: (event) => event is T,
      invoke: (event) => listener(event as T),
    ));
  }

  @override
  Future<void> publish(Object event) async {
    final sw = observer == null ? null : (Stopwatch()..start());
    try {
      // Snapshot: a listener registering another listener mid-dispatch must
      // not throw ConcurrentModificationError (the new listener joins from
      // the next publish).
      for (final registration in List.of(_registrations)) {
        if (registration.matches(event)) {
          await Future.sync(() => registration.invoke(event));
        }
      }
    } finally {
      // Observed even when a listener throws (the error still propagates to
      // the publisher), so the counter reflects every dispatch attempted.
      if (sw != null) {
        observer!.observeEventDispatch('${event.runtimeType}', sw.elapsed);
      }
    }
  }

  @override
  Future<void> broadcast(Object event) async {
    final sink = remoteSink;
    if (sink != null) {
      try {
        sink(event);
      } on ArgumentError {
        throw ArgumentError(
          'Diana broadcast failed: event of type ${event.runtimeType} is '
          'not sendable across isolates. Broadcast events must be plain '
          'data (no ReceivePorts or other unsendable objects). '
          'See docs/guides/events.md.',
        );
      }
    }
    await publish(event);
  }

  /// Delivers an event received from another isolate to local listeners.
  ///
  /// Never touches [remoteSink] (no relay loops), and listener errors are
  /// routed to `onError` instead of thrown — there is no cross-isolate
  /// caller to propagate them to.
  Future<void> dispatchRemote(Object event) async {
    // Same snapshot as publish(): registering a listener mid-dispatch must
    // not throw ConcurrentModificationError.
    for (final registration in List.of(_registrations)) {
      if (registration.matches(event)) {
        try {
          await Future.sync(() => registration.invoke(event));
        } catch (error, stackTrace) {
          _onError(error, stackTrace);
        }
      }
    }
  }
}

class _Registration {
  final bool Function(Object event) matches;
  final FutureOr<void> Function(Object event) invoke;

  _Registration({required this.matches, required this.invoke});
}
