/// Plain-data model of a generated `@ConfigurationProperties` binder.
library;

class ConfigPropsParam {
  final String name;
  final bool isNamed;

  /// Parameter type as written, e.g. `int?`.
  final String typeDisplay;

  const ConfigPropsParam({
    required this.name,
    required this.isNamed,
    required this.typeDisplay,
  });
}

class ConfigPropsModel {
  final String className;
  final String prefix;
  final List<ConfigPropsParam> params;

  const ConfigPropsModel({
    required this.className,
    required this.prefix,
    required this.params,
  });
}
