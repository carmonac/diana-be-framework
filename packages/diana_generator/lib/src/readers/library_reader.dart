/// Converts a resolved [LibraryElement] into the plain-data [LibrarySummary].
///
/// Every analyzer touch-point of the metadata/bootstrap pipeline lives here;
/// graph resolution and code emission never see analyzer types.
library;

import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:collection/collection.dart';
import 'package:source_gen/source_gen.dart' show TypeChecker;

import '../model/adapter_model.dart' show routeApiOf;
import '../model/summary.dart';
import 'adapter_reader.dart' show readControllerAdapters;
import 'checkers.dart';
import 'json_reader.dart' show isJsonClass;

/// Error tied to a source element, formatted with a source span by builders.
class DianaSourceError implements Exception {
  final Element element;
  final String message;

  DianaSourceError(this.element, this.message);

  @override
  String toString() => message;
}

/// Reads every Diana-annotated declaration of [library].
LibrarySummary readLibrary(LibraryElement library) {
  final injectables = <InjectableInfo>[];
  final controllers = <ControllerInfo>[];
  final dtos = <DtoInfo>[];
  final webSockets = <WebSocketInfo>[];
  final globalMiddleware = <GlobalMiddlewareInfo>[];
  final advices = <AdviceInfo>[];
  final grpcServices = <GrpcServiceInfo>[];
  AppInfo? app;

  for (final cls in library.classes) {
    final dto = _dtoInfoOf(cls);
    if (dto != null) dtos.add(dto);

    final injectableAnn = injectableChecker.firstAnnotationOf(cls);
    final controllerAnn = restControllerChecker.firstAnnotationOf(cls);
    final wsAnn = webSocketControllerChecker.firstAnnotationOf(cls);
    final grpcAnn = grpcServiceChecker.firstAnnotationOf(cls);
    final gmAnn = globalMiddlewareChecker.firstAnnotationOf(cls);
    final adviceAnn = controllerAdviceChecker.firstAnnotationOf(cls);
    final configPropsAnn = configPropsChecker.firstAnnotationOf(cls);
    final appAnn = dianaApplicationChecker.firstAnnotationOf(cls);

    final roles = [
      if (injectableAnn != null) '@Injectable/@Service/@Repository/@Component',
      if (controllerAnn != null) '@RestController',
      if (wsAnn != null) '@WebSocketController',
      if (grpcAnn != null) '@GrpcService',
      if (gmAnn != null) '@GlobalMiddleware',
      if (adviceAnn != null) '@ControllerAdvice',
      if (configPropsAnn != null) '@ConfigurationProperties',
      if (appAnn != null) '@DianaApplication',
    ];
    if (roles.isEmpty) continue;
    if (roles.length > 1) {
      throw DianaSourceError(
        cls,
        'Class ${cls.name} combines ${roles.join(' and ')}; '
        'a class may carry only one Diana role annotation.',
      );
    }

    if (appAnn != null) {
      app = AppInfo(
        className: cls.name!,
        configFile: appAnn.getField('configFile')?.toStringValue() ??
            'application.yaml',
      );
      continue;
    }

    _checkProviderClass(cls);
    final selfType = _selfTypeRef(cls);

    if (injectableAnn != null) {
      injectables.add(
        _injectableFrom(cls, selfType, injectableAnn),
      );
    } else if (controllerAnn != null) {
      final scope = _scopeName(controllerAnn.getField('scope'));
      injectables.add(_withLifecycle(cls, InjectableInfo(
        type: selfType,
        scope: scope,
        supertypes: _supertypeRefs(cls),
        ctorParams: _ctorParams(cls),
      )));
      controllers.add(_controllerFrom(cls, selfType, controllerAnn));
    } else if (wsAnn != null) {
      final scope = _scopeName(wsAnn.getField('scope'));
      if (scope == 'request') {
        throw DianaSourceError(
          cls,
          '@WebSocketController class ${cls.name} cannot be request-scoped; '
          'use Scope.singleton (shared handler) or Scope.transient '
          '(one handler per connection).',
        );
      }
      injectables.add(_withLifecycle(cls, InjectableInfo(
        type: selfType,
        scope: scope,
        supertypes: _supertypeRefs(cls),
        ctorParams: _ctorParams(cls),
      )));
      webSockets.add(WebSocketInfo(
        type: selfType,
        path: wsAnn.getField('path')!.toStringValue()!,
        middleware: _useMiddlewareTypes(cls),
      ));
    } else if (grpcAnn != null) {
      injectables.add(_withLifecycle(cls, InjectableInfo(
        type: selfType,
        scope: 'singleton',
        supertypes: _supertypeRefs(cls),
        ctorParams: _ctorParams(cls),
      )));
      grpcServices.add(GrpcServiceInfo(type: selfType));
    } else if (gmAnn != null) {
      injectables.add(_withLifecycle(cls, InjectableInfo(
        type: selfType,
        scope: 'singleton',
        supertypes: _supertypeRefs(cls),
        ctorParams: _ctorParams(cls),
      )));
      globalMiddleware.add(GlobalMiddlewareInfo(
        type: selfType,
        order: gmAnn.getField('order')?.toIntValue() ?? 0,
      ));
    } else if (adviceAnn != null) {
      injectables.add(_withLifecycle(cls, InjectableInfo(
        type: selfType,
        scope: 'singleton',
        supertypes: _supertypeRefs(cls),
        ctorParams: _ctorParams(cls),
      )));
      advices.add(_adviceFrom(cls, selfType));
    } else if (configPropsAnn != null) {
      injectables.add(_withLifecycle(cls, InjectableInfo(
        type: selfType,
        scope: 'singleton',
        kind: ProviderKind.configProps,
        configPrefix:
            configPropsAnn.getField('prefix')?.toStringValue() ?? '',
      )));
    }
  }

  return LibrarySummary(
    libraryUri: library.uri.toString(),
    injectables: injectables,
    controllers: controllers,
    dtos: dtos,
    webSockets: webSockets,
    globalMiddleware: globalMiddleware,
    advices: advices,
    grpcServices: grpcServices,
    app: app,
  );
}

