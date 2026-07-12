# Content negotiation

By default every Diana route speaks JSON. Content negotiation lets a route
accept and produce other formats — XML out of the box, anything else via a
pluggable codec — without changing your DTOs or the validation pipeline.
Three pieces work together:

1. A **`BodyCodec`** translates between a wire format and the intermediate
   representation the DTO codecs already consume (`Map`/`List`/scalars).
2. **`@Consumes`** restricts which request content types a route accepts.
3. **`@Produces`** lists the response formats a route can produce; the
   first one the request's `Accept` header allows wins.

## Registering a codec

A codec is an ordinary injectable: annotate a singleton class implementing
`BodyCodec` and the generator wires it into the server. To enable the
built-in XML codec, subclass it:

```dart
import 'package:diana/diana.dart';

@Component()
class AppXmlCodec extends XmlCodec {}
```

That's all — every route annotated with `application/xml` can now speak
XML. JSON is always registered (it also accepts `…+json` content types
like `application/hal+json`).

Custom formats implement the interface directly:

```dart
@Component()
class CsvCodec implements BodyCodec {
  @override
  List<String> get mimeTypes => ['text/csv'];   // first entry = canonical

  @override
  Object? decode(String body) { /* → Map/List/scalars; FormatException on bad input */ }

  @override
  String encode(Object? value) { /* Map/List/scalars → wire format */ }
}
```

Codecs must be **singletons** — a request-scoped codec is a build error.
The decoded value feeds the same pipeline as JSON: DTO `fromJson`,
validation, everything applies unchanged.

## `@Consumes` — request side

```dart
@Post('/xml')
@Consumes(['application/xml'])
TodoDto create(@Body() CreateTodoRequest body) => service.create(body);
```

- The request's `Content-Type` must match one of the listed types, and a
  codec for it must be registered — otherwise **415 Unsupported Media
  Type**. Malformed bodies (or the wrong shape, e.g. an array where an
  object is expected) are **400**.
- The annotated set **replaces** the default — `@Consumes(['application/xml'])`
  no longer accepts JSON; list both if you want both.
- Method-level replaces controller-level entirely (same precedence rule as
  `@CrossOrigin`).
- Requires a codec-decoded `@Body` parameter (`Map`, `List` or DTO).
  `String`, `FormData` and raw-request bodies bypass codecs, so combining
  them with `@Consumes` is a build error.

## `@Produces` — response side

```dart
@Post('/xml')
@Consumes(['application/xml'])
@Produces(['application/xml', 'application/json'])
TodoDto create(@Body() CreateTodoRequest body) => service.create(body);
```

- The response is encoded with the **first** listed type the request's
  `Accept` header allows — server preference order, like Spring. No
  `Accept` header accepts everything.
- Nothing acceptable → **406 Not Acceptable**.
- Applies to JSON-encodable returns (DTO, `List` of DTOs, `Map`, `List`).
  `String`, `void` and `DianaResponse` returns are not negotiated
  (build error), and `Stream` returns always produce `text/event-stream`
  (see [Server-Sent Events](server-sent-events.md)).

Both annotations are projected into the generated
[OpenAPI document](openapi.md): `requestBody.content` and response
`content` list the declared MIME types.

## The XML convention

XML has no native notion of objects, arrays or types, so `XmlCodec` maps
it to `Map`/`List`/scalars with a fixed convention:

**Decoding** (`application/xml`, `text/xml`):

- The root element's name is ignored; its children become map keys.
- Repeated sibling elements become a `List`.
- An element whose children are all `<item>` becomes a `List`.
- Leaf text is inferred in order: `int` → `double` → `bool` → `String`.
- An empty element decodes to `null`.
- Attributes are **ignored** (documented limitation).

**Encoding**: the root element is `<response>`; list entries are emitted as
repeated elements (or `<item>` at the top level).

```xml
<todo>                          <!-- root name ignored -->
  <title>learn diana</title>    <!-- {'title': 'learn diana', -->
  <priority>2</priority>        <!--  'priority': 2 (int inferred), -->
  <done>false</done>            <!--  'done': false} -->
</todo>
```

One asymmetry to know: a decoded list with a single element is
indistinguishable from a scalar, so it decodes as a scalar. If a DTO field
needs `List<T>` semantics for single values, prefer JSON for that route or
model the field as accepting both.

Scalar inference is what makes typed DTO fields work: `fromJson` casts the
inferred values, and a mismatch surfaces as a 400 through the normal DTO
decoding path.

## Manual negotiation

The generated adapters call two public helpers you can also use directly
in a route returning `DianaResponse`:

```dart
final map = await decodeMapBody(req, consumes: ['application/xml']);     // 415/400
return negotiatedResponse(req, payload, produces: ['application/xml']);  // 406
```

`decodeListBody` is the array-shaped sibling. The registry itself travels
on the request as `req.codecs` (`BodyCodecRegistry.forMime`).

## See also

- [Server-Sent Events](server-sent-events.md) — streaming responses
- [Runtime API](../reference/runtime.md) — `BodyCodec`, `XmlCodec`, helpers
- [Build diagnostics](../reference/build-diagnostics.md) — the exact errors
