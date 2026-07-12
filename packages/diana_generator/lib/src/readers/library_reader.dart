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

import '../model/summary.dart';
import 'checkers.dart';

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
  final globalMiddleware = <GlobalMiddlewareInfo>[];
  final advices = <AdviceInfo>[];
  AppInfo? app;

  for (final cls in library.classes) {
    final injectableAnn = injectableChecker.firstAnnotationOf(cls);
    final controllerAnn = restControllerChecker.firstAnnotationOf(cls);
    final gmAnn = globalMiddlewareChecker.firstAnnotationOf(cls);
    final adviceAnn = controllerAdviceChecker.firstAnnotationOf(cls);
    final configPropsAnn = configPropsChecker.firstAnnotationOf(cls);
    final appAnn = dianaApplicationChecker.firstAnnotationOf(cls);

    final roles = [
      if (injectableAnn != null) '@Injectable/@Service/@Repository/@Component',
      if (controllerAnn != null) '@RestController',
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
      injectables.add(InjectableInfo(
        type: selfType,
        scope: scope,
        supertypes: _supertypeRefs(cls),
        ctorParams: _ctorParams(cls),
      ));
      controllers.add(_controllerFrom(cls, selfType, controllerAnn));
    } else if (gmAnn != null) {
      injectables.add(InjectableInfo(
        type: selfType,
        scope: 'singleton',
        supertypes: _supertypeRefs(cls),
        ctorParams: _ctorParams(cls),
      ));
      globalMiddleware.add(GlobalMiddlewareInfo(
        type: selfType,
        order: gmAnn.getField('order')?.toIntValue() ?? 0,
      ));
    } else if (adviceAnn != null) {
      injectables.add(InjectableInfo(
        type: selfType,
        scope: 'singleton',
        supertypes: _supertypeRefs(cls),
        ctorParams: _ctorParams(cls),
      ));
      advices.add(_adviceFrom(cls, selfType));
    } else if (configPropsAnn != null) {
      injectables.add(InjectableInfo(
        type: selfType,
        scope: 'singleton',
        kind: ProviderKind.configProps,
        configPrefix:
            configPropsAnn.getField('prefix')?.toStringValue() ?? '',
      ));
    }
  }

  return LibrarySummary(
    libraryUri: library.uri.toString(),
    injectables: injectables,
    controllers: controllers,
    globalMiddleware: globalMiddleware,
    advices: advices,
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
  return InjectableInfo(
    type: selfType,
    scope: _scopeName(_constField(ann, 'scope')),
    qualifier: _constField(ann, 'name')?.toStringValue(),
    explicitAs: explicitAs,
    supertypes: _supertypeRefs(cls),
    ctorParams: _ctorParams(cls),
  );
}

ControllerInfo _controllerFrom(
  ClassElement cls,
  TypeRef selfType,
  DartObject ann,
) {
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
    ));
  }
  return ControllerInfo(
    type: selfType,
    basePath: ann.getField('path')?.toStringValue() ?? '/',
    middleware: _useMiddlewareTypes(cls),
    routes: routes,
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