void _checkProviderClass(ClassElement cls) {
  final name = cls.name;
  if (name == null || name.startsWith('_')) {
    throw DianaSourceError(
      cls,
      'Diana-annotated classes must be public: generated wiring in other '
      'libraries needs to reference them.',
    );
  }
  if (cls.typeParameters.isNotEmpty) {
    throw DianaSourceError(
      cls,
      'Class $name declares type parameters. Generic injectables are not '
      'supported; provide a concrete subclass instead.',
    );
  }
  if (cls.isAbstract) {
    throw DianaSourceError(
      cls,
      'Class $name is abstract and cannot be instantiated. Annotate a '
      'concrete implementation instead.',
    );
  }
}

InjectableInfo _injectableFrom(
  ClassElement cls,
  TypeRef selfType,
  DartObject ann,
) {
  final asType = _constField(ann, 'as')?.toTypeValue();
  TypeRef? explicitAs;
  if (asType != null) {
    explicitAs = _typeRefOf(asType, cls);
    final implemented = cls.allSupertypes.any(
      (s) => _typeRefOf(s, cls).key == explicitAs!.key,
    );
    if (!implemented) {
      throw DianaSourceError(
        cls,
        'Class ${cls.name} is bound `as: ${explicitAs.displayName}` but does '
        'not implement or extend it.',
      );
    }
  }
  final scope = _scopeName(_constField(ann, 'scope'));
  final lifecycle = _lifecycleOf(cls, scope);
  return InjectableInfo(
    type: selfType,
    scope: scope,
    qualifier: _constField(ann, 'name')?.toStringValue(),
    explicitAs: explicitAs,
    supertypes: _supertypeRefs(cls),
    ctorParams: _ctorParams(cls),
    postConstruct: lifecycle.postConstruct,
    postConstructAwaited: lifecycle.postConstructAwaited,
    preDestroy: lifecycle.preDestroy,
    preDestroyAwaited: lifecycle.preDestroyAwaited,
    scheduled: _scheduledOf(cls, scope),
  );
}

