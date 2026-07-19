/// The STOMP 1.2 broker and endpoint base — an in-memory topic broker over
/// Diana's WebSocket support. One [StompBroker] (framework-owned singleton)
/// serves every connection of every [StompEndpoint]; topic publishes fan out
/// across isolates through [DianaEventBus.broadcast].
library;

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:math' as math;

import '../binding.dart' show principalAttributeKey;
import '../config.dart';
import '../events.dart';
import '../websocket.dart';
import 'frame.dart';

/// Publishes messages to STOMP destinations. Inject it into any provider to
/// push to subscribers from server-side code.
abstract interface class StompPublisher {
  /// Publishes [body] to [destination]; every subscriber of that exact
  /// destination (on any isolate) receives a MESSAGE frame.
  Future<void> publish(
    String destination,
    String body, {
    Map<String, String> headers = const {},
    String contentType = 'text/plain',
  });
}

/// Cross-isolate relay envelope — plain sendable data broadcast through the
/// event bus so subscribers on other isolates receive the message.
final class StompRelayEvent {
  final String destination;
  final String body;
  final Map<String, String> headers;

  const StompRelayEvent(this.destination, this.body, this.headers);
}

/// The context passed to a `@MessageMapping` handler (optional 2nd param).
class StompMessage {
  /// Destination as the client sent it (including the app prefix).
  final String destination;
  final Map<String, String> headers;
  final String body;
  final String sessionId;

  /// The authenticated principal from the handshake, or `null`.
  final Object? principal;

  const StompMessage({
    required this.destination,
    required this.headers,
    required this.body,
    required this.sessionId,
    required this.principal,
  });
}

/// Base class for a STOMP endpoint: a singleton `@WebSocketController` that
/// delegates every WebSocket callback to the injected [StompBroker].
///
/// ```dart
/// @WebSocketController('/stomp')
/// class AppStomp extends StompEndpoint { AppStomp(super.broker); }
/// ```
abstract class StompEndpoint implements WebSocketHandler {
  final StompBroker broker;

  StompEndpoint(this.broker);

  @override
  void onOpen(WebSocketSession session) => broker.onOpen(session);

  @override
  void onMessage(WebSocketSession session, WebSocketMessage message) =>
      broker.onMessage(session, message);

  @override
  void onError(WebSocketSession session, Object error, StackTrace stackTrace) =>
      broker.onError(session, error, stackTrace);

  @override
  void onClose(WebSocketSession session, int? code, String? reason) =>
      broker.onClose(session, code, reason);
}

enum _AckMode { auto, client, clientIndividual }

/// Raised for a protocol precondition violation; caught and turned into an
/// ERROR frame + connection close.
class _StompProtocol implements Exception {
  final String message;
  const _StompProtocol(this.message);
}

class _Subscription {
  final String id;
  final String destination;
  final _AckMode ack;
  final Queue<_PendingAck> pending = Queue();

  _Subscription(this.id, this.destination, this.ack);
}

class _PendingAck {
  final String ackId;
  final _Subscription sub;
  _PendingAck(this.ackId, this.sub);
}

class _Session {
  final WebSocketSession ws;
  Future<void> tail = Future<void>.value();
  bool connected = false;
  final Map<String, _Subscription> subs = {};
  final Map<String, List<StompFrame>> txs = {};
  final Map<String, _PendingAck> pendingById = {};
  Timer? outgoingHb;
  Timer? watchdog;
  int watchdogMs = 0;
  int seq = 0;

  _Session(this.ws);
}

/// The in-memory STOMP broker.
class StompBroker implements StompPublisher {
  final DianaEventBus _bus;
  final void Function(Object error, StackTrace stackTrace) _onError;

  final String _appPrefix;
  final int _serverHeartbeatMs;

  final Map<String, _Session> _sessions = {};
  final Map<String, Set<_Subscription>> _byDestination = {};
  final Map<String, _Mapping> _mappings = {};

  StompBroker(
    DianaEventBus bus,
    DianaConfig config, {
    void Function(Object error, StackTrace stackTrace)? onError,
  })  : _bus = bus,
        _onError = onError ?? _defaultOnError,
        _appPrefix = config.get<String>('stomp.appPrefix',
            defaultValue: '/app'),
        _serverHeartbeatMs =
            config.get<int>('stomp.heartbeatMs', defaultValue: 10000) {
    // Registered up front so remote broadcasts are delivered locally.
    _bus.on<StompRelayEvent>(_fanOutLocal);
  }

  /// Registers a `@MessageMapping` handler for [destination] (without the
  /// app prefix). Called from generated code.
  void registerMapping(
    String destination,
    FutureOr<Object?> Function(StompMessage message) handler, {
    String? sendTo,
    String Function(Object? result)? encode,
  }) {
    _mappings[destination] = _Mapping(handler, sendTo, encode);
  }

