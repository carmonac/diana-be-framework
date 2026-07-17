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

    _checkSecurityPlacement(
      cls,
      isController: controllerAnn != null,
      isSecurable:
          controllerAnn != null || wsAnn != null || grpcAnn != null,
    );

    // @Transactional is proxied, so it is valid only on @Injectable-family
    // providers (services/components/repositories), never controllers,
    // advices, config-props, etc.
    _checkAspectPlacement(cls, isInjectable: injectableAnn != null);

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
        security: _securityOf(cls, cls.name!),
      ));
    } else if (grpcAnn != null) {
      injectables.add(_withLifecycle(cls, InjectableInfo(
        type: selfType,
        scope: 'singleton',
        supertypes: _supertypeRefs(cls),
        ctorParams: _ctorParams(cls),
      )));
      grpcServices.add(GrpcServiceInfo(
        type: selfType,
        security: _securityOf(cls, cls.name!),
      ));
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
    eventListeners: _eventListenersOf(cls, scope),
    aspectMethods: _aspectMethodsOf(cls),
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
      security: _securityOf(method, '${cls.name}.${method.name}'),
      api: apiByMethod[method.name],
    ));
  }
  return ControllerInfo(
    type: selfType,
    basePath: ann.getField('path')?.toStringValue() ?? '/',
    middleware: _useMiddlewareTypes(cls),
    routes: routes,
    cors: _corsOf(cls),
    security: _securityOf(cls, cls.name!),
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

/// Reads `@Secured`/`@RolesAllowed` on [element]. `@RolesAllowed` wins
/// over `@Secured` (it subsumes it). Throws when the role list is empty.
SecurityInfo? _securityOf(Element element, String where) {
  final rolesAnn = rolesAllowedChecker.firstAnnotationOf(element);
  if (rolesAnn != null) {
    final roles = rolesAnn
            .getField('roles')
            ?.toListValue()
            ?.map((e) => e.toStringValue()!)
            .toList() ??
        const [];
    if (roles.isEmpty) {
      throw DianaSourceError(element, '@RolesAllowed on $where lists no roles.');
    }
    return SecurityInfo(roles: roles);
  }
  if (securedChecker.firstAnnotationOf(element) != null) {
    return const SecurityInfo();
  }
  return null;
}

/// Rejects `@Secured`/`@RolesAllowed` on elements where they would be
/// silently ignored — a security annotation with no effect is a hole the
/// user believes is closed.
void _checkSecurityPlacement(
  ClassElement cls, {
  required bool isController,
  required bool isSecurable,
}) {
  bool hasSecurity(Element e) =>
      securedChecker.firstAnnotationOf(e) != null ||
      rolesAllowedChecker.firstAnnotationOf(e) != null;

  if (!isSecurable && hasSecurity(cls)) {
    throw DianaSourceError(cls, _misplacedSecurity(cls.name!));
  }
  for (final method in cls.methods) {
    if (!hasSecurity(method)) continue;
    final isRoute =
        isController && httpRouteChecker.firstAnnotationOf(method) != null;
    if (!isRoute) {
      throw DianaSourceError(
        method,
        _misplacedSecurity('${cls.name}.${method.name}'),
      );
    }
  }
}

String _misplacedSecurity(String where) =>
    '@Secured/@RolesAllowed on $where has no effect: it is not a REST '
    'controller, WebSocket controller, gRPC service, or route method.';

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

/// Re-creates [info] with the class's lifecycle, scheduled and
/// event-listener methods attached.
InjectableInfo _withLifecycle(ClassElement cls, InjectableInfo info) {
  final lifecycle = _lifecycleOf(cls, info.scope);
  final scheduled = _scheduledOf(cls, info.scope);
  final eventListeners = _eventListenersOf(cls, info.scope);
  if (lifecycle.postConstruct == null &&
      lifecycle.preDestroy == null &&
      scheduled.isEmpty &&
      eventListeners.isEmpty) {
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
    eventListeners: eventListeners,
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
      perIsolate: ann.getField('perIsolate')?.toBoolValue() ?? false,
    ));
  }
  return result;
}

