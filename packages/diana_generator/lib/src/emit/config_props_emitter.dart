/// Emits `$XFromConfig` binder functions into the class's part file.
///
/// Every constructor parameter is bound from `<prefix>.<paramName>`;
/// nullable parameters make the key optional.
library;

import '../model/config_props_model.dart';

String emitConfigPropsBinder(ConfigPropsModel model) {
  final buffer = StringBuffer()
    ..writeln('${model.className} \$${model.className}FromConfig('
        'DianaConfig config) =>')
    ..writeln('    ${model.className}(');
  for (final param in model.params) {
    final key =
        model.prefix.isEmpty ? param.name : '${model.prefix}.${param.name}';
    final label = param.isNamed ? '${param.name}: ' : '';
    buffer.writeln("      ${label}config.get<${param.typeDisplay}>('$key'),");
  }
  buffer.writeln('    );');
  return buffer.toString();
}