ControllerInfo _controllerFrom(
  ClassElement cls,
  TypeRef selfType,
  DartObject ann,
) {
  // Single classification pass shared with the part builder: the API
  // surface serialized here can never diverge from the generated adapters.
  final apiByMethod = {
    for (final model in readControllerAdapters(cls))
      model.methodName: routeApiOf(model),
  };
  final routes = <RouteInfo>[];
  for (final method in cls.methods) {
    final routeAnn = httpRouteChecker.firstAnnotationOf(method);
    if (routeAnn == null) continue;
    if (method.isStatic || method.name!.startsWith('_')) {
      throw DianaSourceError(
        method,
        'Route method ${cls.name}.${method.name} must be a public instance '
        'method.',
      );
    }
    routes.add(RouteInfo(
      httpMethod: _constField(routeAnn, 'method')!.toStringValue()!,
      path: _constField(routeAnn, 'path')!.toStringValue()!,
      methodName: method.name!,
      adapterName: adapterNameFor(cls.name!, method.name!),
      middleware: _useMiddlewareTypes(method),
      cors: _corsOf(method),
      api: apiByMethod[method.name],
    ));
  }
  return ControllerInfo(
    type: selfType,
    basePath: ann.getField('path')?.toStringValue() ?? '/',
    middleware: _useMiddlewareTypes(cls),
    routes: routes,
    cors: _corsOf(cls),
  );
}

/// Builds schema metadata for `@Json` classes and validated DTOs; other
/// classes yield `null` (their OpenAPI schema is a best-effort empty
/// object).
DtoInfo? _dtoInfoOf(ClassElement cls) {
  final isJson = isJsonClass(cls);
  final hasConstraints = cls.fields.any(
    (f) =>
        validChecker.hasAnnotationOf(f) ||
        constraintCheckers.any((c) => c.hasAnnotationOf(f)),
  );
  if (!isJson && !hasConstraints) return null;

  final fields = <DtoFieldInfo>[];
  for (final field in cls.fields) {
    if (field.isStatic || !field.isOriginDeclaration) continue;
    final TypeRef fieldType;
    try {
      fieldType = _typeRefOf(field.type, field);
    } on DianaSourceError {
      continue; // Non-class types can't appear in a schema; skip.
    }
    final constraints = <String, Object?>{};
    final size = sizeChecker.firstAnnotationOf(field);
    if (size != null) {
      final min = size.getField('min')?.toIntValue();
      final max = size.getField('max')?.toIntValue();
      if (min != null) constraints['minLength'] = min;
      if (max != null) constraints['maxLength'] = max;
    }
    final minAnn = minChecker.firstAnnotationOf(field);
    if (minAnn != null) {
      constraints['min'] = minAnn.getField('value')?.toIntValue() ??
          minAnn.getField('value')?.toDoubleValue();
    }
    final maxAnn = maxChecker.firstAnnotationOf(field);
    if (maxAnn != null) {
      constraints['max'] = maxAnn.getField('value')?.toIntValue() ??
          maxAnn.getField('value')?.toDoubleValue();
    }
    final patternAnn = patternChecker.firstAnnotationOf(field);
    if (patternAnn != null) {
      constraints['pattern'] = patternAnn.getField('regex')?.toStringValue();
    }
    if (emailChecker.hasAnnotationOf(field)) constraints['email'] = true;
    if (notBlankChecker.hasAnnotationOf(field)) {
      constraints['notBlank'] = true;
    }
    if (notEmptyChecker.hasAnnotationOf(field)) {
      constraints['notEmpty'] = true;
    }

    List<String>? enumValues;
    final typeElement = field.type is InterfaceType
        ? (field.type as InterfaceType).element
        : null;
    if (typeElement is EnumElement) {
      enumValues = [
        for (final constant in typeElement.fields)
          if (constant.isEnumConstant) constant.name!,
      ];
    }

    fields.add(DtoFieldInfo(
      name: field.name!,
      jsonName: isJson
          ? (jsonFieldChecker
                  .firstAnnotationOf(field)
                  ?.getField('name')
                  ?.toStringValue() ??
              field.name!)
          : field.name!,
      type: fieldType,
      nullable:
          field.type.nullabilitySuffix == NullabilitySuffix.question,
      enumValues: enumValues,
      constraints: constraints,
    ));
  }
  return DtoInfo(type: _selfTypeRef(cls), fields: fields);
}

