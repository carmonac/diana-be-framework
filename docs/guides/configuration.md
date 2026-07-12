# Configuration

Diana loads configuration from a YAML file and lets **any** value be
overridden through environment variables — the standard pattern for
containerized deployments. Configuration is injected at startup: a missing
required key fails the boot, not the first request.

## Sources and precedence

1. **Environment variables** (highest)
2. **The YAML file** named by `@DianaApplication(configFile: ...)` —
   default `application.yaml`, resolved against the working directory

A missing YAML file is fine: the app runs on environment variables and
defaults alone.

## The YAML file

```yaml
server:
  host: 0.0.0.0
  port: 8080

app:
  apiKey: secret
  info:
    name: todo_api
    version: 1.0.0
```

Nested maps flatten to dot-separated keys: `server.port`,
`app.info.name`. Lists are kept as opaque values (scalar coercion only —
list-typed access is on the roadmap).

## Environment overrides

Every key maps to an environment variable: **upper-case, dots and dashes
become underscores**.

| Key | Variable |
|---|---|
| `server.port` | `SERVER_PORT` |
| `app.info.name` | `APP_INFO_NAME` |
| `app.api-key` | `APP_API_KEY` |

```bash
SERVER_PORT=9000 APP_INFO_NAME=prod dart run bin/server.dart
```

Environment values are strings and are coerced to the requested type on
read. Keys that exist *only* as environment variables work too.

## Server keys

The generated server reads these (all optional):

| Key | Default | Meaning |
|---|---|---|
| `server.host` | `0.0.0.0` | Bind address (`0.0.0.0`, `localhost`, `::`, or an IP literal) |
| `server.port` | `8080` | Port. `server.serve(port: 0)` in tests binds an ephemeral one |

## `@Value` — inject one key

Put `@Value` on a constructor parameter of any injectable class:

```dart
@Service()
class Greeter {
  Greeter(@Value('app.greeting', defaultValue: 'hello') this.greeting);
  final String greeting;
}
```

- The parameter type must be `String`, `int`, `double`, `bool` or `num`
  (build error otherwise).
- `defaultValue` must be a literal (`String`, `int`, `double` or `bool`).
- Without a default, the key is **required** — missing means the app fails
  at startup with a `ConfigException` naming the key *and* the environment
  variable that could satisfy it.

## `@ConfigurationProperties` — bind a section

Bind a whole configuration section to a typed class. The library needs a
`part` directive (a binder function is generated):

```dart
import 'package:diana/diana.dart';

part 'mail_props.diana.dart';

@ConfigurationProperties('app.mail')
class MailProps {
  final String host;      // ← app.mail.host (required)
  final int port;         // ← app.mail.port (required)
  final String? replyTo;  // ← app.mail.replyTo (optional)

  const MailProps({required this.host, required this.port, this.replyTo});
}
```

Rules:

- Every constructor parameter binds from `<prefix>.<paramName>`.
- Parameter types: `String`, `int`, `double`, `bool`, `num` — nullable
  makes the key optional (bound to `null` when absent).
- The class becomes an injectable **singleton**; depend on it anywhere:

```dart
@Service()
class Mailer {
  Mailer(this.props);
  final MailProps props;
}
```

## Type coercion

`DianaConfig.get<T>` coerces raw values (YAML scalars or env strings):

| Requested | Accepted raw values |
|---|---|
| `String` | anything (via `toString`) |
| `int` / `num` / `double` | numeric strings or YAML numbers |
| `bool` | `true`/`false`, `1`/`0`, `yes`/`no`, `on`/`off` (case-insensitive) |

An uncoercible value throws `ConfigException` with the key, the raw value
and its type.

## Using DianaConfig directly

The config object is available on the generated context (`ctx.config`) and
can be built by hand — the standard way to configure tests:

```dart
final config = DianaConfig({'server.port': 0, 'app.apiKey': 'test'});
final server = await buildDianaServer(config: config);
```

Full API (constructors, `load`, `get`, `contains`, `envNameFor`) in the
[runtime reference](../reference/runtime.md#dianaconfig).
