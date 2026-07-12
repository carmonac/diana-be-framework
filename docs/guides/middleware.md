# Middleware

Middleware intercept requests around handlers — logging, auth, headers,
rate limiting. Diana's model is a class implementing one interface:

```dart
abstract interface class Middleware {
  FutureOr<DianaResponse> handle(DianaRequest request, Next next);
}

typedef Next = FutureOr<DianaResponse> Function(DianaRequest request);
```

Call `next(request)` to continue the chain; return a response directly to
**short-circuit** (the handler never runs). You can act before `next`
(inspect/annotate the request), after it (transform the response), or both.

```dart
@GlobalMiddleware(order: 0)
class TimingMiddleware implements Middleware {
  @override
  Future<DianaResponse> handle(DianaRequest request, Next next) async {
    final watch = Stopwatch()..start();
    final response = await next(request);
    return response.copyWith(headers: {
      ...response.headers,
      'x-response-time-ms': '${watch.elapsedMilliseconds}',
    });
  }
}
```

## Registering middleware

**Globally** — annotate the class with `@GlobalMiddleware`:

```dart
@GlobalMiddleware(order: 0)
class LoggingMiddleware implements Middleware { ... }
```

Applies to every route. Lower `order` runs first (i.e. outermost); ties are
broken by class name for deterministic builds. `@GlobalMiddleware` classes
are automatically injectable singletons.

**Per controller or per route** — annotate the middleware class as a
regular component and reference it with `@UseMiddleware`:

```dart
@Component()
class ApiKeyMiddleware implements Middleware {
  ApiKeyMiddleware(@Value('app.apiKey') this.expected);
  final String expected;

  @override
  Future<DianaResponse> handle(DianaRequest request, Next next) async {
    if (request.header('x-api-key') != expected) {
      return DianaResponse.json({'error': 'unauthorized'}, statusCode: 401);
    }
    return await next(request);
  }
}

@RestController('/admin')
@UseMiddleware([AuditMiddleware])          // every route in the controller
class AdminController {
  @Delete('/:id')
  @UseMiddleware([ApiKeyMiddleware])       // this route only
  void remove(@PathParam() int id) { ... }
}
```

`@UseMiddleware` takes an ordered list of types; each must be an injectable
class implementing `Middleware` (verified at build time, with a clear error
otherwise).

## Execution order

For any request the chain is always:

```
global (sorted by order) → controller-level (listed order) → route-level (listed order) → handler
```

The first middleware sees the request first and the response last
(onion model). Short-circuiting anywhere skips everything further in.

## Middleware and DI

Middleware are ordinary providers: constructor injection, `@Value`
configuration, interface auto-binding — everything from the
[DI guide](dependency-injection.md) applies. One restriction: **middleware
must be singletons** (a request-scoped middleware is a build error).

## Passing data to handlers

Use `DianaRequest.attributes`, a per-request `Map<String, Object?>` bag:

```dart
// middleware
request.attributes['userId'] = token.subject;
return next(request);

// handler (raw request access)
@Get('/me')
Map<String, dynamic> me(DianaRequest req) =>
    {'userId': req.attributes['userId']};
```

## Errors thrown in middleware

The exception boundary wraps the **whole** chain: an `HttpException` or an
advice-mapped exception thrown from middleware produces the same JSON error
responses as one thrown from a handler. See
[Error handling](error-handling.md).
