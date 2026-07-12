/// Plain-data model of a generated route adapter (one per controller route
/// method). Local to the part builder — never serialized.
library;

enum BindingKind {
  rawRequest,
  path,
  query,
  header,
  bodyMap,
  bodyList,
  bodyDto,
  bodyDtoList,
}

class AdapterParam {
  final BindingKind kind;

  /// Dart parameter name.
  final String paramName;
  final bool isNamed;

  /// Path/query/header name on the wire.
  final String httpName;

  /// For path/query/header: the parameter type as written (e.g. `int?`).
  /// For bodyList: the list element type.
  final String typeDisplay;
  final String? defaultValue;

  /// DTO class name for bodyDto/bodyDtoList.
  final String? dtoName;

  /// Whether to run the DTO's generated validator after decoding.
  final bool validate;

  const AdapterParam({
    required this.kind,
    required this.paramName,
    required this.isNamed,
    required this.httpName,
    required this.typeDisplay,
    this.defaultValue,
    this.dtoName,
    this.validate = false,
  });
}

enum ReturnKind { response, voidLike, text, json }

/// How a json-kind result is converted before `DianaResponse.json`.
enum JsonShape { raw, dto, dtoList }

class AdapterModel {
  final String className;
  final String methodName;
  final String adapterName;
  final List<AdapterParam> params;
  final ReturnKind returnKind;
  final JsonShape jsonShape;
  final bool nullableResult;

  /// Whether the controller method returns a `Future`.
  final bool awaited;

  /// Status override from `@ResponseStatus`.
  final int? status;

  const AdapterModel({
    required this.className,
    required this.methodName,
    required this.adapterName,
    required this.params,
    required this.returnKind,
    this.jsonShape = JsonShape.raw,
    this.nullableResult = false,
    required this.awaited,
    this.status,
  });
}
