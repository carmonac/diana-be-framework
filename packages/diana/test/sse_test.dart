import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:diana/diana.dart';
import 'package:test/test.dart';

void main() {
  group('encodeSseEvent', () {
    test('frames id, event, retry and multi-line data per spec', () {
      expect(
        encodeSseEvent(const ServerSentEvent('hello')),
        'data: hello\n\n',
      );
      expect(
        encodeSseEvent(const ServerSentEvent(
          'line1\nline2',
          id: '7',
          event: 'update',
          retryMs: 3000,
        )),
        'id: 7\nevent: update\nretry: 3000\ndata: line1\ndata: line2\n\n',
      );
    });

    test('ServerSentEvent.json encodes the payload', () {
      final event = ServerSentEvent.json({'a': 1}, event: 'tick');
      expect(event.data, '{"a":1}');
      expect(encodeSseEvent(event), 'event: tick\ndata: {"a":1}\n\n');
    });
  });

  group('encodeSse', () {
    test('encodes the stream and closes with it', () async {
      final source = Stream.fromIterable(const [
        ServerSentEvent('one'),
        ServerSentEvent('two'),
      ]);
      final encoded = await encodeSse(source).transform(utf8.decoder).join();
      expect(encoded, 'data: one\n\ndata: two\n\n');
    });

    test('interleaves heartbeat comments', () async {
      final controller = StreamController<ServerSentEvent>();
      final chunks = <String>[];
      final subscription = encodeSse(controller.stream, heartbeatSeconds: 1)
          .transform(utf8.decoder)
          .listen(chunks.add);
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      controller.add(const ServerSentEvent('x'));
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await controller.close();
      await subscription.cancel();
      expect(chunks, contains(': keep-alive\n\n'));
      expect(chunks, contains('data: x\n\n'));
    });

    test('cancelling the encoded stream cancels the source', () async {
      final cancelled = Completer<void>();
      final source = StreamController<ServerSentEvent>(
        onCancel: cancelled.complete,
      );
      final subscription = encodeSse(source.stream).listen((_) {});
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await subscription.cancel();
      await cancelled.future.timeout(const Duration(seconds: 2));
    });
  });

  group('SSE over DianaServer', () {
    test('serves text/event-stream and cleans up on client disconnect',
        () async {
      final handlerCancelled = Completer<void>();
      final events = StreamController<ServerSentEvent>(
        onCancel: () {
          if (!handlerCancelled.isCompleted) handlerCancelled.complete();
        },
      );

      final server = DianaServer(
        config: DianaConfig({'server.sse.heartbeatSeconds': 1}),
      )..register(
          HttpMethod.get, '/events', (req) => sseResponse(req, events.stream));
      await server.serve(port: 0, quiet: true);
      addTearDown(server.close);

      final client = HttpClient();
      final request = await client
          .getUrl(Uri.parse('http://127.0.0.1:${server.port}/events'));
      final response = await request.close();
      expect(response.statusCode, 200);
      expect(response.headers.contentType?.mimeType, 'text/event-stream');
      expect(response.headers.value('cache-control'), 'no-cache');

      final received = <String>[];
      final subscription =
          response.transform(utf8.decoder).listen(received.add);
      events.add(const ServerSentEvent('first', id: '1'));
      events.add(ServerSentEvent.json({'n': 2}, event: 'num'));
      await Future<void>.delayed(const Duration(milliseconds: 300));

      final all = received.join();
      expect(all, contains('id: 1\ndata: first\n\n'));
      expect(all, contains('event: num\ndata: {"n":2}\n\n'));

      // Client disconnects mid-stream: the handler's source stream must be
      // cancelled (heartbeat acts as the write that detects the drop).
      await subscription.cancel();
      client.close(force: true);
      await handlerCancelled.future.timeout(const Duration(seconds: 5),
          onTimeout: () => fail('handler stream was not cancelled'));
    });

    test('hijacked head: real reason phrase, headers CRLF-sanitized', () async {
      final server = DianaServer()
        ..register(
          HttpMethod.get,
          '/stream',
          (req) => DianaResponse.stream(
            Stream.value(utf8.encode('hi')),
            statusCode: 201,
            mimeType: 'text/plain',
            headers: const {'x-meta': 'clean\r\ninjected: 1'},
          ),
        );
      await server.serve(port: 0, quiet: true);
      addTearDown(server.close);

      final socket = await Socket.connect('127.0.0.1', server.port!);
      socket.write('GET /stream HTTP/1.1\r\nhost: localhost\r\n\r\n');
      await socket.flush();
      final raw =
          utf8.decode(await socket.fold<List<int>>([], (a, b) => a..addAll(b)));
      socket.destroy();

      expect(raw, startsWith('HTTP/1.1 201 Created\r\n'));
      final head = raw.split('\r\n\r\n').first;
      expect(head, contains('x-meta: clean injected: 1'),
          reason: 'CR/LF in app-supplied header values must be stripped');
      expect(head.split('\r\n').where((l) => l.startsWith('injected')), isEmpty,
          reason: 'a header value must not be able to inject header lines');
    });

    test('zero-length chunks do not terminate the chunked framing', () async {
      final server = DianaServer()
        ..register(
          HttpMethod.get,
          '/stream',
          (req) => DianaResponse.stream(
            Stream.fromIterable(<List<int>>[
              utf8.encode('first'),
              const [], // must be skipped: 0\r\n\r\n is the terminator
              utf8.encode('second'),
            ]),
            mimeType: 'application/octet-stream',
          ),
        );
      await server.serve(port: 0, quiet: true);
      addTearDown(server.close);

      final client = HttpClient();
      addTearDown(client.close);
      final response = await (await client
              .getUrl(Uri.parse('http://127.0.0.1:${server.port}/stream')))
          .close();
      final body = await response.transform(utf8.decoder).join();
      expect(body, 'firstsecond');
    });

    test('a source error terminates the encoded stream (no live heartbeat)',
        () async {
      final source = StreamController<ServerSentEvent>();
      final out = encodeSse(source.stream, heartbeatSeconds: 1);
      final errors = <Object>[];
      var done = false;
      out.listen((_) {}, onError: errors.add, onDone: () => done = true);

      source.addError(StateError('source boom'));
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(errors, hasLength(1));
      expect(done, isTrue,
          reason: 'the stream must close after a source error — an open '
              'stream would keep the heartbeat writing forever');
      await source.close();
    });

    test('copyWith preserves the stream body (middleware compatibility)', () {
      final response = DianaResponse.stream(const Stream.empty(),
          mimeType: 'text/event-stream');
      final copied = response.copyWith(headers: {'x': 'y'});
      expect(copied.bodyStream, isNotNull);
      expect(copied.mimeType, 'text/event-stream');
    });

    test('accept guard lets text/event-stream through for */*', () {
      expect(acceptsMime('*/*', 'text/event-stream'), isTrue);
      expect(acceptsMime('text/event-stream', 'text/event-stream'), isTrue);
    });
  });
}
