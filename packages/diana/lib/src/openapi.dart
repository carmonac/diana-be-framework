/// Runtime support for the generated OpenAPI document.
library;

import 'dart:convert';

import 'config.dart';

/// Patches `info.title`/`info.version` of the build-time-generated
/// [document] from `server.openapi.title` / `server.openapi.version`
/// (keeping the const deterministic while letting deployments brand it).
String patchOpenApiInfo(String document, DianaConfig config) {
  final decoded = (jsonDecode(document) as Map).cast<String, Object?>();
  final info = (decoded['info'] as Map?)?.cast<String, Object?>() ?? {};
  decoded['info'] = {
    ...info,
    'title': config.get<String>('server.openapi.title',
        defaultValue: info['title'] as String? ?? 'Diana application'),
    'version': config.get<String>('server.openapi.version',
        defaultValue: info['version'] as String? ?? '0.0.0'),
  };
  return jsonEncode(decoded);
}
