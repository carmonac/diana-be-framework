# diana_generator example

Add the generator as a dev dependency next to the runtime; its builders
apply automatically to your package:

```yaml
dependencies:
  diana: ^0.15.1

dev_dependencies:
  build_runner: ^2.12.0
  diana_generator: ^0.15.1
```

Given this application:

```dart
// lib/app.dart — anchors the generated composition root
import 'package:diana/diana.dart';

@DianaApplication()
class MyApp {}
```

```dart
// lib/greeting_service.dart
import 'package:diana/diana.dart';

@Service()
class GreetingService {
  final String prefix;
  GreetingService(@Value('app.greeting', defaultValue: 'Hello') this.prefix);

  String greet(String name) => '$prefix, $name!';
}
```

```dart
// lib/hello_controller.dart
import 'package:diana/diana.dart';

import 'greeting_service.dart';

part 'hello_controller.diana.dart';

@RestController('/hello')
class HelloController {
  final GreetingService greetings; // injected at compile time
  HelloController(this.greetings);

  @Get()
  Map<String, dynamic> hello() => {'message': 'Hello from Diana!'};

  @Get('/:name')
  String greet(@PathParam() String name) => greetings.greet(name);
}
```

```dart
// bin/server.dart
import 'package:my_api/app.diana_app.dart';

Future<void> main() => runDiana();
```

```bash
dart run build_runner build   # emits *.diana.dart and app.diana_app.dart
dart run bin/server.dart      # [diana] Listening on http://0.0.0.0:8080
curl localhost:8080/hello/dart   # Hello, dart!
```

the generator emits `hello_controller.diana.dart` (the route adapters) and
`app.diana_app.dart` (the composition root with `runDiana()`). Missing
dependencies, ambiguous bindings and cycles are reported as build errors.

More complete, runnable apps live in the repository's
[examples](https://github.com/carmonac/diana-be-framework/tree/main/examples),
and the full documentation is at
<https://carmonac.github.io/diana-be-framework/>.