  @override
  Future<void> publish(
    String destination,
    String body, {
    Map<String, String> headers = const {},
    String contentType = 'text/plain',
  }) async {
    final merged = {'content-type': contentType, ...headers};
    await _bus.broadcast(StompRelayEvent(destination, body, merged));
  }

  // ---- WebSocket callbacks (delegated from StompEndpoint) ----

  void onOpen(WebSocketSession session) {
    _sessions[session.id] = _Session(session);
  }

  void onMessage(WebSocketSession session, WebSocketMessage message) {
    final s = _sessions[session.id];
    if (s == null) return;
    _armWatchdog(s); // any inbound traffic resets the liveness watchdog
    final bytes = message is TextMessage
        ? utf8.encode(message.text)
        : (message as BinaryMessage).data;
    s.tail = s.tail.then((_) => _process(s, bytes));
  }

  void onError(WebSocketSession session, Object error, StackTrace stackTrace) {
    _cleanup(_sessions[session.id]);
  }

  void onClose(WebSocketSession session, int? code, String? reason) {
    _cleanup(_sessions[session.id]);
  }

  // ---- frame processing ----

  Future<void> _process(_Session s, List<int> bytes) async {
    List<StompFrame> frames;
    try {
      frames = parseStompChunk(bytes);
    } on StompParseException catch (e) {
      await _fail(s, e.message);
      return;
    }
    for (final frame in frames) {
      if (!_sessions.containsKey(s.ws.id)) return; // closed mid-batch
      try {
        await _handle(s, frame);
      } on _StompProtocol catch (e) {
        await _fail(s, e.message, receiptId: frame.headers['receipt']);
        return;
      } on StompPayloadException catch (e) {
        await _fail(s, e.message, receiptId: frame.headers['receipt']);
        return;
      } catch (error, st) {
        _onError(error, st);
        await _fail(s, 'message handler failed',
            receiptId: frame.headers['receipt']);
        return;
      }
    }
  }

  Future<void> _handle(_Session s, StompFrame frame) async {
    if (!s.connected && frame.command != 'CONNECT' && frame.command != 'STOMP') {
      throw const _StompProtocol(
          'not connected: first frame must be CONNECT or STOMP');
    }
    switch (frame.command) {
      case 'CONNECT':
      case 'STOMP':
        _handleConnect(s, frame);
      case 'SUBSCRIBE':
        _handleSubscribe(s, frame);
        _receipt(s, frame);
      case 'UNSUBSCRIBE':
        _handleUnsubscribe(s, frame);
        _receipt(s, frame);
      case 'SEND':
        await _handleSend(s, frame);
        _receipt(s, frame);
      case 'ACK':
        _handleAck(s, frame, nack: false);
        _receipt(s, frame);
      case 'NACK':
        _handleAck(s, frame, nack: true);
        _receipt(s, frame);
      case 'BEGIN':
        _handleBegin(s, frame);
        _receipt(s, frame);
      case 'COMMIT':
        await _handleCommit(s, frame);
        _receipt(s, frame);
      case 'ABORT':
        _handleAbort(s, frame);
        _receipt(s, frame);
      case 'DISCONNECT':
        _receipt(s, frame);
        await _disconnect(s);
      default:
        throw _StompProtocol('unexpected command ${frame.command}');
    }
  }

  void _handleConnect(_Session s, StompFrame frame) {
    if (s.connected) throw const _StompProtocol('already connected');
    if (frame.headers.containsKey('receipt')) {
      throw const _StompProtocol('receipt is not allowed on CONNECT');
    }
    final accept = frame.headers['accept-version'] ?? '1.0';
    if (!accept.split(',').map((v) => v.trim()).contains('1.2')) {
      // Version-mismatch ERROR carries the supported `version` header; sent
      // directly (not via _fail) so the header is included, then the loop
      // stops because the session is gone.
      _send(s, const StompFrame('ERROR', {
        'version': '1.2',
        'content-type': 'text/plain',
        'message': 'unsupported protocol version: supported versions are 1.2',
      }, 'unsupported protocol version: supported versions are 1.2'));
      _cleanup(s);
      unawaited(s.ws.close(4002, 'STOMP protocol error'));
      return;
    }
    // Heartbeat negotiation: heart-beat:<cx>,<cy>.
    var cx = 0, cy = 0;
    final hb = frame.headers['heart-beat'];
    if (hb != null) {
      final match = RegExp(r'^(\d+),(\d+)$').firstMatch(hb);
      if (match == null) {
        throw _StompProtocol('invalid heart-beat header "$hb"');
      }
      cx = int.parse(match.group(1)!);
      cy = int.parse(match.group(2)!);
    }
    s.connected = true;
    _startHeartbeats(s, clientTx: cx, clientRx: cy);
    _send(s, StompFrame('CONNECTED', {
      'version': '1.2',
      'heart-beat': '$_serverHeartbeatMs,$_serverHeartbeatMs',
      'session': s.ws.id,
    }));
  }

