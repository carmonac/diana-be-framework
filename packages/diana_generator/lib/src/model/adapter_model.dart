/// Plain-data model of a generated route adapter (one per controller route
/// method). Local to the part builder — never serialized (the serializable
/// [RouteApi] projection is derived from it by `routeApiOf`).
library;

import 'summary.dart';

enum BindingKind {
  rawRequest,
  principal,
  path,
  query,
  header,
  bodyMap,
  bodyList,
  bodyDto,
  bodyDtoList,
  bodyText,
  bodyForm,
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

  /// Whether the DTO is `@Json` (use `$XFromJson` instead of `X.fromJson`).
  final bool jsonGenerated;

  /// Structured type of the parameter (path/query/header: the param type;
  /// body kinds: the body/DTO type). Used for OpenAPI.
  final TypeRef? typeRef;

  /// Whether the parameter is required on the wire (non-nullable and no
  /// default).
  final bool apiRequired;

  const AdapterParam({
    required this.kind,
    required this.paramName,
    required this.isNamed,
    required this.httpName,
    required this.typeDisplay,
    this.defaultValue,
    this.dtoName,
    this.validate = false,
    this.jsonGenerated = false,
    this.typeRef,
    this.apiRequired = true,
  });
}

enum ReturnKind { response, voidLike, text, json, sse }

/// Element shape of an SSE `Stream` return.
enum SseShape { event, dto }

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

  /// DTO class name for dto/dtoList returns.
  final String? returnDtoName;

  /// Whether the returned DTO is `@Json` (use `$XToJson`).
  final bool returnJsonGenerated;

  /// Structured return type (unwrapped from Future), for OpenAPI.
  final TypeRef? returnTypeRef;

  /// Content types accepted by `@Body` (from `@Consumes`); null = JSON.
  final List<String>? consumes;

  /// Response content types (from `@Produces`); null = JSON.
  final List<String>? produces;

  /// Element shape for [ReturnKind.sse] returns.
  final SseShape? sseShape;

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
    this.returnDtoName,
    this.returnJsonGenerated = false,
    this.returnTypeRef,
    this.consumes,
    this.produces,
    this.sseShape,
  });
}

/// Projects the serializable API surface out of an [AdapterModel] — the
/// single classification pass feeds both the part builder and the summary
/// (and therefore OpenAPI), so the two can never diverge.
RouteApi routeApiOf(AdapterModel model) {
  final params = <RouteParamApi>[];
  String? bodyShape;
  TypeRef? bodyType;
  for (final param in model.params) {
    switch (param.kind) {
      case BindingKind.path:
      case BindingKind.query:
      case BindingKind.header:
        params.add(RouteParamApi(
          kind: param.kind.name,
          name: param.httpName,
          type: param.typeRef ??
              const TypeRef(libraryUri: 'dart:core', name: 'String'),
          required: param.apiRequired,
          defaultValue: param.defaultValue,
        ));
      case BindingKind.bodyDto:
        bodyShape = 'dto';
        bodyType = param.typeRef;
      case BindingKind.bodyDtoList:
        bodyShape = 'dtoList';
        bodyType = param.typeRef;
      case BindingKind.bodyMap:
        bodyShape = 'map';
      case BindingKind.bodyList:
        bodyShape = 'list';
      case BindingKind.bodyText:
        bodyShape = 'text';
      case BindingKind.bodyForm:
        bodyShape = 'form';
      case BindingKind.rawRequest:
      case BindingKind.principal:
        // Not wire parameters — nothing to project into the API surface.
        break;
    }
  }
  final returnShape = switch (model.returnKind) {
    ReturnKind.response => 'response',
    ReturnKind.voidLike => 'void',
    ReturnKind.text => 'text',
    ReturnKind.sse => 'sse',
    ReturnKind.json => switch (model.jsonShape) {
        JsonShape.dto => 'dto',
        JsonShape.dtoList => 'dtoList',
        JsonShape.raw => 'raw',
      },
  };
  return RouteApi(
    params: params,
    bodyShape: bodyShape,
    bodyType: bodyType,
    returnShape: returnShape,
    returnType: model.returnTypeRef,
    status: model.status,
    consumes: model.consumes,
    produces: model.produces,
  );
}
