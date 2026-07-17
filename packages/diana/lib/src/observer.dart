/// The neutral observation contract Diana's runtime calls into.
///
/// Diana itself never depends on an observability implementation. Instead
/// the server, scheduler, event bus and (via `package:diana_data`) the
/// database call these hooks, and an add-on package like
/// `diana_observability` subclasses [DianaObserver] to record metrics and
/// spans. Every method has a no-op default, so subclasses override only the
/// surfaces they care about, and a `null` observer costs nothing.
library;

import 'dart:async';

import 'http/method.dart';
import 'http/request.dart';
import 'http/response.dart';
import 'middleware.dart';

abstract class DianaObserver {
  const DianaObserver();

  /// Wraps a fully-composed route handler ([next]) — including the error
  /// boundary, so the returned response carries the final status (2xx/4xx/
  /// 5xx) and [next] never throws. [routeTemplate] is the registered
  /// pattern (`/todos/:id`), not the concrete path, keeping metric/span
  /// cardinality bounded.
  FutureOr<DianaResponse> observeHttp(
    HttpMethod method,
    String routeTemplate,
    DianaRequest request,
    DianaHandler next,
  ) =>
      next(request);

  /// Called once per request that matched no route (a 404). No path is
  /// passed — unmatched paths are unbounded, so they are counted in
  /// aggregate only.
  void observeUnmatched() {}

  /// Wraps a database operation ([run]) — `select`, `insert`, `update`,
  /// `delete`, `raw` or `transaction`.
  FutureOr<T> observeQuery<T>(String operation, FutureOr<T> Function() run) =>
      run();

  /// Wraps a `@Timed` proxied method invocation ([run]). [name] is
  /// `Class.method`, or the annotation's `name:` override; cardinality is
  /// bounded by the set of annotated methods.
  FutureOr<T> observeTimedMethod<T>(String name, FutureOr<T> Function() run) =>
      run();

  /// Reports a completed `@Scheduled` run. [name] is `Class.method` when the
  /// generator wired it, else `null`.
  void observeScheduledRun(
    String? name,
    Duration elapsed, {
    required bool success,
  }) {}

  /// Reports a completed event dispatch. [eventType] is the event's runtime
  /// type name.
  void observeEventDispatch(String eventType, Duration elapsed) {}
}