/// Reads a `@CrossOrigin` annotation from a controller class or route
/// method.
CorsInfo? _corsOf(Element element) {
  final ann = crossOriginChecker.firstAnnotationOf(element);
  if (ann == null) return null;
  List<String>? strings(String field) => ann
      .getField(field)
      ?.toListValue()
      ?.map((e) => e.toStringValue()!)
      .toList();
  return CorsInfo(
    origins: strings('origins') ?? const ['*'],
    methods: strings('methods'),
    headers: strings('headers') ?? const ['*'],
    exposedHeaders: strings('exposedHeaders') ?? const [],
    credentials: ann.getField('credentials')?.toBoolValue() ?? false,
    maxAge: ann.getField('maxAge')?.toIntValue() ?? 3600,
  );
}

AdviceInfo _adviceFrom(ClassElement cls, TypeRef selfType) {
  final handlers = <HandlerInfo>[];
  for (final method in cls.methods) {
    final ann = exceptionHandlerChecker.firstAnnotationOf(method);
    if (ann == null) continue;
    final excType = ann.getField('exception')?.toTypeValue();
    if (excType is! InterfaceType) {
      throw DianaSourceError(
        method,
        '@ExceptionHandler on ${cls.name}.${method.name} must reference a '
        'class type.',
      );
    }
    final params = method.formalParameters;
    if (params.isEmpty ||
        params.length > 2 ||
        params.first.type is! InterfaceType ||
        _typeRefOf(params.first.type, method).key !=
            _typeRefOf(excType, method).key ||
        (params.length == 2 && !_isDianaRequest(params[1].type))) {
      throw DianaSourceError(
        method,
        'Exception handler ${cls.name}.${method.name} must take '
        '(${excType.element.name}) or '
        '(${excType.element.name}, DianaRequest).',
      );
    }
    var returnType = method.returnType;
    if (returnType is InterfaceType && returnType.isDartAsyncFuture) {
      returnType = returnType.typeArguments.single;
    }
    if (!_isDianaResponse(returnType)) {
      throw DianaSourceError(
        method,
        'Exception handler ${cls.name}.${method.name} must return '
        'DianaResponse (or Future<DianaResponse>).',
      );
    }
    handlers.add(HandlerInfo(
      exceptionType: _typeRefOf(excType, method),
      methodName: method.name!,
      takesRequest: params.length == 2,
      depth: _supertypeDepth(excType),
    ));
  }
  if (handlers.isEmpty) {
    throw DianaSourceError(
      cls,
      '@ControllerAdvice class ${cls.name} declares no @ExceptionHandler '
      'methods.',
    );
  }
  return AdviceInfo(type: selfType, handlers: handlers);
}

/// Name of the generated public route adapter for a controller method.
String adapterNameFor(String className, String methodName) =>
    '\$diana\$$className\$$methodName';

String _scopeName(DartObject? scopeObj) {
  final index = _constField(scopeObj, 'index')?.toIntValue();
  const names = ['singleton', 'request', 'transient'];
  return index == null ? 'singleton' : names[index];
}

/// Reads a field from a const object, walking the superclass chain (the
/// analyzer stores inherited fields under the synthetic `(super)` key).
DartObject? _constField(DartObject? object, String name) {
  var current = object;
  while (current != null) {
    final value = current.getField(name);
    if (value != null) return value;
    current = current.getField('(super)');
  }
  return null;
}

List<TypeRef> _useMiddlewareTypes(Element element) {
  final ann = useMiddlewareChecker.firstAnnotationOf(element);
  if (ann == null) return const [];
  final list = ann.getField('middleware')?.toListValue() ?? const [];
  return [
    for (final item in list)
      _typeRefOf(
        item.toTypeValue() ??
            (throw DianaSourceError(
              element,
              '@UseMiddleware entries must be type literals.',
            )),
        element,
      ),
  ];
}

