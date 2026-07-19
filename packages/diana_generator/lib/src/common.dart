/// Shared helpers for the Diana builders.
library;

/// Cheap textual pre-check: does this source possibly contain Diana
/// annotations? Avoids resolving libraries that can't be relevant.
final RegExp dianaAnnotationPattern = RegExp(
  r'@(Injectable|Service|Repository|Component|RestController|'
  r'WebSocketController|GlobalMiddleware|UseMiddleware|ControllerAdvice|'
  r'ConfigurationProperties|DianaApplication|NotNull|NotEmpty|NotBlank|Min|'
  r'Max|Size|Pattern|Email|Valid|CrossOrigin|Json|JsonField|Scheduled|Consumes|Produces|GrpcService|EventListener|Secured|RolesAllowed|Principal|Transactional|'
  r'Timed|Cacheable|Retryable|CircuitBreaker|Table)\b',
);

/// Pre-check for the application entrypoint annotation only.
final RegExp dianaApplicationPattern = RegExp(r'@DianaApplication\b');

/// Header prepended to every generated Dart file.
const String generatedHeader = '''
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import
''';

/// Joins a controller base path and a route path into a normalized route
/// (`/todos` + `/:id` → `/todos/:id`).
String joinPaths(String base, String sub) {
  String normalize(String s) {
    if (s.isEmpty || s == '/') return '';
    var result = s.startsWith('/') ? s : '/$s';
    if (result.endsWith('/')) result = result.substring(0, result.length - 1);
    return result;
  }

  final joined = '${normalize(base)}${normalize(sub)}';
  return joined.isEmpty ? '/' : joined;
}
