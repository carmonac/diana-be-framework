# diana_native

Native HTTP engine for the [Diana framework](https://github.com/carmonac/diana-be-framework):
serves your app through [relic_native](https://pub.dev/packages/relic_native),
an HTTP server written in Zig, instead of `dart:io`. Routing, middleware,
SSE, WebSockets, static files, HTTPS and multi-isolate serving behave the
same.

```yaml
environment:
  sdk: ^3.10.0

dependencies:
  diana: ^0.16.0
  diana_native: ^0.16.0
```

```dart
import 'package:diana/diana.dart';
import 'package:diana_native/diana_native.dart';

@Component()
class AppEngine extends DianaNativeEngine {}
```

Build for production with `dart build cli` (not `dart compile exe`, which
does not run build hooks) and ship the whole bundle, native library
included.

Read the [native engine guide](https://carmonac.github.io/diana-be-framework/guides/native-engine/).
