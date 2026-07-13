/// Reads controller route methods into plain [AdapterModel]s for the part
/// builder, performing all parameter/return-type validation with precise
/// source spans.
library;

import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:source_gen/source_gen.dart' show TypeChecker;

import '../model/adapter_model.dart';
import '../model/summary.dart' show TypeRef;
import 'checkers.dart';
import 'json_reader.dart' show isJsonClass;
import 'library_reader.dart' show DianaSourceError, adapterNameFor, typeRefOf;
import 'validator_reader.dart' show classNeedsValidator;

/// Reads every route adapter of a `@RestController` class.
List<AdapterModel> readControllerAdapters(ClassElement cls) {
  final adapters = <AdapterModel>[];
  for (final method in cls.methods) {
    final routeAnn = httpRouteChecker.firstAnnotationOf(method);
    if (routeAnn == null) continue;
    adapters.add(_readAdapter(cls, method));
  }
  return adapters;
}

AdapterModel _readAdapter(ClassElement cls, MethodElement method) {
  final where = '${cls.name}.${method.name}';

  final params = <AdapterParam>[];
  for (final param in method.formalParameters) {
    params.add(_readParam(param, where));
  }

  // @Consumes/@Produces: method-level replaces controller-level entirely.
  final consumes = _mimeListOf(consumesChecker, method, cls, 'Consumes', where);
  final produces = _mimeListOf(producesChecker, method, cls, 'Produces', where);
  if (consumes != null) {
    final hasCodecBody = params.any((p) =>
        p.kind == BindingKind.bodyMap ||
        p.kind == BindingKind.bodyList ||
        p.kind == BindingKind.bodyDto ||
        p.kind == BindingKind.bodyDtoList);
    if (!hasCodecBody) {
      throw DianaSourceError(
        method,
        '@Consumes on $where requires a codec-decoded @Body parameter '
        '(Map, List or DTO); String, FormData and raw-request bodies '
        'bypass codecs.',
      );
    }
  }

  final statusAnn = responseStatusChecker.firstAnnotationOf(method);
  final status = statusAnn?.getField('code')?.toIntValue();

  var returnType = method.returnType;
  var awaited = false;
  if (returnType is InterfaceType && returnType.isDartAsyncFuture) {
    awaited = true;
    returnType = returnType.typeArguments.single;
  }

  ReturnKind kind;
  var jsonShape = JsonShape.raw;
  var nullableResult = false;
  String? returnDtoName;
  var returnJsonGenerated = false;
  TypeRef? returnTypeRef;
  SseShape? sseShape;
  if (returnType is InterfaceType && returnType.isDartAsyncStream) {
    kind = ReturnKind.sse;
    final element = returnType.typeArguments.single;
    if (_isDiana(element, 'ServerSentEvent')) {
      sseShape = SseShape.event;
    } else if (element is InterfaceType &&
        element.element is ClassElement &&
        !_isJsonPrimitiveOrCollection(element)) {
      returnJsonGenerated = _requireToJson(element, method, where);
      returnDtoName = element.element.name;
      returnTypeRef = typeRefOf(element, method);
      sseShape = SseShape.dto;
    } else {
      throw DianaSourceError(
        method,
        'Route method $where returns '
        'Stream<${element.getDisplayString()}>; supported stream element '
        'types are ServerSentEvent or a DTO with toJson().',
      );
    }
    if (status != null) {
      throw DianaSourceError(
        method,
        '@ResponseStatus cannot be combined with a Stream return on '
        '$where; SSE responses are always 200.',
      );
    }
    if (produces != null) {
      throw DianaSourceError(
        method,
        '@Produces cannot be combined with a Stream return on $where; '
        'SSE always produces text/event-stream.',
      );
    }
  } else if (returnType is VoidType) {
    kind = ReturnKind.voidLike;
  } else if (_isDiana(returnType, 'DianaResponse')) {
    kind = ReturnKind.response;
  } else if (returnType is InterfaceType && returnType.isDartCoreString) {
    kind = ReturnKind.text;
  } else if (returnType is InterfaceType) {
    kind = ReturnKind.json;
    nullableResult =
        returnType.nullabilitySuffix == NullabilitySuffix.question;
    if (_isJsonPrimitiveOrCollection(returnType)) {
      jsonShape = JsonShape.raw;
    } else if (returnType.isDartCoreList) {
      final element = returnType.typeArguments.single;
      returnJsonGenerated = _requireToJson(element, method, where);
      returnDtoName =
          element is InterfaceType ? element.element.name : null;
      returnTypeRef =
          element is InterfaceType ? typeRefOf(element, method) : null;
      jsonShape = JsonShape.dtoList;
    } else {
      returnJsonGenerated = _requireToJson(returnType, method, where);
      returnDtoName = returnType.element.name;
      returnTypeRef = typeRefOf(returnType, method);
      jsonShape = JsonShape.dto;
    }
  } else if (returnType is DynamicType) {
    kind = ReturnKind.json;
  } else {
    throw DianaSourceError(
      method,
      'Route method $where has unsupported return type '
      '${returnType.getDisplayString()}. Supported: a DTO with toJson(), '
      'List of DTOs, Map, String, void, DianaResponse — optionally wrapped '
      'in Future.',
    );
  }

  if (produces != null && kind != ReturnKind.json && kind != ReturnKind.sse) {
    throw DianaSourceError(
      method,
      '@Produces on $where requires a JSON-encodable return (DTO, List of '
      'DTOs, Map or List); String, void and DianaResponse returns are not '
      'negotiated.',
    );
  }

  return AdapterModel(
    className: cls.name!,
    methodName: method.name!,
    adapterName: adapterNameFor(cls.name!, method.name!),
    params: params,
    returnKind: kind,
    jsonShape: jsonShape,
    nullableResult: nullableResult,
    awaited: awaited,
    status: status,
    returnDtoName: returnDtoName,
    returnJsonGenerated: returnJsonGenerated,
    returnTypeRef: returnTypeRef,
    consumes: consumes,
    produces: produces,
    sseShape: sseShape,
  );
}

