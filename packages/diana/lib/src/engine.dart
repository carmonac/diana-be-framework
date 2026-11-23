/// The pluggable HTTP engine contract.
///
/// Diana serves through relic. By default relic's `dart:io` adapter accepts
/// connections; an add-on (e.g. `diana_native`) can swap in another relic
/// adapter by providing one [DianaHttpEngine] singleton, which the generator
/// discovers by supertype and threads into [DianaServer].
library;

import 'dart:async';
import 'dart:io';

/// Where and how an engine binds. Built by Diana from `server.*` config.
final class DianaEngineBinding {
  /// The parsed `server.host`.
  final InternetAddress address;

  /// The `server.port` (0 lets the OS pick one).
  final int port;

  /// PEM certificate chain path (`server.ssl.certPath`), or `null` for HTTP.
  final String? sslCertPath;

  /// PEM private key path (`server.ssl.keyPath`).
  final String? sslKeyPath;

  /// Password of an encrypted private key (`server.ssl.keyPassword`).
  final String? sslKeyPassword;

  /// Whether several isolates of this process bind the same address/port
  /// (multi-isolate serving).
  final bool shared;

  const DianaEngineBinding({
    required this.address,
    required this.port,
    this.sslCertPath,
    this.sslKeyPath,
    this.sslKeyPassword,
    this.shared = false,
  });

  /// Whether HTTPS was requested.
  bool get secure => sslCertPath != null;
}

/// Supplies the relic adapter Diana serves through.
///
/// Implementations live in add-on packages; core never names a concrete
/// engine. Exactly one singleton provider may extend this class.
abstract class DianaHttpEngine {
  const DianaHttpEngine();

  /// A short engine name for the startup log (`native`, …).
  String get name;

  /// Binds and returns the engine's relic `Adapter` (from
  /// `package:relic_core`). Typed as [Object] so relic stays out of Diana's
  /// public API; anything else fails at startup with a [StateError].
  FutureOr<Object> bind(DianaEngineBinding binding);
}
