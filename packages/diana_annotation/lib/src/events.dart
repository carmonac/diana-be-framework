import 'package:meta/meta_meta.dart';

/// Marks a method as an application-event listener (Spring:
/// `@EventListener`).
///
/// The method must be a public instance method with exactly one positional
/// parameter — the event type — returning `void` or `Future<void>`, on a
/// **singleton** provider. It receives every published event whose runtime
/// type matches the parameter type (subtypes included).
///
/// Events are published through the injectable `DianaEventPublisher`:
/// `publish` delivers to local listeners (awaited, in registration order);
/// `broadcast` additionally relays the event to every other isolate when
/// serving with `server.isolates > 1`.
@Target({TargetKind.method})
class EventListener {
  const EventListener();
}
