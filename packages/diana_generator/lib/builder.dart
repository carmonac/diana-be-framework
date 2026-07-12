/// Builder entrypoints for the Diana code generator, referenced from
/// `build.yaml`.
library;

import 'package:build/build.dart';

import 'src/bootstrap_builder.dart';
import 'src/metadata_builder.dart';
import 'src/part_builder.dart';

Builder dianaMetadataBuilder(BuilderOptions options) =>
    const DianaMetadataBuilder();

Builder dianaPartBuilder(BuilderOptions options) => const DianaPartBuilder();

Builder dianaBootstrapBuilder(BuilderOptions options) =>
    const DianaBootstrapBuilder();