  void _handleSubscribe(_Session s, StompFrame frame) {
    final destination = _require(frame, 'destination', 'SUBSCRIBE');
    final id = _require(frame, 'id', 'SUBSCRIBE');
    if (s.subs.containsKey(id)) {
      throw _StompProtocol('duplicate subscription id "$id"');
    }
    final ackHeader = frame.headers['ack'] ?? 'auto';
    final ack = switch (ackHeader) {
      'auto' => _AckMode.auto,
      'client' => _AckMode.client,
      'client-individual' => _AckMode.clientIndividual,
      _ => throw _StompProtocol('invalid ack mode "$ackHeader"'),
    };
    final sub = _Subscription(id, destination, ack);
    s.subs[id] = sub;
    _byDestination.putIfAbsent(destination, () => {}).add(sub);
  }

  void _handleUnsubscribe(_Session s, StompFrame frame) {
    final id = _require(frame, 'id', 'UNSUBSCRIBE');
    final sub = s.subs.remove(id);
    if (sub == null) throw _StompProtocol('unknown subscription id "$id"');
    _byDestination[sub.destination]?.remove(sub);
    for (final entry in sub.pending) {
      s.pendingById.remove(entry.ackId);
    }
  }

  Future<void> _handleSend(_Session s, StompFrame frame) async {
    final tx = frame.headers['transaction'];
    if (tx != null) {
      _buffer(s, tx, frame);
      return;
    }
    _require(frame, 'destination', 'SEND');
    await _doSend(s, frame);
  }

  Future<void> _doSend(_Session s, StompFrame frame) async {
    final destination = frame.headers['destination']!;
    if (destination == _appPrefix || destination.startsWith('$_appPrefix/')) {
      final mappingDest = destination.substring(_appPrefix.length);
      final mapping = _mappings[mappingDest];
      if (mapping == null) {
        _onError(
            StateError('no @MessageMapping for destination "$destination"'),
            StackTrace.current);
        return; // Spring drops unmapped app-prefixed sends
      }
      final message = StompMessage(
        destination: destination,
        headers: frame.headers,
        body: frame.body,
        sessionId: s.ws.id,
        principal: s.ws.attributes[principalAttributeKey],
      );
      final result = await mapping.handler(message);
      final sendTo = mapping.sendTo;
      if (sendTo != null && result != null) {
        final body = mapping.encode != null ? mapping.encode!(result) : '$result';
        await publish(sendTo, body);
      }
      return;
    }
    // Broker destination: fan out to subscribers (passing user headers).
    final userHeaders = {
      for (final e in frame.headers.entries)
        if (e.key != 'destination' &&
            e.key != 'content-length' &&
            e.key != 'receipt')
          e.key: e.value,
    };
    await publish(destination, frame.body,
        headers: userHeaders,
        contentType: frame.headers['content-type'] ?? 'text/plain');
  }

  void _handleAck(_Session s, StompFrame frame, {required bool nack}) {
    final tx = frame.headers['transaction'];
    if (tx != null) {
      if (!s.txs.containsKey(tx)) throw _StompProtocol('unknown transaction "$tx"');
      _buffer(s, tx, frame);
      return;
    }
    _applyAck(s, frame, nack: nack);
  }

  void _applyAck(_Session s, StompFrame frame, {required bool nack}) {
    final id = _require(frame, 'id', nack ? 'NACK' : 'ACK');
    final entry = s.pendingById[id];
    if (entry == null) throw _StompProtocol('unknown ack id "$id"');
    final sub = entry.sub;
    if (sub.ack == _AckMode.clientIndividual) {
      sub.pending.remove(entry);
      s.pendingById.remove(id);
    } else {
      // Cumulative: this message and every earlier one in the subscription.
      while (sub.pending.isNotEmpty) {
        final head = sub.pending.removeFirst();
        s.pendingById.remove(head.ackId);
        if (identical(head, entry)) break;
      }
    }
    if (nack) {
      _onError(StateError('NACK for message "$id" (no redelivery)'),
          StackTrace.current);
    }
  }

  void _handleBegin(_Session s, StompFrame frame) {
    final tx = _require(frame, 'transaction', 'BEGIN');
    if (s.txs.containsKey(tx)) {
      throw _StompProtocol('transaction "$tx" already begun');
    }
    s.txs[tx] = [];
  }

  Future<void> _handleCommit(_Session s, StompFrame frame) async {
    final tx = _require(frame, 'transaction', 'COMMIT');
    final buffered = s.txs.remove(tx);
    if (buffered == null) throw _StompProtocol('unknown transaction "$tx"');
    for (final f in buffered) {
      if (f.command == 'SEND') {
        await _doSend(s, f);
      } else {
        _applyAck(s, f, nack: f.command == 'NACK');
      }
    }
  }

