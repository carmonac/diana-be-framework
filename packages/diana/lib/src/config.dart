import 'dart:io';

import 'package:yaml/yaml.dart';

/// Configuration store backed by flattened dot-separated keys, with
/// environment-variable overrides.
///
/// Sources, highest precedence first:
/// 1. Environment variables (`server.port` ← `SERVER_PORT`)
/// 2. The YAML file loaded by [DianaConfig.load] (nested maps flattened to
///    dot keys)
class DianaConfig {
  final Map<String, Object?> _values;
  final Map<String, String> _environment;

  /// Creates a config from already-flattened dot-keys
  /// (e.g. `{'server.port': 8080}`). Pass [environment] to enable env
  /// overrides (tests can inject a fake map).
  DianaConfig(
    Map<String, Object?> values, {
    Map<String, String>? environment,
  })  : _values = Map.unmodifiable(values),
        _environment = environment ?? const {};

  /// An empty configuration.
  const DianaConfig.empty()
      : _values = const {},
        _environment = const {};

  /// Loads [path] (YAML) and overlays [Platform.environment]. A missing file
  /// yields an env-only configuration, so containerized deployments can run
  /// on environment variables alone.
  static Future<DianaConfig> load(
    String path, {
    Map<String, String>? environment,
  }) async {
    final file = File(path);
    final values = <String, Object?>{};
    if (file.existsSync()) {
      final doc = loadYaml(await file.readAsString());
      if (doc is YamlMap) _flatten(doc, '', values);
    }
    return DianaConfig(
      values,
      environment: environment ?? Platform.environment,
    );
  }

  static void _flatten(
    YamlMap node,
    String prefix,
    Map<String, Object?> into,
  ) {
    for (final entry in node.entries) {
      final key = prefix.isEmpty ? '${entry.key}' : '$prefix.${entry.key}';
      final value = entry.value;
      if (value is YamlMap) {
        _flatten(value, key, into);
      } else if (value is YamlList) {
        into[key] = List<Object?>.unmodifiable(value);
      } else {
        into[key] = value;
      }
    }
  }

  /// Whether [key] is present in any configuration source.
  bool contains(String key) =>
      _environment.containsKey(envNameFor(key)) || _values.containsKey(key);

  /// Returns the value for [key] coerced to [T] (`String`, `int`, `double`,
  /// `bool` or `num`).
  ///
  /// Falls back to [defaultValue] when the key is absent; throws
  /// [ConfigException] when the key is absent without a default (unless [T]
  /// is nullable), or when the value cannot be represented as [T].
  T get<T>(String key, {T? defaultValue}) {
    final Object? raw = _environment[envNameFor(key)] ??
        (_values.containsKey(key) ? _values[key] : null);
    if (raw == null) {
      if (defaultValue != null) return defaultValue;
      if (null is T) return null as T;
      throw ConfigException(
        'Missing required config key "$key" '
        '(checked the YAML config file and environment variable '
        '"${envNameFor(key)}").',
      );
    }
    final coerced = _coerce<T>(raw);
    if (coerced == null) {
      throw ConfigException(
        'Config key "$key" has value "$raw" '
        '(${raw.runtimeType}), which cannot be read as $T.',
      );
    }
    return coerced;
  }

  /// The environment variable that overrides [key]: upper-cased with dots
  /// and dashes replaced by underscores (`server.port` → `SERVER_PORT`).
  static String envNameFor(String key) =>
      key.toUpperCase().replaceAll('.', '_').replaceAll('-', '_');

  T? _coerce<T>(Object raw) {
    if (raw is T) return raw as T;
    final s = raw.toString();
    Object? result;
    if (T == int || T == _typeOf<int?>()) {
      result = int.tryParse(s);
    } else if (T == num || T == _typeOf<num?>()) {
      result = num.tryParse(s);
    } else if (T == double || T == _typeOf<double?>()) {
      result = double.tryParse(s);
    } else if (T == bool || T == _typeOf<bool?>()) {
      result = switch (s.toLowerCase()) {
        'true' || '1' || 'yes' || 'on' => true,
        'false' || '0' || 'no' || 'off' => false,
        _ => null,
      };
    } else if (T == String || T == _typeOf<String?>()) {
      result = s;
    }
    return result as T?;
  }

  static Type _typeOf<X>() => X;
}

/// Thrown for missing or badly-typed configuration values.
class ConfigException implements Exception {
  final String message;
  ConfigException(this.message);

  @override
  String toString() => 'ConfigException: $message';
}
