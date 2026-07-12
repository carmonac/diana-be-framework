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

  /// Profiles applied by [load] (empty for hand-built configs).
  final List<String> activeProfiles;

  /// Creates a config from already-flattened dot-keys
  /// (e.g. `{'server.port': 8080}`). Pass [environment] to enable env
  /// overrides (tests can inject a fake map).
  DianaConfig(
    Map<String, Object?> values, {
    Map<String, String>? environment,
    List<String> activeProfiles = const [],
  })  : _values = Map.unmodifiable(values),
        _environment = environment ?? const {},
        activeProfiles = List.unmodifiable(activeProfiles);

  /// An empty configuration.
  const DianaConfig.empty()
      : _values = const {},
        _environment = const {},
        activeProfiles = const [];

  /// Loads [path] (YAML), applies profile overlays and overlays
  /// [Platform.environment]. A missing file yields an env-only
  /// configuration, so containerized deployments can run on environment
  /// variables alone.
  ///
  /// Active profiles come from the `DIANA_PROFILE` environment variable
  /// (comma-separated, Spring-style), which fully replaces the
  /// `diana.profile` key of the base file when set. For each active profile
  /// `p`, `application-p.yaml` (next to [path]) is overlaid in listed order
  /// — later profiles win; environment variables still win over everything.
  /// Missing profile files are skipped.
  static Future<DianaConfig> load(
    String path, {
    Map<String, String>? environment,
  }) async {
    final env = environment ?? Platform.environment;
    final values = <String, Object?>{};
    await _mergeYamlFile(path, values);

    final profilesRaw = env['DIANA_PROFILE'] ??
        (values['diana.profile']?.toString() ?? '');
    final profiles = [
      for (final p in profilesRaw.split(','))
        if (p.trim().isNotEmpty) p.trim(),
    ];
    if (profiles.isNotEmpty) {
      final dot = path.lastIndexOf('.');
      final stem = dot == -1 ? path : path.substring(0, dot);
      final ext = dot == -1 ? '.yaml' : path.substring(dot);
      for (final profile in profiles) {
        await _mergeYamlFile('$stem-$profile$ext', values);
      }
    }

    return DianaConfig(values, environment: env, activeProfiles: profiles);
  }

  static Future<void> _mergeYamlFile(
    String path,
    Map<String, Object?> into,
  ) async {
    final file = File(path);
    if (!file.existsSync()) return;
    final doc = loadYaml(await file.readAsString());
    if (doc is YamlMap) _flatten(doc, '', into);
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

  /// The flattened keys under `prefix.`, with the prefix stripped and
  /// environment overrides applied.
  ///
  /// Only keys present in the YAML sources are enumerated (environment-only
  /// keys cannot be discovered, since env names don't map back to dot-keys
  /// unambiguously).
  Map<String, Object?> section(String prefix) {
    final withDot = '$prefix.';
    return {
      for (final entry in _values.entries)
        if (entry.key.startsWith(withDot))
          entry.key.substring(withDot.length):
              _environment[envNameFor(entry.key)] ?? entry.value,
    };
  }

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
    final asList = _coerceList<T>(raw);
    if (asList != null) return asList;
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

  /// Coerces YAML lists (element-wise) and comma-separated env strings to
  /// `List<String>`/`List<int>`/`List<double>`/`List<bool>`/`List<num>`.
  T? _coerceList<T>(Object raw) {
    final wantsList = T == _typeOf<List<String>>() ||
        T == _typeOf<List<String>?>() ||
        T == _typeOf<List<int>>() ||
        T == _typeOf<List<int>?>() ||
        T == _typeOf<List<double>>() ||
        T == _typeOf<List<double>?>() ||
        T == _typeOf<List<bool>>() ||
        T == _typeOf<List<bool>?>() ||
        T == _typeOf<List<num>>() ||
        T == _typeOf<List<num>?>();
    if (!wantsList) return null;

    final List<Object?> elements;
    if (raw is List) {
      elements = raw;
    } else if (raw is String) {
      elements = [
        for (final part in raw.split(','))
          if (part.trim().isNotEmpty) part.trim(),
      ];
    } else {
      return null;
    }

    List<E>? convert<E>() {
      final result = <E>[];
      for (final element in elements) {
        if (element == null) return null;
        final coerced = _coerce<E>(element);
        if (coerced == null) return null;
        result.add(coerced);
      }
      return result;
    }

    Object? result;
    if (T == _typeOf<List<String>>() || T == _typeOf<List<String>?>()) {
      result = convert<String>();
    } else if (T == _typeOf<List<int>>() || T == _typeOf<List<int>?>()) {
      result = convert<int>();
    } else if (T == _typeOf<List<double>>() ||
        T == _typeOf<List<double>?>()) {
      result = convert<double>();
    } else if (T == _typeOf<List<bool>>() || T == _typeOf<List<bool>?>()) {
      result = convert<bool>();
    } else if (T == _typeOf<List<num>>() || T == _typeOf<List<num>?>()) {
      result = convert<num>();
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
