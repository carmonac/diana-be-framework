import 'package:meta/meta_meta.dart';

/// Lifecycle scope of an injectable class.
enum Scope {
  /// One instance for the whole application (default).
  singleton,

  /// One instance per HTTP request.
  request,

  /// A new instance every time the dependency is requested.
  transient,
}

/// Marks a class as a provider in the dependency injection graph.
///
/// The class is instantiated through its unnamed constructor; every
/// constructor parameter is resolved from the graph at build time. Missing or
/// circular dependencies fail the build, not the runtime.
@Target({TargetKind.classType})
class Injectable {
  /// Lifecycle of the instances produced by this provider.
  final Scope scope;

  /// Explicitly bind this provider to [as] (usually an implemented
  /// interface) in addition to its own type.
  final Type? as;

  /// Qualifier under which this provider is registered. Consumers select it
  /// with `@Named(name)` on the constructor parameter.
  final String? name;

  const Injectable({this.scope = Scope.singleton, this.as, this.name});
}

/// An [Injectable] that expresses business logic (semantic alias).
@Target({TargetKind.classType})
class Service extends Injectable {
  const Service({super.scope, super.as, super.name});
}

/// An [Injectable] that encapsulates data access (semantic alias).
@Target({TargetKind.classType})
class Repository extends Injectable {
  const Repository({super.scope, super.as, super.name});
}

/// A generic [Injectable] component (semantic alias).
@Target({TargetKind.classType})
class Component extends Injectable {
  const Component({super.scope, super.as, super.name});
}

/// Selects a qualified provider for a constructor parameter.
///
/// ```dart
/// @Service()
/// class Notifier {
///   Notifier(@Named('smtp') MailSender sender);
/// }
/// ```
@Target({TargetKind.parameter})
class Named {
  final String name;
  const Named(this.name);
}