/// Reads a `@Consumes`/`@Produces` MIME list, method level winning over
/// controller level. Returns null when neither is annotated.
List<String>? _mimeListOf(
  TypeChecker checker,
  MethodElement method,
  ClassElement cls,
  String annotation,
  String where,
) {
  final ann =
      checker.firstAnnotationOf(method) ?? checker.firstAnnotationOf(cls);
  if (ann == null) return null;
  final mimes = ann
      .getField('mimeTypes')
      ?.toListValue()
      ?.map((DartObject e) => e.toStringValue()!)
      .toList();
  if (mimes == null || mimes.isEmpty) {
    throw DianaSourceError(
      method,
      '@$annotation on $where lists no MIME types.',
    );
  }
  return mimes;
}

AdapterParam _readParam(FormalParameterElement param, String where) {
  final path = pathParamChecker.firstAnnotationOf(param);
  final query = queryParamChecker.firstAnnotationOf(param);
  final header = headerChecker.firstAnnotationOf(param);
  final body = bodyChecker.firstAnnotationOf(param);
  final principal = principalChecker.firstAnnotationOf(param);
  final count =
      [path, query, header, body, principal].where((a) => a != null).length;

  final type = param.type;
  if (count == 0) {
    if (_isDiana(type, 'DianaRequest')) {
      return AdapterParam(
        kind: BindingKind.rawRequest,
        paramName: param.name!,
        isNamed: param.isNamed,
        httpName: '',
        typeDisplay: '',
      );
    }
    throw DianaSourceError(
      param,
      'Parameter "${param.name}" of route method $where needs exactly one '
      'binding annotation (@PathParam, @QueryParam, @Header, @Body or '
      '@Principal), or be of type DianaRequest for raw access.',
    );
  }
  if (count > 1) {
    throw DianaSourceError(
      param,
      'Parameter "${param.name}" of route method $where combines multiple '
      'binding annotations; use exactly one.',
    );
  }

  if (principal != null) {
    if (type is! InterfaceType) {
      throw DianaSourceError(
        param,
        '@Principal parameter "${param.name}" of $where must be a class '
        'type.',
      );
    }
    return AdapterParam(
      kind: BindingKind.principal,
      paramName: param.name!,
      isNamed: param.isNamed,
      httpName: '',
      typeDisplay: type.getDisplayString(),
    );
  }

  if (body != null) return _readBodyParam(param, where);

  if (!_isSimpleBindable(type)) {
    throw DianaSourceError(
      param,
      'Parameter "${param.name}" of route method $where must be String, '
      'int, double, bool or num (nullable allowed for @QueryParam/@Header) '
      '— got ${type.getDisplayString()}.',
    );
  }
  final typeDisplay = type.getDisplayString();

  if (path != null) {
    if (type.nullabilitySuffix == NullabilitySuffix.question) {
      throw DianaSourceError(
        param,
        'Path parameter "${param.name}" of $where is always present when '
        'the route matches; use a non-nullable type.',
      );
    }
    return AdapterParam(
      kind: BindingKind.path,
      paramName: param.name!,
      isNamed: param.isNamed,
      httpName: path.getField('name')?.toStringValue() ?? param.name!,
      typeDisplay: typeDisplay,
      typeRef: typeRefOf(type, param),
      apiRequired: true,
    );
  }
  final nullable = type.nullabilitySuffix == NullabilitySuffix.question;
  if (query != null) {
    final defaultValue = query.getField('defaultValue')?.toStringValue();
    return AdapterParam(
      kind: BindingKind.query,
      paramName: param.name!,
      isNamed: param.isNamed,
      httpName: query.getField('name')?.toStringValue() ?? param.name!,
      defaultValue: defaultValue,
      typeDisplay: typeDisplay,
      typeRef: typeRefOf(type, param),
      apiRequired: !nullable && defaultValue == null,
    );
  }
  return AdapterParam(
    kind: BindingKind.header,
    paramName: param.name!,
    isNamed: param.isNamed,
    httpName: header!.getField('name')?.toStringValue() ?? param.name!,
    typeDisplay: typeDisplay,
    typeRef: typeRefOf(type, param),
    apiRequired: !nullable,
  );
}

