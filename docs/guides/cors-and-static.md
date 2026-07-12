# CORS and static files

## CORS

Two ways to enable it; both include automatic `OPTIONS` preflight routes.

**Globally**, from configuration:

```yaml
server:
  cors:
    enabled: true
    allowedOrigins: ["https://app.example"]   # default ['*']
    # allowedMethods: [GET, POST]             # default: methods on the path
    allowedHeaders: ["*"]                     # '*' echoes the preflight
    exposedHeaders: []
    allowCredentials: false
    maxAge: 3600                              # preflight cache, seconds
```

**Per controller or route**, with `@CrossOrigin` (same fields, camelCase):

```dart
@RestController('/info')
@CrossOrigin(origins: ['https://dashboard.example'])
class InfoController { ... }
```

Semantics:

- Route annotation **replaces** controller annotation **replaces** global
  config — whole-policy replacement, no field merging.
- `@CrossOrigin` enables CORS on its routes even when the global config is
  disabled.
- Disallowed origins simply get no CORS headers (the browser blocks); a
  valid preflight answers 204 with `Access-Control-Allow-*` headers and
  `Vary: Origin`.
- With `allowCredentials: true`, a `*` origin list echoes the caller's
  origin (the spec forbids literal `*` with credentials).
- Registering your own `OPTIONS` route on a path suppresses the automatic
  preflight for it.

## Static files

Serve a directory through the engine's hardened static handler (ETag,
Range/conditional requests, path-traversal protection):

```yaml
server:
  static:
    enabled: true
    dir: public          # filesystem directory
    prefix: /static      # URL prefix
    index: index.html    # served on directory hits
    spa: false           # true: serve index on ANY miss under the prefix
    cacheMaxAge: 3600    # Cache-Control max-age, seconds
```

- `GET /static/…` and `HEAD` are served from `dir`; anything outside the
  prefix is untouched, so API routes coexist.
- `spa: true` turns misses under the prefix into `index.html` — client-side
  routers (Flutter web, React) work unhydrated.
- Purely a runtime feature — no annotations, no codegen; `DianaServer`
  mounts it during `serve()` when enabled.