  void _handleAbort(_Session s, StompFrame frame) {
    final tx = _require(frame, 'transaction', 'ABORT');
    if (s.txs.remove(tx) == null) {
      throw _StompProtocol('unknown transaction "$tx"');
    }
  }

  void _buffer(_Session s, String tx, StompFrame frame) {
    final buffered = s.txs[tx];
    if (buffered == null) throw _StompProtocol('unknown transaction "$tx"');
    buffered.add(frame);
  }

  // ---- delivery ----

  void _fanOutLocal(StompRelayEvent event) {
    final subs = _byDestination[event.destination];
    if (subs == null || subs.isEmpty) return;
    for (final sub in subs.toList()) {
      final session = _sessionOf(sub);
      if (session == null) continue;
      final headers = <String, String>{
        'destination': event.destination,
        'message-id': '${session.ws.id}-${session.seq++}',
        'subscription': sub.id,
        ...event.headers,
      };
      if (sub.ack != _AckMode.auto) {
        final ackId = '${session.ws.id}-a${session.seq++}';
        headers['ack'] = ackId;
        final pending = _PendingAck(ackId, sub);
        sub.pending.add(pending);
        session.pendingById[ackId] = pending;
      }
      headers['content-length'] =
          '${utf8.encode(event.body).length}';
      final ok =
          session.ws.sendText(serializeStompFrame(StompFrame('MESSAGE', headers, event.body)));
      if (!ok) _cleanup(session);
    }
  }

  _Session? _sessionOf(_Subscription sub) {
    for (final session in _sessions.values) {
      if (session.subs[sub.id] == sub) return session;
    }
    return null;
  }

  // ---- heartbeats ----

  void _startHeartbeats(_Session s, {required int clientTx, required int clientRx}) {
    final serverMs = _serverHeartbeatMs;
    // server → client
    final outgoing = (serverMs == 0 || clientRx == 0)
        ? 0
        : math.max(serverMs, clientRx);
    if (outgoing > 0) {
      s.outgoingHb = Timer.periodic(Duration(milliseconds: outgoing), (_) {
        if (!s.ws.sendText(stompHeartbeat)) _cleanup(s);
      });
    }
    // client → server
    final incoming = (clientTx == 0 || serverMs == 0)
        ? 0
        : math.max(clientTx, serverMs);
    s.watchdogMs = incoming;
    _armWatchdog(s);
  }

  void _armWatchdog(_Session s) {
    if (s.watchdogMs <= 0) return;
    s.watchdog?.cancel();
    s.watchdog = Timer(Duration(milliseconds: 2 * s.watchdogMs), () {
      _onError(
          StateError('STOMP heartbeat timeout on session ${s.ws.id}'),
          StackTrace.current);
      unawaited(s.ws.close(4000, 'heartbeat timeout'));
      _cleanup(s);
    });
  }

  // ---- shutdown / cleanup ----

  Future<void> _disconnect(_Session s) async {
    _cleanup(s);
    await s.ws.close(1000);
  }

  Future<void> _fail(_Session s, String message, {String? receiptId}) async {
    final headers = {
      'message': message,
      'content-type': 'text/plain',
      if (receiptId != null) 'receipt-id': receiptId,
    };
    _send(s, StompFrame('ERROR', headers, message));
    _cleanup(s);
    await s.ws.close(4002, 'STOMP protocol error');
  }

  void _cleanup(_Session? s) {
    if (s == null) return;
    s.outgoingHb?.cancel();
    s.watchdog?.cancel();
    for (final sub in s.subs.values) {
      _byDestination[sub.destination]?.remove(sub);
    }
    s.subs.clear();
    s.txs.clear();
    s.pendingById.clear();
    _sessions.remove(s.ws.id);
  }

  // ---- helpers ----

  void _send(_Session s, StompFrame frame) => s.ws.sendText(serializeStompFrame(frame));

  void _receipt(_Session s, StompFrame frame) {
    final receipt = frame.headers['receipt'];
    if (receipt != null) {
      _send(s, StompFrame('RECEIPT', {'receipt-id': receipt}));
    }
  }

  String _require(StompFrame frame, String header, String command) {
    final value = frame.headers[header];
    if (value == null) {
      throw _StompProtocol(
          'missing required header "$header" for $command');
    }
    return value;
  }

  static void _defaultOnError(Object error, StackTrace stackTrace) {
    // ignore: avoid_print
    print('[diana] STOMP: $error');
  }
}

class _Mapping {
  final FutureOr<Object?> Function(StompMessage message) handler;
  final String? sendTo;
  final String Function(Object? result)? encode;
  _Mapping(this.handler, this.sendTo, this.encode);
}
