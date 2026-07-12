import 'package:meta/meta_meta.dart';

/// Marks the application entrypoint class.
///
/// Must be placed on exactly one class per package, inside `lib/`
/// (convention: `lib/app.dart`). The generator emits a sibling
/// `<file>.diana_app.dart` library containing the wired `DianaContext`,
/// `buildDianaServer()` and `runDiana()`.
@Target({TargetKind.classType})
class DianaApplication {
  /// YAML configuration file loaded at startup, relative to the working
  /// directory.
  final String configFile;

  const DianaApplication({this.configFile = 'application.yaml'});
}