AdapterParam _readBodyParam(FormalParameterElement param, String where) {
  final type = param.type;
  if (type is! InterfaceType) {
    throw DianaSourceError(
      param,
      '@Body parameter "${param.name}" of $where has unsupported type '
      '${type.getDisplayString()}. Supported: a DTO with fromJson, '
      'Map<String, dynamic>, List, String (raw text) or FormData '
      '(multipart/urlencoded).',
    );
  }
  if (type.isDartCoreString) {
    return AdapterParam(
      kind: BindingKind.bodyText,
      paramName: param.name!,
      isNamed: param.isNamed,
      httpName: '',
      typeDisplay: 'String',
    );
  }
  if (_isDiana(type, 'FormData')) {
    return AdapterParam(
      kind: BindingKind.bodyForm,
      paramName: param.name!,
      isNamed: param.isNamed,
      httpName: '',
      typeDisplay: 'FormData',
    );
  }
  if (type.isDartCoreMap) {
    return AdapterParam(
      kind: BindingKind.bodyMap,
      paramName: param.name!,
      isNamed: param.isNamed,
      httpName: '',
      typeDisplay: type.getDisplayString(),
    );
  }
  if (type.isDartCoreList) {
    final element = type.typeArguments.single;
    if (element is DynamicType ||
        (element is InterfaceType && _isJsonPrimitive(element))) {
      return AdapterParam(
        kind: BindingKind.bodyList,
        paramName: param.name!,
        isNamed: param.isNamed,
        httpName: '',
        typeDisplay: element.getDisplayString(),
      );
    }
    final elementGenerated = _requireFromJson(element, param, where);
    return AdapterParam(
      kind: BindingKind.bodyDtoList,
      paramName: param.name!,
      isNamed: param.isNamed,
      httpName: '',
      typeDisplay: type.getDisplayString(),
      dtoName: element.getDisplayString(),
      validate: _needsValidation(element),
      jsonGenerated: elementGenerated,
      typeRef:
          element is InterfaceType ? typeRefOf(element, param) : null,
    );
  }
  final generated = _requireFromJson(type, param, where);
  return AdapterParam(
    kind: BindingKind.bodyDto,
    paramName: param.name!,
    isNamed: param.isNamed,
    httpName: '',
    typeDisplay: type.getDisplayString(),
    dtoName: type.element.name,
    validate: _needsValidation(type),
    jsonGenerated: generated,
    typeRef: typeRefOf(type, param),
  );
}