List<CtorParamInfo> _ctorParams(ClassElement cls) {
  final ctor = cls.constructors
      .where((c) => c.isGenerative && (c.name == 'new' || c.name == null))
      .firstOrNull;
  if (ctor == null) {
    throw DianaSourceError(
      cls,
      'Class ${cls.name} has no public unnamed generative constructor; '
      'Diana instantiates providers through it.',
    );
  }

  final params = <CtorParamInfo>[];
  for (final param in ctor.formalParameters) {
    final valueAnn = valueChecker.firstAnnotationOf(param);
    final namedAnn = namedChecker.firstAnnotationOf(param);
    final type = param.type;
    if (type is! InterfaceType) {
      throw DianaSourceError(
        param,
        'Constructor parameter "${param.name}" of ${cls.name} has '
        'unsupported type ${type.getDisplayString()}; only class types can '
        'be injected.',
      );
    }
    String? valueKey;
    Object? valueDefault;
    var hasValueDefault = false;
    if (valueAnn != null) {
      if (!_isConfigBindable(type)) {
        throw DianaSourceError(
          param,
          '@Value parameter "${param.name}" of ${cls.name} must be String, '
          'int, double, bool or num — got ${type.getDisplayString()}.',
        );
      }
      valueKey = valueAnn.getField('key')!.toStringValue();
      final def = valueAnn.getField('defaultValue');
      if (def != null && !def.isNull) {
        valueDefault = _constToJson(def, param);
        hasValueDefault = true;
      }
    }
    params.add(CtorParamInfo(
      name: param.name!,
      isNamed: param.isNamed,
      type: _typeRefOf(type, param),
      qualifier: namedAnn?.getField('name')?.toStringValue(),
      valueKey: valueKey,
      valueDefault: valueDefault,
      hasValueDefault: hasValueDefault,
    ));
  }
  return params;
}

bool _isConfigBindable(InterfaceType type) =>
    type.isDartCoreString ||
    type.isDartCoreInt ||
    type.isDartCoreDouble ||
    type.isDartCoreBool ||
    type.isDartCoreNum;

Object? _constToJson(DartObject value, Element context) =>
    value.toStringValue() ??
    value.toIntValue() ??
    value.toBoolValue() ??
    value.toDoubleValue() ??
    (throw DianaSourceError(
      context,
      '@Value defaultValue must be a String, int, double or bool literal.',
    ));

TypeRef _selfTypeRef(ClassElement cls) => TypeRef(
      libraryUri: cls.library.uri.toString(),
      name: cls.name!,
    );

List<TypeRef> _supertypeRefs(ClassElement cls) => [
      for (final st in cls.allSupertypes)
        if (!st.isDartCoreObject &&
            !st.element.library.uri.toString().startsWith('dart:'))
          _typeRefOf(st, cls),
    ];

typedef _Lifecycle = ({
  String? postConstruct,
  bool postConstructAwaited,
  String? preDestroy,
  bool preDestroyAwaited,
});

/// Reads `@PostConstruct`/`@PreDestroy` methods of a provider class,
/// validating signatures and scope compatibility.
_Lifecycle _lifecycleOf(ClassElement cls, String scope) {
  final post = _lifecycleMethod(cls, postConstructChecker, 'PostConstruct', scope);
  final pre = _lifecycleMethod(cls, preDestroyChecker, 'PreDestroy', scope);
  return (
    postConstruct: post.name,
    postConstructAwaited: post.awaited,
    preDestroy: pre.name,
    preDestroyAwaited: pre.awaited,
  );
}

/// Re-creates [info] with the class's lifecycle and scheduled methods
/// attached.
InjectableInfo _withLifecycle(ClassElement cls, InjectableInfo info) {
  final lifecycle = _lifecycleOf(cls, info.scope);
  final scheduled = _scheduledOf(cls, info.scope);
  if (lifecycle.postConstruct == null &&
      lifecycle.preDestroy == null &&
      scheduled.isEmpty) {
    return info;
  }
  return InjectableInfo(
    type: info.type,
    scope: info.scope,
    qualifier: info.qualifier,
    explicitAs: info.explicitAs,
    supertypes: info.supertypes,
    ctorParams: info.ctorParams,
    kind: info.kind,
    configPrefix: info.configPrefix,
    postConstruct: lifecycle.postConstruct,
    postConstructAwaited: lifecycle.postConstructAwaited,
    preDestroy: lifecycle.preDestroy,
    preDestroyAwaited: lifecycle.preDestroyAwaited,
    scheduled: scheduled,
  );
}

