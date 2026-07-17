# Configuration keys reference

Every key Diana itself reads. All keys are overridable via environment
variables (`server.port` ← `SERVER_PORT`; dots and dashes become
underscores). Your application adds its own keys freely (`@Value`,
`@ConfigurationProperties`, `config.get`).

## Server

| Key | Default | Meaning |
|---|---|---|
| `server.host` | `0.0.0.0` | Bind address (`localhost`, `::`, IP literal) |
| `server.port` | `8080` | Port (`serve(port: 0)` for ephemeral in tests) |
| `server.isolates` | `1` | Worker isolates (experimental; see [operations](../guides/operations.md#multi-isolate-serving-experimental)) |

## TLS

| Key | Default | Meaning |
|---|---|---|
| `server.ssl.certPath` | — | Certificate chain (PEM). Set together with `keyPath` |
| `server.ssl.keyPath` | — | Private key (PEM) |
| `server.ssl.keyPassword` | — | Key password, if any |

## CORS (`server.cors.*`)

| Key | Default | Meaning |
|---|---|---|
| `enabled` | `false` | Global CORS on every route |
| `allowedOrigins` | `['*']` | Allowed origins |
| `allowedMethods` | registered methods | Preflight allow-methods |
| `allowedHeaders` | `['*']` | `*` echoes the preflight request |
| `exposedHeaders` | `[]` | `Access-Control-Expose-Headers` |
| `allowCredentials` | `false` | Credentials; `*` origins then echo |
| `maxAge` | `3600` | Preflight cache (seconds) |

## Static files (`server.static.*`)

| Key | Default | Meaning |
|---|---|---|
| `enabled` | `false` | Mount the static handler |
| `dir` | `public` | Directory to serve |
| `prefix` | `/static` | URL prefix |
| `index` | `index.html` | Served on directory hits |
| `spa` | `false` | Serve index on any miss under the prefix |
| `cacheMaxAge` | `3600` | `Cache-Control: max-age` (seconds) |

## Bodies

| Key | Default | Meaning |
|---|---|---|
| `server.maxBodyBytes` | `10485760` (10 MiB) | Request body limit for non-multipart bodies (JSON, forms, raw `String`, custom codecs); exceeding ⇒ 413. `0` disables |
| `server.multipart.maxSize` | `10485760` (10 MiB) | Multipart body limit (raw stream, including part headers); exceeding ⇒ 413. Replaces `server.maxBodyBytes` for `multipart/form-data` requests |

## Server-Sent Events

| Key | Default | Meaning |
|---|---|---|
| `server.sse.heartbeatSeconds` | `15` | Keep-alive comment interval on SSE streams; `0` disables |

## gRPC (`grpc.*`, with `package:diana_grpc`)

| Key | Default | Meaning |
|---|---|---|
| `grpc.enabled` | `true` | Serve `@GrpcService` classes (`false` skips serving) |
| `grpc.host` | `0.0.0.0` | gRPC bind address |
| `grpc.port` | `9090` | gRPC port (`0` for ephemeral in tests) |

gRPC serving requires `server.isolates: 1` — see the
[gRPC guide](../guides/grpc.md#limitations-v03).

## OpenAPI (`server.openapi.*`)

| Key | Default | Meaning |
|---|---|---|
| `enabled` | `false` | Serve `GET /openapi.json` |
| `title` | `Diana application` | Patched into `info.title` |
| `version` | `0.0.0` | Patched into `info.version` |

## Actuator

| Key | Default | Meaning |
|---|---|---|
| `management.enabled` | `false` | Serve `/actuator/health` and `/actuator/info` |
| `info.*` | — | Free-form section served by `/actuator/info` |

## Authentication (`auth.*`, with `package:diana_auth`)

`diana_auth` reads no keys directly; your `AuthenticationMiddleware` pulls
them via `@Value`. Conventional keys:

| Key | Default | Meaning |
|---|---|---|
| `auth.jwt.secret` | — | HS256 signing/verification secret (env `AUTH_JWT_SECRET`) |

See the [auth guide](../guides/auth.md).

## Persistence (`db.*`, with `package:diana_data`)

| Key | Default | Meaning |
|---|---|---|
| `db.migrations.dir` | — | Directory of `*.sql` migrations applied on startup (opt-in) |
| `db.*` | — | Whatever your `DatabaseConnector` reads (host, file, credentials, …) |

See the [persistence guide](../guides/persistence.md).

## Observability (`observability.*`, with `package:diana_observability`)

| Key | Default | Meaning |
|---|---|---|
| `observability.tracing.endpoint` | — | OTLP collector URL; empty/unset disables tracing (metrics still work) |
| `observability.tracing.serviceName` | `diana` | `service.name` resource attribute |

`/actuator/metrics` and the liveness/readiness probes are gated by
`management.enabled` (see [Actuator](#actuator)). See the
[observability guide](../guides/observability.md).

## Profiles

| Key / variable | Meaning |
|---|---|
| `DIANA_PROFILE` (env) | Comma-separated active profiles; replaces `diana.profile` |
| `diana.profile` | Active profiles from the base file |

Applied as overlays: `application.yaml` → `application-{profile}.yaml` (in
order) → environment variables.
