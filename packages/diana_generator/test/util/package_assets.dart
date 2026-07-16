import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;

/// Reads every `lib/` source of [package] (resolved through the current
/// package config) as in-memory build assets, so `testBuilder` resolvers can
/// resolve `package:` imports in test sources.
Future<Map<String, String>> packageAssets(String package) async {
  final anyLibUri =
      await Isolate.resolvePackageUri(Uri.parse('package:$package/_.dart'));
  final libDir = Directory(p.dirname(anyLibUri!.toFilePath()));
  return {
    for (final file in libDir.listSync(recursive: true).whereType<File>())
      if (file.path.endsWith('.dart'))
        '$package|lib/${p.relative(file.path, from: libDir.path)}':
            file.readAsStringSync(),
  };
}

Map<String, String>? _cached;

/// Assets every Diana builder test needs: the annotation package, meta, and
/// a minimal stub of `package:diana` (same library URIs as the real runtime,
/// without its HTTP-engine dependency) so test sources can implement
/// `Middleware` etc.
Future<Map<String, String>> dianaTestDeps() async => _cached ??= {
      ...await packageAssets('diana_annotation'),
      ...await packageAssets('meta'),
      ..._fakeDianaRuntime,
    };

const Map<String, String> _fakeDianaRuntime = {
  'grpc|lib/grpc.dart': '''
export 'src/server/service.dart';
''',
  'grpc|lib/src/server/service.dart': '''
abstract class Service {
  String get \$name;
}
''',
  'diana_auth|lib/diana_auth.dart': '''
import 'dart:async';

import 'package:diana/diana.dart';

abstract interface class Authenticator {}

class AuthenticationMiddleware implements Middleware {
  const AuthenticationMiddleware({required this.authenticators});
  final List<Authenticator> authenticators;

  Future<Set<String>?> authorizeMetadata(Map<String, String> metadata) async =>
      null;

  @override
  Future<DianaResponse> handle(DianaRequest request, Next next) => next(request);
}
''',
  'diana_data|lib/diana_data.dart': '''
class Database {
  Future<T> runTransactional<T>(Future<T> Function() body) => body();
}

abstract class DatabaseConnector {
  Future<Object> connect(Object config);
  Future<void> close(Object connection);
}
''',
  'diana_observability|lib/diana_observability.dart': '''
import 'package:diana/diana.dart';

class DianaObservability extends DianaObserver {}

DianaHandler metricsEndpointHandler(DianaObservability o) =>
    (req) => throw UnimplementedError();
''',
  'diana|lib/diana.dart': '''
export 'package:diana_annotation/diana_annotation.dart';

export 'src/codec.dart';
export 'src/events.dart';
export 'src/http/request.dart';
export 'src/http/response.dart';
export 'src/middleware.dart';
export 'src/observer.dart';
export 'src/sse.dart';
export 'src/websocket.dart';
''',
  'diana|lib/src/observer.dart': '''
import 'dart:async';

import 'http/request.dart';
import 'http/response.dart';
import 'middleware.dart';

abstract class DianaObserver {
  const DianaObserver();
  FutureOr<DianaResponse> observeHttp(Object method, String routeTemplate,
          DianaRequest request, DianaHandler next) =>
      next(request);
  void observeUnmatched() {}
  FutureOr<T> observeQuery<T>(String operation, FutureOr<T> Function() run) =>
      run();
  void observeScheduledRun(String? name, Duration elapsed,
      {required bool success}) {}
  void observeEventDispatch(String eventType, Duration elapsed) {}
}
''',
  'diana|lib/src/events.dart': '''
import 'dart:async';

abstract interface class DianaEventPublisher {
  Future<void> publish(Object event);
  Future<void> broadcast(Object event);
}

class DianaEventBus implements DianaEventPublisher {
  void on<T extends Object>(FutureOr<void> Function(T event) listener) {}

  @override
  Future<void> publish(Object event) async {}

  @override
  Future<void> broadcast(Object event) async {}
}
''',
  'diana|lib/src/codec.dart': '''
abstract interface class BodyCodec {
  List<String> get mimeTypes;
  Object? decode(String body);
  String encode(Object? value);
}
''',
  'diana|lib/src/sse.dart': '''
class ServerSentEvent {
  final String data;
  final String? id;
  final String? event;
  final int? retryMs;
  const ServerSentEvent(this.data, {this.id, this.event, this.retryMs});
  ServerSentEvent.json(Object? data, {this.id, this.event, this.retryMs})
      : data = '';
}
''',
  'diana|lib/src/websocket.dart': '''
import 'dart:async';

sealed class WebSocketMessage {}

final class TextMessage extends WebSocketMessage {
  final String text;
  TextMessage(this.text);
}

abstract interface class WebSocketSession {
  bool sendText(String text);
}

abstract interface class WebSocketHandler {
  FutureOr<void> onOpen(WebSocketSession session);
  FutureOr<void> onMessage(WebSocketSession session, WebSocketMessage message);
  FutureOr<void> onError(
      WebSocketSession session, Object error, StackTrace stackTrace);
  FutureOr<void> onClose(WebSocketSession session, int? code, String? reason);
}

abstract class BaseWebSocketHandler implements WebSocketHandler {
  const BaseWebSocketHandler();

  @override
  FutureOr<void> onOpen(WebSocketSession session) {}

  @override
  FutureOr<void> onMessage(
      WebSocketSession session, WebSocketMessage message) {}

  @override
  FutureOr<void> onError(
      WebSocketSession session, Object error, StackTrace stackTrace) {}

  @override
  FutureOr<void> onClose(
      WebSocketSession session, int? code, String? reason) {}
}
''',
  'diana|lib/src/http/request.dart': '''
class DianaRequest {}
''',
  'diana|lib/src/http/response.dart': '''
class DianaResponse {
  const DianaResponse({int statusCode = 200});

  DianaResponse.json(Object? data, {int statusCode = 200});
}
''',
  'diana|lib/src/middleware.dart': '''
import 'dart:async';

import 'http/request.dart';
import 'http/response.dart';

typedef DianaHandler = FutureOr<DianaResponse> Function(DianaRequest request);
typedef Next = FutureOr<DianaResponse> Function(DianaRequest request);

abstract interface class Middleware {
  FutureOr<DianaResponse> handle(DianaRequest request, Next next);
}
''',
};