bool _isDiana(DartType type, String name) =>
    type is InterfaceType &&
    type.element.name == name &&
    type.element.library.uri.toString().startsWith('package:diana/');

bool _isSimpleBindable(DartType type) =>
    type is InterfaceType &&
    (type.isDartCoreString ||
        type.isDartCoreInt ||
        type.isDartCoreDouble ||
        type.isDartCoreBool ||
        type.isDartCoreNum);

bool _isJsonPrimitive(InterfaceType type) =>
    type.isDartCoreString ||
    type.isDartCoreInt ||
    type.isDartCoreDouble ||
    type.isDartCoreBool ||
    type.isDartCoreNum ||
    type.isDartCoreNull;

bool _isJsonPrimitiveOrCollection(InterfaceType type) {
  if (_isJsonPrimitive(type)) return true;
  if (type.isDartCoreMap || type.isDartCoreList) {
    return type.typeArguments.every(
      (t) =>
          t is DynamicType ||
          (t is InterfaceType &&
              (_isJsonPrimitive(t) || t.isDartCoreObject)) ||
          (t is InterfaceType && _isJsonPrimitiveOrCollection(t)),
    );
  }
  return false;
}

/// Returns true when the class is `@Json` (generated codec); false when it
/// follows the `fromJson` convention. Throws otherwise.
bool _requireFromJson(DartType type, Element context, String where) {
  final cls = type is InterfaceType ? type.element : null;
  final name = type.getDisplayString();
  if (cls is ClassElement && isJsonClass(cls)) return true;
  final hasFactory = cls is ClassElement &&
      (cls.constructors.any((c) => c.name == 'fromJson') ||
          cls.methods.any((m) => m.isStatic && m.name == 'fromJson'));
  if (!hasFactory) {
    throw DianaSourceError(
      context,
      '$name is used with @Body in $where but has no '
      '`factory $name.fromJson(Map<String, dynamic>)`. Annotate the class '
      'with @Json, write one manually, or generate it with '
      'json_serializable (all work with Diana).',
    );
  }
  return false;
}

/// Returns true when the class is `@Json` (generated codec); false when it
/// exposes `toJson()`. Throws otherwise.
bool _requireToJson(DartType type, Element context, String where) {
  var inner = type;
  if (inner is InterfaceType && _isJsonPrimitiveOrCollection(inner)) {
    return false;
  }
  if (inner is DynamicType) return false;
  final cls = inner is InterfaceType ? inner.element : null;
  if (cls is ClassElement && isJsonClass(cls)) return true;
  final hasToJson = cls != null &&
      [cls, ...cls.allSupertypes.map((s) => s.element)]
          .expand((e) => e.methods)
          .any((m) => m.name == 'toJson');
  if (!hasToJson) {
    throw DianaSourceError(
      context,
      '${inner.getDisplayString()} is returned from route method $where but '
      'has no `Map<String, dynamic> toJson()`. Annotate the class with '
      '@Json, write one manually, or generate it with json_serializable '
      '(all work with Diana).',
    );
  }
  return false;
}

bool _needsValidation(DartType type) {
  if (type is! InterfaceType) return false;
  final cls = type.element;
  if (cls is! ClassElement) return false;
  return classNeedsValidator(cls);
}