/// Reads `@EventListener` methods, validating signatures, the event
/// parameter type and scope.
List<EventListenerInfo> _eventListenersOf(ClassElement cls, String scope) {
  final result = <EventListenerInfo>[];
  for (final method in cls.methods) {
    final ann = eventListenerChecker.firstAnnotationOf(method);
    if (ann == null) continue;
    final returnType = method.returnType;
    final returnsFutureVoid = returnType is InterfaceType &&
        returnType.isDartAsyncFuture &&
        returnType.typeArguments.single is VoidType;
    final params = method.formalParameters;
    final validSignature = !method.isStatic &&
        !method.name!.startsWith('_') &&
        params.length == 1 &&
        params.single.isRequiredPositional &&
        (returnType is VoidType || returnsFutureVoid);
    if (!validSignature) {
      throw DianaSourceError(
        method,
        '@EventListener method ${cls.name}.${method.name} must be a public '
        'instance method with exactly one positional parameter returning '
        'void or Future<void>.',
      );
    }
    final param = params.single;
    final paramType = param.type;
    if (paramType is! InterfaceType ||
        paramType.nullabilitySuffix != NullabilitySuffix.none) {
      throw DianaSourceError(
        method,
        '@EventListener parameter "${param.name}" of '
        '${cls.name}.${method.name} must be a non-nullable class type; '
        'found ${paramType.getDisplayString()}.',
      );
    }
    if (scope != 'singleton') {
      throw DianaSourceError(
        method,
        '@EventListener on ${cls.name} requires singleton scope; '
        'found $scope.',
      );
    }
    result.add(EventListenerInfo(
      methodName: method.name!,
      eventType: _typeRefOf(paramType, method),
    ));
  }
  return result;
}

