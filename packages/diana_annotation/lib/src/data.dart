import 'package:meta/meta_meta.dart';

/// Runs the method inside a database transaction (Spring:
/// `@Transactional`).
///
/// Requires the `diana_data` package. The method must return a `Future` and
/// live on a `@Service`/`@Component`/`@Repository` provider that is open to
/// extension (not `final`/`base`/`sealed`) — the generator emits a proxy
/// subclass overriding it to wrap the call in an ambient transaction.
///
/// Transactions nest with **propagation REQUIRED**: a `@Transactional`
/// method called from within another joins the enclosing transaction as a
/// savepoint. An uncaught exception rolls the (save)point back and rethrows.
///
/// On a class it applies to every public `Future`-returning method.
@Target({TargetKind.method, TargetKind.classType})
class Transactional {
  const Transactional();
}
