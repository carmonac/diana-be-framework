import 'package:meta/meta_meta.dart';

/// Marks a method to run after the provider is constructed, during
/// application initialization (Spring: `@PostConstruct`).
///
/// Requirements (enforced at build time): public instance method, no
/// parameters, returning `void` or `Future<void>`; at most one per class;
/// the provider must be a singleton. Post-construct methods run in
/// dependency (topological) order and are awaited before the server starts
/// accepting traffic.
@Target({TargetKind.method})
class PostConstruct {
  const PostConstruct();
}

/// Marks a method to run during graceful shutdown (Spring: `@PreDestroy`).
///
/// Same signature rules as [PostConstruct]. Pre-destroy methods run in
/// **reverse** dependency order after the server has stopped accepting
/// requests and in-flight requests have drained.
@Target({TargetKind.method})
class PreDestroy {
  const PreDestroy();
}
