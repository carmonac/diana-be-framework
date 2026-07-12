import 'package:diana/diana.dart';

part 'audit_controller.diana.dart';

/// Request-scoped provider: a fresh instance per HTTP request.
@Component(scope: Scope.request)
class RequestAudit {
  static int _counter = 0;
  final int id = ++_counter;
}

/// A controller depending on request-scoped providers must be
/// request-scoped itself.
@RestController('/audit', Scope.request)
class AuditController {
  final RequestAudit audit;

  AuditController(this.audit);

  @Get()
  Map<String, dynamic> get() => {'requestId': audit.id};
}
