import 'package:meta/meta_meta.dart';

/// Registers a `Middleware` implementation globally, applied to every route.
///
/// Global middleware run in ascending [order] (ties broken by class name),
/// before controller- and route-level middleware. The class joins the
/// dependency injection graph automatically.
@Target({TargetKind.classType})
class GlobalMiddleware {
  final int order;
  const GlobalMiddleware({this.order = 0});
}

/// Applies `Middleware` implementations to a controller (all its routes) or
/// to a single route method, in the listed order.
///
/// The referenced types must be injectable (e.g. `@Component()`) and
/// implement Diana's `Middleware` interface.
@Target({TargetKind.classType, TargetKind.method})
class UseMiddleware {
  final List<Type> middleware;
  const UseMiddleware(this.middleware);
}
