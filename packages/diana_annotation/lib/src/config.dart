import 'package:meta/meta_meta.dart';

/// Injects a configuration value (from `application.yaml`, overridable via
/// environment variables) into a constructor parameter.
///
/// ```dart
/// @Service()
/// class Greeter {
///   Greeter(@Value('app.greeting', defaultValue: 'hello') this.greeting);
///   final String greeting;
/// }
/// ```
///
/// A missing key without [defaultValue] fails at application startup.
@Target({TargetKind.parameter})
class Value {
  /// Dot-separated configuration key, e.g. `server.port`.
  final String key;

  /// Fallback applied when the key is absent from every configuration source.
  final Object? defaultValue;

  const Value(this.key, {this.defaultValue});
}

/// Binds a whole configuration section to a class, which becomes injectable.
///
/// Each final field is bound from `<prefix>.<fieldName>` through the unnamed
/// constructor's named parameters.
@Target({TargetKind.classType})
class ConfigurationProperties {
  /// Dot-separated key prefix, e.g. `app.mail`.
  final String prefix;

  const ConfigurationProperties(this.prefix);
}