/// Reads aspect-annotated methods — `@Transactional` (directly annotated,
/// or every eligible method when the class carries it) plus the
/// method-level `@Timed`/`@Cacheable`/`@Retryable`/`@CircuitBreaker` —
/// capturing each signature so the generated proxy can re-declare a
/// faithful override.
List<AspectMethodInfo> _aspectMethodsOf(ClassElement cls) {
  final classAnnotated = transactionalChecker.firstAnnotationOf(cls) != null;

  const newAspects = [
    (checker: timedChecker, name: 'Timed'),
    (checker: cacheableChecker, name: 'Cacheable'),
    (checker: retryableChecker, name: 'Retryable'),
    (checker: circuitBreakerChecker, name: 'CircuitBreaker'),
  ];
  // Method-level only: a class-level default for cache/retry/breaker/timed
  // invites silent misconfiguration (one TTL for every method, ...).
  for (final aspect in newAspects) {
    if (aspect.checker.firstAnnotationOf(cls) != null) {
      throw DianaSourceError(
        cls,
        '@${aspect.name} is method-level only; annotate individual methods '
        'of ${cls.name}.',
      );
    }
  }

  String? newAspectNameOf(MethodElement m) {
    for (final aspect in newAspects) {
      if (aspect.checker.firstAnnotationOf(m) != null) return aspect.name;
    }
    return null;
  }

  final annotated = [
    for (final method in cls.methods)
      if (classAnnotated ||
          transactionalChecker.firstAnnotationOf(method) != null ||
          newAspectNameOf(method) != null)
        method,
  ];
  if (annotated.isEmpty) return const [];

  // The proxy is a generated subclass, so the class must be extendable.
  // Transactional-only classes keep the historical message.
  if (cls.isFinal || cls.isBase || cls.isSealed) {
    if (annotated.any((m) => newAspectNameOf(m) != null)) {
      throw DianaSourceError(
        cls,
        'Aspect-annotated class ${cls.name} must be extendable: remove the '
        'final/base/sealed modifier so Diana can generate an aspect proxy '
        'subclass.',
      );
    }
    throw DianaSourceError(
      cls,
      '@Transactional class ${cls.name} must be extendable: remove the '
      'final/base/sealed modifier so Diana can generate a transactional '
      'proxy subclass.',
    );
  }

  final result = <AspectMethodInfo>[];
  for (final method in annotated) {
    final directTx = transactionalChecker.firstAnnotationOf(method) != null;
    final newAspectName = newAspectNameOf(method);

    if (method.isStatic || method.name!.startsWith('_')) {
      if (newAspectName != null) {
        throw DianaSourceError(
          method,
          '@$newAspectName method ${cls.name}.${method.name} must be a '
          'public instance method.',
        );
      }
      // Class-level @Transactional silently skips these; a direct annotation
      // on one is caught by the placement check.
      if (classAnnotated) continue;
    }
    final returnType = method.returnType;
    final returnsFuture =
        returnType is InterfaceType && returnType.isDartAsyncFuture;
    if (!returnsFuture) {
      if (directTx && !classAnnotated) {
        throw DianaSourceError(
          method,
          '@Transactional method ${cls.name}.${method.name} must return Future '
          '(transactions are asynchronous); found '
          '${returnType.getDisplayString()}.',
        );
      }
      if (newAspectName != null) {
        throw DianaSourceError(
          method,
          '@$newAspectName method ${cls.name}.${method.name} must return '
          'Future (aspect proxies are asynchronous); found '
          '${returnType.getDisplayString()}.',
        );
      }
      continue; // class-level @Transactional: only proxy Future methods
    }

    TimedInfo? timed;
    final timedAnn = timedChecker.firstAnnotationOf(method);
    if (timedAnn != null) {
      final name = timedAnn.getField('name')?.toStringValue();
      if (name != null && name.isEmpty) {
        throw DianaSourceError(
          method,
          '@Timed name on ${cls.name}.${method.name} must not be empty.',
        );
      }
      timed = TimedInfo(name: name);
    }

    CacheableInfo? cacheable;
    final cacheableAnn = cacheableChecker.firstAnnotationOf(method);
    if (cacheableAnn != null) {
      // The proxy's cache field is typed on the concrete value type, so
      // generic methods and void results cannot be cached.
      if (method.typeParameters.isNotEmpty) {
        throw DianaSourceError(
          method,
          '@Cacheable method ${cls.name}.${method.name} declares type '
          'parameters; caching generic methods is not supported.',
        );
      }
      if (returnType.typeArguments.single is VoidType) {
        throw DianaSourceError(
          method,
          '@Cacheable method ${cls.name}.${method.name} must return '
          'Future<T> with a non-void T (a void result cannot be cached); '
          'found Future<void>.',
        );
      }
      final ttl = cacheableAnn.getField('ttlSeconds')?.toIntValue() ?? 60;
      final max = cacheableAnn.getField('maxEntries')?.toIntValue() ?? 1024;
      if (ttl < 1) {
        throw DianaSourceError(
          method,
          '@Cacheable on ${cls.name}.${method.name} requires '
          'ttlSeconds >= 1; found $ttl.',
        );
      }
      if (max < 1) {
        throw DianaSourceError(
          method,
          '@Cacheable on ${cls.name}.${method.name} requires '
          'maxEntries >= 1; found $max.',
        );
      }
      cacheable = CacheableInfo(ttlSeconds: ttl, maxEntries: max);
    }

    RetryableInfo? retryable;
    final retryAnn = retryableChecker.firstAnnotationOf(method);
    if (retryAnn != null) {
      final attempts = retryAnn.getField('maxAttempts')?.toIntValue() ?? 3;
      final backoff = retryAnn.getField('backoffMs')?.toIntValue() ?? 200;
      if (attempts < 1) {
        throw DianaSourceError(
          method,
          '@Retryable on ${cls.name}.${method.name} requires '
          'maxAttempts >= 1; found $attempts.',
        );
      }
      if (backoff < 0) {
        throw DianaSourceError(
          method,
          '@Retryable on ${cls.name}.${method.name} requires '
          'backoffMs >= 0; found $backoff.',
        );
      }
      final entries = retryAnn.getField('retryOn')?.toListValue() ?? const [];
      retryable = RetryableInfo(
        maxAttempts: attempts,
        backoffMs: backoff,
        retryOn: [
          for (final item in entries)
            _typeRefOf(
                item.toTypeValue() ??
                    (throw DianaSourceError(
                      method,
                      '@Retryable retryOn entries must be type literals.',
                    )),
                method),
        ],
      );
    }

    CircuitBreakerInfo? circuitBreaker;
    final breakerAnn = circuitBreakerChecker.firstAnnotationOf(method);
    if (breakerAnn != null) {
      final threshold =
          breakerAnn.getField('failureThreshold')?.toIntValue() ?? 5;
      final reset = breakerAnn.getField('resetTimeoutMs')?.toIntValue() ?? 30000;
      if (threshold < 1) {
        throw DianaSourceError(
          method,
          '@CircuitBreaker on ${cls.name}.${method.name} requires '
          'failureThreshold >= 1; found $threshold.',
        );
      }
      if (reset < 1) {
        throw DianaSourceError(
          method,
          '@CircuitBreaker on ${cls.name}.${method.name} requires '
          'resetTimeoutMs >= 1; found $reset.',
        );
      }
      circuitBreaker = CircuitBreakerInfo(
        failureThreshold: threshold,
        resetTimeoutMs: reset,
      );
    }

    result.add(AspectMethodInfo(
      methodName: method.name!,
      returnType: _typeRefLenient(returnType, method),
      typeParams: [
        for (final tp in method.typeParameters)
          TypeParamInfo(
            name: tp.name!,
            bound: tp.bound == null
                ? null
                : _typeRefLenient(tp.bound!, method),
          ),
      ],
      params: [
        for (final param in method.formalParameters)
          AspectParamInfo(
            name: param.name!,
            type: _typeRefLenient(param.type, param),
            kind: param.isNamed
                ? 'named'
                : param.isOptionalPositional
                    ? 'optionalPositional'
                    : 'requiredPositional',
            required: param.isRequiredPositional || param.isRequiredNamed,
            defaultCode: param.defaultValueCode,
          ),
      ],
      transactional: classAnnotated || directTx,
      timed: timed,
      cacheable: cacheable,
      retryable: retryable,
      circuitBreaker: circuitBreaker,
    ));
  }
  return result;
}

