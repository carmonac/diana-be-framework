/// Reads controller route methods into plain [AdapterModel]s for the part
/// builder, performing all parameter/return-type validation with precise
/// source spans.
library;

import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:analyzer/dart/element/type.dart';

import '../model/adapter_model.dart';
import 'checkers.dart';
import 'library_reader.dart' show DianaSourceError, adapterNameFor;
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
  if (returnType is VoidType) {
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
      _requireToJson(element, method, where);
      jsonShape = JsonShape.dtoList;
    } else {
      _requireToJson(returnType, method, where);
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
  );
}

AdapterParam _readParam(FormalParameterElement param, String where) {
  final path = pathParamChecker.firstAnnotationOf(param);
  final query = queryParamChecker.firstAnnotationOf(param);
  final header = headerChecker.firstAnnotationOf(param);
  final body = bodyChecker.firstAnnotationOf(param);
  final count =
      [path, query, header, body].where((a) => a != null).length;

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
      'binding annotation (@PathParam, @QueryParam, @Header or @Body), or '
      'be of type DianaRequest for raw access.',
    );
  }
  if (count > 1) {
    throw DianaSourceError(
      param,
      'Parameter "${param.name}" of route method $where combines multiple '
      'binding annotations; use exactly one.',
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
    );
  }
  if (query != null) {
    return AdapterParam(
      kind: BindingKind.query,
      paramName: param.name!,
      isNamed: param.isNamed,
      httpName: query.getField('name')?.toStringValue() ?? param.name!,
      defaultValue: query.getField('defaultValue')?.toStringValue(),
      typeDisplay: typeDisplay,
    );
  }
  return AdapterParam(
    kind: BindingKind.header,
    paramName: param.name!,
    isNamed: param.isNamed,
    httpName: header!.getField('name')?.toStringValue() ?? param.name!,
    typeDisplay: typeDisplay,
  );
}

AdapterParam _readBodyParam(FormalParameterElement param, String where) {
  final type = param.type;
  if (type is! InterfaceType) {
    throw DianaSourceError(
      param,
      '@Body parameter "${param.name}" of $where has unsupported type '
      '${type.getDisplayString()}.',
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
    _requireFromJson(element, param, where);
    return AdapterParam(
      kind: BindingKind.bodyDtoList,
      paramName: param.name!,
      isNamed: param.isNamed,
      httpName: '',
      typeDisplay: type.getDisplayString(),
      dtoName: element.getDisplayString(),
      validate: _needsValidation(element),
    );
  }
  _requireFromJson(type, param, where);
  return AdapterParam(
    kind: BindingKind.bodyDto,
    paramName: param.name!,
    isNamed: param.isNamed,
    httpName: '',
    typeDisplay: type.getDisplayString(),
    dtoName: type.element.name,
    validate: _needsValidation(type),
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

void _requireFromJson(DartType type, Element context, String where) {
  final cls = type is InterfaceType ? type.element : null;
  final name = type.getDisplayString();
  final hasFactory = cls is ClassElement &&
      (cls.constructors.any((c) => c.name == 'fromJson') ||
          cls.methods.any((m) => m.isStatic && m.name == 'fromJson'));
  if (!hasFactory) {
    throw DianaSourceError(
      context,
      '$name is used with @Body in $where but has no '
      '`factory $name.fromJson(Map<String, dynamic>)`. Write one manually '
      'or generate it with json_serializable (both work with Diana).',
    );
  }
}

void _requireToJson(DartType type, Element context, String where) {
  var inner = type;
  if (inner is InterfaceType && _isJsonPrimitiveOrCollection(inner)) return;
  if (inner is DynamicType) return;
  final cls = inner is InterfaceType ? inner.element : null;
  final hasToJson = cls != null &&
      [cls, ...cls.allSupertypes.map((s) => s.element)]
          .expand((e) => e.methods)
          .any((m) => m.name == 'toJson');
  if (!hasToJson) {
    throw DianaSourceError(
      context,
      '${inner.getDisplayString()} is returned from route method $where but '
      'has no `Map<String, dynamic> toJson()`. Write one manually or '
      'generate it with json_serializable (both work with Diana).',
    );
  }
}

bool _needsValidation(DartType type) {
  if (type is! InterfaceType) return false;
  final cls = type.element;
  if (cls is! ClassElement) return false;
  return classNeedsValidator(cls);
}
