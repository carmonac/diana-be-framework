import 'package:meta/meta_meta.dart';

import 'di.dart';

/// Marks a class as an HTTP controller whose routes are mounted under [path].
///
/// Controllers join the dependency injection graph: constructor parameters
/// are injected. Route methods are annotated with [Get], [Post], etc.
@Target({TargetKind.classType})
class RestController {
  /// Base path for every route in the controller, e.g. `/todos`.
  final String path;

  /// Lifecycle of the controller. Controllers depending on request-scoped
  /// providers must be request-scoped themselves.
  final Scope scope;

  const RestController([this.path = '/', this.scope = Scope.singleton]);
}

/// Base class for HTTP route annotations. Prefer the [Get]/[Post]/[Put]/
/// [Delete]/[Patch] shorthands.
@Target({TargetKind.method})
class HttpRoute {
  /// HTTP method, upper-case (`GET`, `POST`, ...).
  final String method;

  /// Route path relative to the controller base path. May contain `:name`
  /// path parameters, e.g. `/:id`.
  final String path;

  const HttpRoute(this.method, this.path);
}

/// Maps a method to `GET` requests.
@Target({TargetKind.method})
class Get extends HttpRoute {
  const Get([String path = '']) : super('GET', path);
}

/// Maps a method to `POST` requests.
@Target({TargetKind.method})
class Post extends HttpRoute {
  const Post([String path = '']) : super('POST', path);
}

/// Maps a method to `PUT` requests.
@Target({TargetKind.method})
class Put extends HttpRoute {
  const Put([String path = '']) : super('PUT', path);
}

/// Maps a method to `DELETE` requests.
@Target({TargetKind.method})
class Delete extends HttpRoute {
  const Delete([String path = '']) : super('DELETE', path);
}

/// Maps a method to `PATCH` requests.
@Target({TargetKind.method})
class Patch extends HttpRoute {
  const Patch([String path = '']) : super('PATCH', path);
}

/// Binds a route-method parameter to a path parameter.
///
/// The parameter name defaults to the Dart parameter name:
/// `@Get('/:id') getById(@PathParam() int id)`.
@Target({TargetKind.parameter})
class PathParam {
  final String? name;
  const PathParam([this.name]);
}

/// Binds a route-method parameter to a query-string parameter.
///
/// Nullable parameter types make the query parameter optional;
/// [defaultValue] (always given as a string) is applied when absent.
@Target({TargetKind.parameter})
class QueryParam {
  final String? name;
  final String? defaultValue;
  const QueryParam([this.name, this.defaultValue]);
}

/// Binds a route-method parameter to an HTTP request header.
@Target({TargetKind.parameter})
class Header {
  final String? name;
  const Header([this.name]);
}

/// Binds a route-method parameter to the JSON request body.
///
/// The parameter type must be `Map<String, dynamic>`, a DTO exposing
/// `factory X.fromJson(Map<String, dynamic>)`, or a `List` of either.
@Target({TargetKind.parameter})
class Body {
  const Body();
}

/// Overrides the success status code of a route (default 200, or 204 for
/// `void` returns).
@Target({TargetKind.method})
class ResponseStatus {
  final int code;
  const ResponseStatus(this.code);
}