/// Rejects aspect annotations where the generator can't proxy them (not a
/// service/component/repository provider).
void _checkAspectPlacement(
  ClassElement cls, {
  required bool isInjectable,
}) {
  const aspects = [
    (checker: transactionalChecker, name: 'Transactional'),
    (checker: timedChecker, name: 'Timed'),
    (checker: cacheableChecker, name: 'Cacheable'),
    (checker: retryableChecker, name: 'Retryable'),
    (checker: circuitBreakerChecker, name: 'CircuitBreaker'),
  ];
  for (final aspect in aspects) {
    bool has(Element e) => aspect.checker.firstAnnotationOf(e) != null;
    if ((has(cls) || cls.methods.any(has)) && !isInjectable) {
      throw DianaSourceError(
        cls,
        '@${aspect.name} on ${cls.name} has no effect: it is not a '
        '@Service/@Component/@Repository provider.',
      );
    }
  }
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

/// Like [_typeRefOf] but tolerant of `void`/`dynamic`/non-class types in
/// (type-argument) positions — used to re-declare `@Transactional` method
/// signatures faithfully (e.g. `Future<void>`). A URI-less [TypeRef] renders
/// as a bare symbol with no import.
TypeRef _typeRefLenient(DartType type, Element context) {
  if (type is VoidType) return const TypeRef(libraryUri: '', name: 'void');
  if (type is DynamicType) {
    return const TypeRef(libraryUri: '', name: 'dynamic');
  }
  if (type is! InterfaceType || type.element.name == null) {
    return TypeRef(libraryUri: '', name: type.getDisplayString());
  }
  return TypeRef(
    libraryUri: type.element.library.uri.toString(),
    name: type.element.name!,
    typeArgs: [for (final a in type.typeArguments) _typeRefLenient(a, context)],
    nullable: type.nullabilitySuffix == NullabilitySuffix.question,
  );
}

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