/// Reads `@Scheduled` methods, validating signatures, timing arguments and
/// scope.
List<ScheduledMethodInfo> _scheduledOf(ClassElement cls, String scope) {
  final result = <ScheduledMethodInfo>[];
  for (final method in cls.methods) {
    final ann = scheduledChecker.firstAnnotationOf(method);
    if (ann == null) continue;
    final returnType = method.returnType;
    final returnsFutureVoid = returnType is InterfaceType &&
        returnType.isDartAsyncFuture &&
        returnType.typeArguments.single is VoidType;
    final validSignature = !method.isStatic &&
        !method.name!.startsWith('_') &&
        method.formalParameters.isEmpty &&
        (returnType is VoidType || returnsFutureVoid);
    if (!validSignature) {
      throw DianaSourceError(
        method,
        '@Scheduled method ${cls.name}.${method.name} must be a public '
        'instance method with no parameters returning void or Future<void>.',
      );
    }
    final fixedRate = ann.getField('fixedRate')?.toIntValue();
    final fixedDelay = ann.getField('fixedDelay')?.toIntValue();
    if ((fixedRate == null) == (fixedDelay == null)) {
      throw DianaSourceError(
        method,
        '@Scheduled on ${cls.name}.${method.name} requires exactly one of '
        'fixedRate or fixedDelay.',
      );
    }
    if (scope != 'singleton') {
      throw DianaSourceError(
        method,
        '@Scheduled on ${cls.name} requires singleton scope; found $scope.',
      );
    }
    result.add(ScheduledMethodInfo(
      methodName: method.name!,
      fixedRateMs: fixedRate,
      fixedDelayMs: fixedDelay,
      initialDelayMs: ann.getField('initialDelay')?.toIntValue() ?? 0,
    ));
  }
  return result;
}

({String? name, bool awaited}) _lifecycleMethod(
  ClassElement cls,
  TypeChecker checker,
  String annotation,
  String scope,
) {
  final matches =
      cls.methods.where((m) => checker.hasAnnotationOf(m)).toList();
  if (matches.isEmpty) return (name: null, awaited: false);
  if (matches.length > 1) {
    throw DianaSourceError(
      cls,
      'Class ${cls.name} declares multiple @$annotation methods; declare at '
      'most one.',
    );
  }
  final method = matches.single;
  final returnType = method.returnType;
  final returnsFutureVoid = returnType is InterfaceType &&
      returnType.isDartAsyncFuture &&
      returnType.typeArguments.single is VoidType;
  final validSignature = !method.isStatic &&
      !method.name!.startsWith('_') &&
      method.formalParameters.isEmpty &&
      (returnType is VoidType || returnsFutureVoid);
  if (!validSignature) {
    throw DianaSourceError(
      method,
      '@$annotation method ${cls.name}.${method.name} must be a public '
      'instance method with no parameters returning void or Future<void>.',
    );
  }
  if (scope != 'singleton') {
    throw DianaSourceError(
      method,
      '@$annotation on ${cls.name} requires singleton scope; found $scope.',
    );
  }
  return (name: method.name!, awaited: returnsFutureVoid);
}

bool _isDianaRequest(DartType type) => _isDianaType(type, 'DianaRequest');

bool _isDianaResponse(DartType type) => _isDianaType(type, 'DianaResponse');

bool _isDianaType(DartType type, String name) =>
    type is InterfaceType &&
    type.element.name == name &&
    type.element.library.uri.toString().startsWith('package:diana/');

int _supertypeDepth(InterfaceType type) {
  var depth = 0;
  InterfaceType? current = type;
  while (current != null && !current.isDartCoreObject) {
    depth++;
    current = current.element.supertype;
  }
  return depth;
}

/// Public entry for other readers.
TypeRef typeRefOf(DartType type, Element context) => _typeRefOf(type, context);

TypeRef _typeRefOf(DartType type, Element context) {
  if (type is! InterfaceType) {
    throw DianaSourceError(
      context,
      'Unsupported type ${type.getDisplayString()}: only class types are '
      'supported here.',
    );
  }
  final name = type.element.name;
  if (name == null) {
    throw DianaSourceError(context, 'Unnamed types are not supported.');
  }
  return TypeRef(
    libraryUri: type.element.library.uri.toString(),
    name: name,
    typeArgs: [for (final a in type.typeArguments) _typeRefOf(a, context)],
    nullable: type.nullabilitySuffix == NullabilitySuffix.question,
  );
}
