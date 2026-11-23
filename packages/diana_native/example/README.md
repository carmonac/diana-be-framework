# diana_native example

```yaml
dependencies:
  diana: ^0.16.0
  diana_native: ^0.16.0
```

Register one `DianaNativeEngine` subclass. The generator discovers it and
the server binds through relic_native's Zig HTTP server:

```dart
import 'package:diana/diana.dart';
import 'package:diana_native/diana_native.dart';

@Component()
class AppEngine extends DianaNativeEngine {
  AppEngine()
      : super(
          options: const NativeOptions(
            maxConnections: 10000,
            idleTimeout: Duration(seconds: 30),
          ),
        );
}
```

```bash
dart build cli -t bin/server.dart -o build
./build/bundle/bin/server
# [diana] Listening on http://0.0.0.0:8080 (engine: native)
```
