import 'dart:async';
import 'dart:io';

import 'package:diana/diana.dart';
import 'package:relic_native/relic_native.dart';

/// Serves a Diana app through relic_native's Zig HTTP server instead of
/// `dart:io`.
///
/// ```dart
/// @Component()
/// class AppEngine extends DianaNativeEngine {}
/// ```
///
/// Routing, middleware, SSE, WebSockets and static files behave the same.
/// HTTPS (`server.ssl.*`) is TLS 1.3 only. Multi-isolate serving shares one
/// native server: every isolate joins the same bind group.
class DianaNativeEngine extends DianaHttpEngine {
  /// Limits and timeouts of the native server.
  final NativeOptions options;

  const DianaNativeEngine({this.options = const NativeOptions()});

  @override
  String get name => 'native';

  @override
  Future<Object> bind(DianaEngineBinding binding) async {
    NativeTls? tls;
    if (binding.sslCertPath != null && binding.sslKeyPath != null) {
      tls = NativeTls(
        certificateChain: await File(binding.sslCertPath!).readAsBytes(),
        privateKey: await File(binding.sslKeyPath!).readAsBytes(),
        password: binding.sslKeyPassword,
      );
    }
    return NativeAdapter.bind(
      binding.address,
      port: binding.port,
      // Isolates of one process that serve the same address/port join one
      // native server; a non-shared bind gets a server of its own.
      group: binding.shared ? bindGroup(binding) : null,
      options: options,
      tls: tls,
    );
  }

  /// The bind group shared by this process's isolates for [binding].
  static String bindGroup(DianaEngineBinding binding) =>
      'diana_native/$pid/${binding.address.address}:${binding.port}';
}
