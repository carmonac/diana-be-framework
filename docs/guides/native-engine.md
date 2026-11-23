# Native HTTP engine (`diana_native`)

Diana serves HTTP through [relic](https://pub.dev/packages/relic). By
default relic accepts connections with its `dart:io` adapter. The optional
[`diana_native`](../../packages/diana_native) package swaps in
[`relic_native`](https://pub.dev/packages/relic_native): an HTTP server
written in Zig that parses requests, keeps connections alive, terminates
TLS and frames WebSockets in native code. relic's benchmarks put it at
about **5x the requests per second** of `dart:io` over HTTP, and 5–10x
over HTTPS, with lower tail latency and less memory per idle WebSocket.

Only the transport changes. Routing, middleware, the exception boundary,
validation, SSE, WebSockets, STOMP, static files and multi-isolate serving
work the same, and the generated code stays the same apart from one
constructor argument.

## Enabling it

```yaml
# pubspec.yaml
environment:
  sdk: ^3.10.0

dependencies:
  diana: ^0.16.0
  diana_native: ^0.16.0
```

Register **one** `DianaNativeEngine` subclass as a singleton. The generator
discovers it by supertype and passes it to the server:

```dart
import 'package:diana/diana.dart';
import 'package:diana_native/diana_native.dart';

@Component()
class AppEngine extends DianaNativeEngine {}
```

The startup log names the engine:

```text
[diana] Listening on http://0.0.0.0:8080 (engine: native)
```

Remove the class (or the dependency) to go back to `dart:io`.

### Tuning

`NativeOptions` (re-exported from `relic_native`) holds the native server's
limits and timeouts:

```dart
@Component()
class AppEngine extends DianaNativeEngine {
  AppEngine()
      : super(
          options: const NativeOptions(
            maxConnections: 10000,
            idleTimeout: Duration(seconds: 30),
            maxInlineBody: 64 * 1024, // body read before the handler runs
          ),
        );
}
```

Diana's own limits (`server.maxBodyBytes`, `server.multipart.maxSize`) still
apply on top.

## Configuration

The engine reads the same `server.*` keys as the default one:

- `server.host` / `server.port` — the bind address.
- `server.ssl.certPath` / `keyPath` / `keyPassword` — HTTPS. The native
  server speaks **TLS 1.3 only** and accepts ECDSA, RSA or Ed25519 keys in
  PKCS#8, SEC 1 or PKCS#1 PEM form (an encrypted PKCS#8 key opens with
  `keyPassword`). Clients limited to TLS 1.2 cannot connect; terminate TLS
  at a proxy if you must serve them.
- `server.isolates` — every isolate joins one native server (a shared bind
  group per process, address and port), each driving it from its own
  thread. Throughput grows with the isolate count.

## Platforms

`relic_native` ships prebuilt libraries for Linux, macOS and Windows on x64
and arm64, so no Zig toolchain is needed. A Dart build hook bundles the
library: `dart run` and `dart test` work unchanged.

**Compiling for production:** `dart compile exe` does not support build
hooks and refuses to compile the app. Use `dart build cli` instead and ship
the whole output bundle — the executable in `bundle/bin/` loads the native
library from `bundle/lib/`:

```bash
dart build cli -t bin/server.dart -o build
# build/bundle/bin/server + build/bundle/lib/librelic_native.so
```

In a Dockerfile, copy `build/bundle/` as a directory rather than the single
executable.

On x64 the library needs AES-NI, PCLMULQDQ and AVX; on Linux and Windows
arm64, the ARMv8 crypto extensions.

The native engine speaks HTTP/1.0 and HTTP/1.1. The gain shows once the
server itself is the bottleneck, not the database or the handler. As a
rough guide, one isolate of a Diana app compiled with `dart build cli`
(Apple M-series, `wrk -c64`) went from 56k to 146k requests/s on a
plain-text route and from 39k to 71k on a 1 KB JSON route: Diana's own
pipeline (routing, middleware, error boundary, JSON encoding) is a larger
share of each request than in relic's bare benchmarks.

## Build-time checks

| Message | Fix |
|---|---|
| `Multiple DianaHttpEngine providers: A (lib), B (lib). Declare exactly one.` | Keep a single engine |
| `X extends DianaHttpEngine but is <scope>-scoped; HTTP engines must be singletons.` | Make the engine a singleton provider |

## Writing another engine

`DianaHttpEngine` (in `package:diana`) is the contract: `name` for the log,
and `bind(DianaEngineBinding)` returning a relic `Adapter`. It is typed
`Object` so relic stays out of Diana's public API; anything that is not a
relic `Adapter` fails at startup with a `StateError`. `diana_native` is the
reference implementation.
