# Troubleshooting & FAQ

## Build problems

### "Missing the part directive"

```
ctrl.dart declares Diana members that need generated code, but is missing
the part directive. Add:

part 'ctrl.diana.dart';
```

Paste the printed line into the named file, after the imports. Needed by
libraries with controllers, constrained DTOs or `@ConfigurationProperties`
classes.

### The analyzer shows errors in `*.diana.dart` / `*.diana_app.dart`

Generated files can be stale after you rename or delete things. Re-run:

```bash
dart run build_runner build
```

If the errors persist, the build log contains the real diagnostic (severe
messages fail the build) — look it up in the
[build diagnostics reference](reference/build-diagnostics.md).

### `runDiana` / `buildDianaServer` doesn't exist

- Is there exactly one `@DianaApplication` class under `lib/` ?
- Did the build actually run without severe errors?
- Import path: `package:<your_app>/<file>.diana_app.dart`, where `<file>`
  is the library containing `@DianaApplication` (`app.dart` →
  `app.diana_app.dart`).

### Stale results / weird incremental behaviour

```bash
dart run build_runner clean
dart run build_runner build
```

### My DTO fails with "has no factory X.fromJson" but it has one

Check the exact shape: it must accept a single positional
`Map<String, dynamic>`. With json_serializable, make sure the DTO's
`part 'x.g.dart';` file generated (json_serializable must be in
`dev_dependencies`).

### Types behind an import prefix break generated code

If a controller imports its DTOs with `import '...' as dto;`, generated
adapters (which reproduce type names without prefixes) won't compile.
Import route-signature types without prefixes in controller libraries.
(Tracked as a known limitation.)

## Runtime problems

### The app exits with `ConfigException` at startup

By design: a `@Value` without default or a required
`@ConfigurationProperties` key is missing. The message names the key *and*
the environment variable that can supply it:

```
ConfigException: Missing required config key "app.apiKey"
(checked the YAML config file and environment variable "APP_APIKEY").
```

### My `application.yaml` seems to be ignored

- It's resolved against the **working directory** of the process, not the
  package root. Run the server from the directory containing it (or pass a
  path in `@DianaApplication(configFile: ...)`).
- Environment variables silently win over file values — check
  `SERVER_PORT` & friends if a value "won't change".

### Every response is 404

The route path is controller path + method path: `@RestController('/todos')`
plus `@Get('/:id')` serves `/todos/:id`, not `/:id`. The generated
`buildDianaServer()` in `*.diana_app.dart` lists every registered route —
read it, it's short.

### I return an object and get a 500

If the object's `toJson()` itself throws (or a nested object lacks
`toJson()`), serialization fails at runtime. Nested custom types inside
Maps/Lists are only checked one level deep at build time.

### Port already in use

Another process owns 8080. `SERVER_PORT=0 dart run bin/server.dart` binds a
free one, or set `server.port`.

## FAQ

**Why compile-time DI instead of a runtime container?**
Wiring errors surface in CI instead of production, startup does zero
resolution work, the generated context is plain debuggable Dart, and
tree-shaking keeps working because there's no reflection.

**Does Diana use `dart:mirrors` or macros?**
Neither. Mirrors are unusable for AOT; Dart macros were discontinued. Diana
generates code with `build_runner`, like riverpod or json_serializable.

**Can I use it with Flutter?**
Diana is a *server-side* framework (it binds sockets via `dart:io`). Share
DTOs between a Diana backend and a Flutter app by putting them in a common
package.

**How do I override a dependency in tests?**
Prefer testing layers directly (construct services by hand, or use
`buildDianaServer(config: ...)` for e2e). Provider substitution/overrides
is on the roadmap.

**Can two apps live in one package?**
No — one `@DianaApplication` per package (build error otherwise). Use
separate packages in the workspace.

**Is there hot reload?**
Yes: `dart run build_runner watch` + `dart run --enable-vm-service
bin/server.dart`. Handler bodies hot-reload; DI-graph changes need a
restart because the composition root is rewritten.

**Which HTTP methods are supported?**
`@Get/@Post/@Put/@Delete/@Patch`, plus `@HttpRoute('HEAD', ...)` /
`@HttpRoute('OPTIONS', ...)` for the rest.

**Where do I report bugs or propose features?**
Open an issue in the repository — and read
[Architecture](architecture.md) first if you'd like to contribute a fix.
