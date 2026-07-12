# todo_api

Complete example application for the [Diana framework](../../README.md):
REST controllers, compile-time DI, global + route middleware, YAML/env
configuration, DTO validation, `@ControllerAdvice` exception mapping,
WebSocket chat rooms, and json_serializable interop.

```bash
dart run build_runner build
dart run bin/server.dart
```

```bash
curl localhost:8080/todos
curl localhost:8080/todos/1
curl -X POST localhost:8080/todos -H 'Content-Type: application/json' \
     -d '{"title": "try diana"}'
curl -X POST localhost:8080/todos -H 'Content-Type: application/json' \
     -d '{"title": "   ", "priority": 9}'          # → 400 with field errors
curl -X DELETE localhost:8080/todos/1              # → 401 (missing API key)
curl -X DELETE localhost:8080/todos/1 -H 'X-Api-Key: secret'
curl localhost:8080/info                           # @ConfigurationProperties
SERVER_PORT=9000 dart run bin/server.dart          # env overrides yaml
```

WebSocket chat (rooms broadcast; try two terminals with
[wscat](https://github.com/websockets/wscat) or any WS client):

```bash
wscat -c ws://localhost:8080/ws/chat/dart
```

Run the end-to-end tests with `dart test`.
