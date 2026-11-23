/// Native HTTP engine for Diana, backed by
/// [relic_native](https://pub.dev/packages/relic_native).
///
/// Register one [DianaNativeEngine] subclass as a singleton; the generator
/// discovers it and serves the app through the native adapter.
library;

export 'package:relic_native/relic_native.dart' show NativeOptions;

export 'src/native_engine.dart';
