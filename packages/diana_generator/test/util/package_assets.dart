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
class QueryBuilder {
  QueryBuilder table(String table) => this;
  QueryBuilder where(dynamic column, [dynamic op, dynamic value]) => this;
  QueryBuilder orWhere(dynamic column, [dynamic op, dynamic value]) => this;
  QueryBuilder whereIn(String column, dynamic values) => this;
  QueryBuilder whereNotIn(String column, dynamic values) => this;
  QueryBuilder orWhereNotIn(String column, List<dynamic> values) => this;
  QueryBuilder whereNull(String column) => this;
  QueryBuilder whereNotNull(String column) => this;
  QueryBuilder orWhereNull(String column) => this;
  QueryBuilder orWhereNotNull(String column) => this;
  QueryBuilder whereBetween(String column, List<dynamic> values) => this;
  QueryBuilder orWhereBetween(String column, List<dynamic> values) => this;
  QueryBuilder orderBy(String column, [String direction = 'asc']) => this;
  QueryBuilder limit(int value) => this;
  QueryBuilder insert(dynamic values) => this;
  QueryBuilder delete() => this;
  QueryBuilder count([dynamic column = '*']) => this;
}

class Database {
  QueryBuilder table(String table) => QueryBuilder();
  Future<List<Map<String, dynamic>>> select(QueryBuilder query) async => [];
  Future<List<Map<String, dynamic>>> insert(QueryBuilder query) async => [];
  Future<List<Map<String, dynamic>>> delete(QueryBuilder query) async => [];
  Future<T> runTransactional<T>(Future<T> Function() body) => body();
}

abstract class DatabaseConnector {
  Future<Object> connect(Object config);
  Future<void> close(Object connection);
}

abstract class DianaRepository<T> {
  final Database db;
  DianaRepository(this.db);
  Future<List<T>> findAll();
  Future<T?> findById(Object id);
  Future<void> save(T entity);
  Future<void> deleteById(Object id);
  Future<int> runCount(QueryBuilder query) async => 0;
  Future<bool> runExists(QueryBuilder query) async => false;
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

export 'src/aspects.dart';
export 'src/codec.dart';
export 'src/events.dart';
export 'src/http/request.dart';
export 'src/http/response.dart';
export 'src/middleware.dart';
export 'src/observer.dart';
export 'src/sse.dart';
export 'src/websocket.dart';
''',
  'diana|lib/src/aspects.dart': '''
import 'dart:async';

import 'observer.dart';

Future<T> runTimed<T>(
        DianaObserver? observer, String name, Future<T> Function() run) =>
    run();

class MethodCache<V> {
  MethodCache({required Duration ttl, required int maxEntries});
  Future<V> run(List<Object?> key, Future<V> Function() miss) => miss();
  void clear() {}
}

class RetryPolicy {
  const RetryPolicy(
      {int maxAttempts = 3,
      Duration backoff = Duration.zero,
      bool Function(Object error)? retryWhen});
  Future<T> run<T>(Future<T> Function() attempt) => attempt();
}

class CircuitBreakerPolicy {
  CircuitBreakerPolicy(
      {int failureThreshold = 5, Duration resetTimeout = Duration.zero});
  Future<T> run<T>(Future<T> Function() call) => call();
}

class CircuitOpenException implements Exception {
  const CircuitOpenException();
}

class CacheSpec {
  const CacheSpec(
      {required String method, required Duration ttl, required int maxEntries});
}

abstract class DianaCacheStore {
  const DianaCacheStore();
  Future<V> run<V>(
          CacheSpec spec, List<Object?> key, Future<V> Function() miss) =>
      miss();
  FutureOr<void> clear() {}
}

class InMemoryCacheStore extends DianaCacheStore {}
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
  FutureOr<T> observeTimedMethod<T>(String name, FutureOr<T> Function() run) =>
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
