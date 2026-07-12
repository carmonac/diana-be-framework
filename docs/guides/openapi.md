# OpenAPI

Diana generates an **OpenAPI 3.0 document at build time** from the same
single classification pass that generates your route adapters — the spec
cannot drift from the actual routes.

## Enabling

```yaml
server:
  openapi:
    enabled: true          # default false
    title: Todo API        # patched into info.title
    version: 1.2.3         # patched into info.version
```

The document is embedded in the generated code as a deterministic constant
and served at `GET /openapi.json` (guarded at runtime — toggling needs no
rebuild). Point Swagger UI or any OpenAPI tool at it.

## What's in the document

- **Paths and operations** for every `@RestController` route
  (`/todos/:id` → `/todos/{id}`), with `operationId`
  (`Controller_method`) and the controller name as tag.
- **Parameters** from `@PathParam`/`@QueryParam`/`@Header`: location,
  requiredness (nullable or defaulted ⇒ optional), primitive schema and
  default value.
- **Request bodies**: `$ref` to the DTO schema for `@Body()` DTOs (arrays
  for `List<Dto>`), `text/plain` for `String` bodies, `multipart/form-data`
  for `FormData`, unconstrained objects for raw `Map`/`List` bodies.
- **Responses** keyed by the effective status (`@ResponseStatus`, 204 for
  `void`) with the return schema.
- **Schemas** (`components/schemas`) for every `@Json` class and every
  validated DTO: property types (including `DateTime` → `string`/
  `date-time`, enums with their values, nested `$ref`s), `required` from
  non-nullable fields, and validation constraints mapped to
  `minLength`/`maxLength`/`minimum`/`maximum`/`pattern`/`format: email`
  (`@NotBlank`/`@NotEmpty` imply `minLength: 1`).

- **Content negotiation**: `@Consumes`/`@Produces` MIME lists are
  projected into `requestBody.content` and response `content` (same schema
  per MIME type); SSE routes (`Stream` returns) are documented as a `200`
  with `text/event-stream` content.

Best-effort areas (documented, not errors): DTOs that are neither `@Json`
nor validated (e.g. plain json_serializable classes) appear as unconstrained
`{}` schemas; `DianaResponse` returns have unspecified content.

## Branding

`info.title`/`info.version` are patched **at startup** from
`server.openapi.title`/`server.openapi.version` (via `patchOpenApiInfo`),
keeping the build-time constant deterministic while letting deployments
brand the spec.
