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
import 'json_reader.dart' show isJsonClass, readJsonClass;

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
      isSecurable: controllerAnn != null || wsAnn != null || grpcAnn != null,
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

    // An abstract class directly extending DianaRepository is a query
    // repository: the generator implements it, so the abstract guard is
    // lifted for it (and only for it).
    final repoSuper = injectableAnn != null ? _queryRepoSuper(cls) : null;
    final isQueryRepo = cls.isAbstract && repoSuper != null;

    _checkProviderClass(cls, allowAbstract: isQueryRepo);
    final selfType = _selfTypeRef(cls);

    if (injectableAnn != null) {
      injectables.add(
        _injectableFrom(cls, selfType, injectableAnn,
            queryRepo: cls.isAbstract && repoSuper != null
                ? _queryRepoOf(cls, repoSuper)
                : null),
      );
    } else if (controllerAnn != null) {
      final scope = _scopeName(controllerAnn.getField('scope'));
      injectables.add(_withLifecycle(
          cls,
          InjectableInfo(
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
      injectables.add(_withLifecycle(
          cls,
          InjectableInfo(
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
      injectables.add(_withLifecycle(
          cls,
          InjectableInfo(
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
      injectables.add(_withLifecycle(
          cls,
          InjectableInfo(
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
      injectables.add(_withLifecycle(
          cls,
          InjectableInfo(
            type: selfType,
            scope: 'singleton',
            supertypes: _supertypeRefs(cls),
            ctorParams: _ctorParams(cls),
          )));
      advices.add(_adviceFrom(cls, selfType));
    } else if (configPropsAnn != null) {
      injectables.add(_withLifecycle(
          cls,
          InjectableInfo(
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

void _checkProviderClass(ClassElement cls, {bool allowAbstract = false}) {
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
  if (cls.isAbstract && !allowAbstract) {
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
  DartObject ann, {
  QueryRepoInfo? queryRepo,
}) {
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
    queryRepo: queryRepo,
    messageMappings: _messageMappingsOf(cls, scope),
  );
}

/// The direct `DianaRepository<E>` supertype from `package:diana_data`, or
/// null when [cls] does not directly extend it.
InterfaceType? _queryRepoSuper(ClassElement cls) {
  final superType = cls.supertype;
  if (superType == null) return null;
  final element = superType.element;
  if (element.name != 'DianaRepository') return null;
  if (!element.library.uri.toString().startsWith('package:diana_data/')) {
    return null;
  }
  return superType;
}

/// Everything a query repository needs, snapshotted from the entity at
/// read time (the entity may live in another library): table, id column,
/// per-property columns and types, and every parsed query method.
QueryRepoInfo _queryRepoOf(ClassElement cls, InterfaceType superType) {
  final name = cls.name!;

  // Entity resolution and validation.
  final typeArgs = superType.typeArguments;
  final entityType = typeArgs.length == 1 ? typeArgs.single : null;
  final entityElement = entityType is InterfaceType ? entityType.element : null;
  if (entityElement is! ClassElement || entityElement.name == null) {
    throw DianaSourceError(
      cls,
      'Query repository $name must extend DianaRepository<E> with a '
      'concrete class type argument.',
    );
  }
  final entityName = entityElement.name!;
  if (!isJsonClass(entityElement)) {
    throw DianaSourceError(
      cls,
      'Query repository $name targets $entityName, which is not a @Json '
      'class. Annotate $entityName with @Json() so rows can be mapped to '
      'instances.',
    );
  }
  final tableAnn = tableChecker.firstAnnotationOf(entityElement);
  final table = tableAnn?.getField('name')?.toStringValue();
  if (table == null) {
    throw DianaSourceError(
      cls,
      'Query repository $name targets $entityName, which is missing @Table. '
      "Annotate $entityName with @Table('table_name').",
    );
  }

  // Property catalog: field name → column (jsonName) and field type.
  final jsonModel = readJsonClass(entityElement);
  final columns = <String, String>{
    for (final field in jsonModel.fields) field.fieldName: field.jsonName,
  };
  final fieldTypes = <String, TypeRef>{
    for (final field in entityElement.fields)
      if (!field.isStatic && !field.name!.startsWith('_'))
        field.name!: _typeRefLenient(field.type, field),
  };
  final idColumn = columns['id'];
  if (idColumn == null) {
    throw DianaSourceError(
      cls,
      "Query repository $name targets $entityName, which has no 'id' "
      'field; DianaRepository.findById/deleteById need one.',
    );
  }

  // Aspects cannot proxy generated implementations (yet).
  if (_aspectMethodsOf(cls).isNotEmpty) {
    throw DianaSourceError(
      cls,
      'Query repository $name declares aspect-annotated methods; '
      '@Transactional/@Timed/@Cacheable/@Retryable/@CircuitBreaker are not '
      'supported on query repositories in this version. Move them to a '
      'service that injects $name.',
    );
  }

  // Abstract non-method members cannot be implemented by the generator.
  for (final getter in cls.getters) {
    if (getter.isAbstract) {
      throw DianaSourceError(
        getter,
        'Query repository $name declares abstract member '
        '"${getter.name}" which is not a method; only query methods can '
        'be abstract.',
      );
    }
  }
  for (final setter in cls.setters) {
    if (setter.isAbstract) {
      throw DianaSourceError(
        setter,
        'Query repository $name declares abstract member '
        '"${setter.name}" which is not a method; only query methods can '
        'be abstract.',
      );
    }
  }

  const crudNames = {'findAll', 'findById', 'save', 'deleteById'};
  final entityRef = _typeRefOf(entityType!, cls);
  final methods = <QueryMethodInfo>[];
  for (final method in cls.methods) {
    final methodName = method.name!;
    if (crudNames.contains(methodName)) {
      throw DianaSourceError(
        method,
        'Query repository $name re-declares "$methodName", which is '
        'implemented by the generated repository; remove the declaration.',
      );
    }
    if (!method.isAbstract) continue; // concrete helpers are inherited
    methods.add(_parseQueryMethod(
      method,
      className: name,
      entity: entityRef,
      entityName: entityName,
      columns: columns,
      fieldTypes: fieldTypes,
    ));
  }

  return QueryRepoInfo(
    entity: entityRef,
    table: table,
    idColumn: idColumn,
    methods: methods,
  );
}

/// Operator suffixes by descending length (longest-match), with their
/// condition op, parameter arity, and whether they need a String property.
const List<({String suffix, String op, int arity, bool stringOnly})> _queryOps =
    [
  (suffix: 'GreaterThanEqual', op: 'gte', arity: 1, stringOnly: false),
  (suffix: 'LessThanEqual', op: 'lte', arity: 1, stringOnly: false),
  (suffix: 'GreaterThan', op: 'gt', arity: 1, stringOnly: false),
  (suffix: 'StartsWith', op: 'startsWith', arity: 1, stringOnly: true),
  (suffix: 'IsNotNull', op: 'isNotNull', arity: 0, stringOnly: false),
  (suffix: 'LessThan', op: 'lt', arity: 1, stringOnly: false),
  (suffix: 'EndsWith', op: 'endsWith', arity: 1, stringOnly: true),
  (suffix: 'Contains', op: 'contains', arity: 1, stringOnly: true),
  (suffix: 'Between', op: 'between', arity: 2, stringOnly: false),
  (suffix: 'IsNull', op: 'isNull', arity: 0, stringOnly: false),
  (suffix: 'NotIn', op: 'notIn', arity: 1, stringOnly: false),
  (suffix: 'Like', op: 'like', arity: 1, stringOnly: true),
  (suffix: 'Not', op: 'not', arity: 1, stringOnly: false),
  (suffix: 'In', op: 'inList', arity: 1, stringOnly: false),
];

QueryMethodInfo _parseQueryMethod(
  MethodElement method, {
  required String className,
  required TypeRef entity,
  required String entityName,
  required Map<String, String> columns,
  required Map<String, TypeRef> fieldTypes,
}) {
  final methodName = method.name!;
  final id = '$className.$methodName';
  final knownProps = columns.keys.join(', ');

  if (method.typeParameters.isNotEmpty) {
    throw DianaSourceError(
      method,
      'Query method $id must not declare type parameters.',
    );
  }

  // Subject prefix (longest first: findFirstBy before findBy).
  const subjects = [
    (prefix: 'findFirstBy', subject: 'findFirst'),
    (prefix: 'findBy', subject: 'find'),
    (prefix: 'countBy', subject: 'count'),
    (prefix: 'existsBy', subject: 'exists'),
    (prefix: 'deleteBy', subject: 'delete'),
  ];
  final match =
      subjects.where((s) => methodName.startsWith(s.prefix)).firstOrNull;
  if (match == null) {
    throw DianaSourceError(
      method,
      'Query method $id must start with findBy, findFirstBy, countBy, '
      'existsBy or deleteBy.',
    );
  }
  final subject = match.subject;
  var rest = methodName.substring(match.prefix.length);

  // OrderBy split (first occurrence).
  String? orderRest;
  final orderIdx = rest.indexOf('OrderBy');
  if (orderIdx != -1) {
    orderRest = rest.substring(orderIdx + 'OrderBy'.length);
    rest = rest.substring(0, orderIdx);
    if (subject == 'count' || subject == 'exists' || subject == 'delete') {
      throw DianaSourceError(
        method,
        'OrderBy is not supported on countBy/existsBy/deleteBy '
        '(query method $id).',
      );
    }
  }
  if (rest.isEmpty) {
    throw DianaSourceError(
      method,
      'Query method $id declares no conditions; add at least one property '
      'after the prefix.',
    );
  }

  String upper(String s) => s[0].toUpperCase() + s.substring(1);

  // Longest-match property lookup at [pos]; null when nothing matches.
  String? matchProp(String source, int pos) {
    String? best;
    for (final prop in columns.keys) {
      final segment = upper(prop);
      if (source.startsWith(segment, pos)) {
        if (best == null || prop.length > best.length) best = prop;
      }
    }
    return best;
  }

  // Predicate loop.
  final conditions = <QueryConditionInfo>[];
  final conditionMeta =
      <({String prop, String op, int arity, bool stringOnly, String label})>[];
  String? connector;
  var pos = 0;
  while (true) {
    final prop = matchProp(rest, pos);
    if (prop == null) {
      throw DianaSourceError(
        method,
        'Cannot parse query method $id at "${rest.substring(pos)}": '
        'expected a property of $entityName followed by an optional '
        'condition. Known properties: $knownProps.',
      );
    }
    pos += prop.length;
    var op = 'eq';
    var arity = 1;
    var stringOnly = false;
    var label = upper(prop);
    for (final candidate in _queryOps) {
      if (rest.startsWith(candidate.suffix, pos)) {
        op = candidate.op;
        arity = candidate.arity;
        stringOnly = candidate.stringOnly;
        label = '${upper(prop)}${candidate.suffix}';
        pos += candidate.suffix.length;
        break;
      }
    }
    conditions.add(QueryConditionInfo(column: columns[prop]!, op: op));
    conditionMeta.add((
      prop: prop,
      op: op,
      arity: arity,
      stringOnly: stringOnly,
      label: label
    ));
    if (pos == rest.length) break;
    String next;
    if (rest.startsWith('And', pos)) {
      next = 'and';
      pos += 3;
    } else if (rest.startsWith('Or', pos)) {
      next = 'or';
      pos += 2;
    } else {
      throw DianaSourceError(
        method,
        'Cannot parse query method $id at "${rest.substring(pos)}": '
        'expected a property of $entityName followed by an optional '
        'condition. Known properties: $knownProps.',
      );
    }
    if (connector != null && next != connector) {
      throw DianaSourceError(
        method,
        'Query method $id mixes And and Or; a method may use only one '
        'connector.',
      );
    }
    connector = next;
  }

  // The query builder has no orWhereIn (knex_dart 1.3); forbid the combo.
  if (connector == 'or' && conditions.any((c) => c.op == 'inList')) {
    throw DianaSourceError(
      method,
      'Query method $id combines In with the Or connector, which the query '
      'builder cannot express; use And.',
    );
  }

  // Order clause.
  final orderBy = <QueryOrderInfo>[];
  if (orderRest != null) {
    var opos = 0;
    while (opos < orderRest.length) {
      final prop = matchProp(orderRest, opos);
      if (prop == null) {
        throw DianaSourceError(
          method,
          'Cannot parse the OrderBy clause of query method $id at '
          '"${orderRest.substring(opos)}": expected <Property>Asc or '
          '<Property>Desc. Known properties: $knownProps.',
        );
      }
      opos += prop.length;
      bool desc;
      if (orderRest.startsWith('Asc', opos)) {
        desc = false;
        opos += 3;
      } else if (orderRest.startsWith('Desc', opos)) {
        desc = true;
        opos += 4;
      } else {
        throw DianaSourceError(
          method,
          'Cannot parse the OrderBy clause of query method $id at '
          '"${orderRest.substring(opos)}": expected <Property>Asc or '
          '<Property>Desc. Known properties: $knownProps.',
        );
      }
      orderBy.add(QueryOrderInfo(column: columns[prop]!, desc: desc));
    }
  }

  // Parameters: required positional only, count == sum of arities.
  for (final param in method.formalParameters) {
    if (param.isNamed || param.isOptional) {
      throw DianaSourceError(
        method,
        'Query method $id must declare only required positional parameters.',
      );
    }
  }
  final expected = conditionMeta.fold<int>(0, (sum, c) => sum + c.arity);
  final params = method.formalParameters;
  if (params.length != expected) {
    throw DianaSourceError(
      method,
      'Query method $id declares ${params.length} parameter(s) but its '
      'conditions take $expected.',
    );
  }

  // Per-slot type checks.
  var slot = 0;
  for (final meta in conditionMeta) {
    final fieldType = fieldTypes[meta.prop]!;
    if (meta.stringOnly && fieldType.name != 'String') {
      throw DianaSourceError(
        method,
        'Condition "${meta.label}" of query method $id needs a '
        "String-typed property; '${meta.prop}' of $entityName is "
        '${fieldType.displayName}.',
      );
    }
    for (var i = 0; i < meta.arity; i++) {
      final param = params[slot++];
      final paramType = _typeRefLenient(param.type, param);
      final String expectedDisplay;
      final bool ok;
      if (meta.op == 'inList' || meta.op == 'notIn') {
        expectedDisplay = 'List<${fieldType.displayName}>';
        ok = paramType.name == 'List' &&
            paramType.typeArgs.length == 1 &&
            paramType.typeArgs.single.key == fieldType.key;
      } else {
        expectedDisplay = fieldType.displayName;
        ok = paramType.key == fieldType.key;
      }
      if (!ok) {
        throw DianaSourceError(
          method,
          'Parameter "${param.name}" of query method $id must be '
          '$expectedDisplay for condition "${meta.label}"; got '
          '${paramType.displayName}.',
        );
      }
    }
  }

  // Return-type contract per subject.
  final returnType = _typeRefLenient(method.returnType, method);
  bool isFutureOf(bool Function(TypeRef inner) check) =>
      returnType.name == 'Future' &&
      returnType.typeArgs.length == 1 &&
      check(returnType.typeArgs.single);
  final ok = switch (subject) {
    'find' => isFutureOf((t) =>
        t.name == 'List' &&
        t.typeArgs.length == 1 &&
        t.typeArgs.single.key == entity.key),
    'findFirst' => isFutureOf((t) => t.key == entity.key && t.nullable),
    'count' => isFutureOf((t) => t.name == 'int'),
    'exists' => isFutureOf((t) => t.name == 'bool'),
    _ => isFutureOf((t) => t.name == 'void'),
  };
  if (!ok) {
    final expectedReturn = switch (subject) {
      'find' => 'Future<List<${entity.name}>> (findBy)',
      'findFirst' => 'Future<${entity.name}?> (findFirstBy)',
      'count' => 'Future<int> (countBy)',
      'exists' => 'Future<bool> (existsBy)',
      _ => 'Future<void> (deleteBy)',
    };
    throw DianaSourceError(
      method,
      'Query method $id must return $expectedReturn; got '
      '${returnType.displayName}.',
    );
  }

  return QueryMethodInfo(
    name: methodName,
    subject: subject,
    connector: connector ?? 'and',
    conditions: conditions,
    orderBy: orderBy,
    params: [
      for (final param in params)
        QueryParamInfo(
          name: param.name!,
          type: _typeRefLenient(param.type, param),
        ),
    ],
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
      nullable: field.type.nullabilitySuffix == NullabilitySuffix.question,
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
      throw DianaSourceError(
          element, '@RolesAllowed on $where lists no roles.');
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
  final post =
      _lifecycleMethod(cls, postConstructChecker, 'PostConstruct', scope);
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
  final messageMappings = _messageMappingsOf(cls, info.scope);
  if (lifecycle.postConstruct == null &&
      lifecycle.preDestroy == null &&
      scheduled.isEmpty &&
      eventListeners.isEmpty &&
      messageMappings.isEmpty) {
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
    messageMappings: messageMappings,
  );
}

/// Reads `@MessageMapping` methods (STOMP), validating the signature,
/// payload/return types, `@SendTo` pairing, destination syntax and scope.
List<MessageMappingInfo> _messageMappingsOf(ClassElement cls, String scope) {
  final result = <MessageMappingInfo>[];
  for (final method in cls.methods) {
    final mappingAnn = messageMappingChecker.firstAnnotationOf(method);
    final sendToAnn = sendToChecker.firstAnnotationOf(method);
    if (mappingAnn == null) {
      if (sendToAnn != null) {
        throw DianaSourceError(
          method,
          '@SendTo on ${cls.name}.${method.name} requires @MessageMapping '
          'on the same method.',
        );
      }
      continue;
    }
    final id = '${cls.name}.${method.name}';

    if (scope != 'singleton') {
      throw DianaSourceError(
        method,
        '@MessageMapping on ${cls.name} requires singleton scope; found '
        '$scope.',
      );
    }

    final params = method.formalParameters;
    final validArity = params.isNotEmpty &&
        params.length <= 2 &&
        params.every((p) => p.isRequiredPositional);
    if (method.isStatic || method.name!.startsWith('_') || !validArity) {
      throw DianaSourceError(
        method,
        '@MessageMapping method $id must be a public instance method with '
        'one or two positional parameters: the payload (String or an @Json '
        'class), optionally followed by a StompMessage.',
      );
    }

    // Payload parameter.
    final payloadParam = params.first;
    final payloadType = payloadParam.type;
    String payloadKind;
    TypeRef? payloadRef;
    if (payloadType is InterfaceType && payloadType.isDartCoreString) {
      payloadKind = 'text';
    } else if (payloadType is InterfaceType &&
        payloadType.element is ClassElement &&
        isJsonClass(payloadType.element as ClassElement)) {
      payloadKind = 'json';
      payloadRef = _typeRefOf(payloadType, payloadParam);
    } else {
      throw DianaSourceError(
        method,
        '@MessageMapping payload parameter "${payloadParam.name}" of $id '
        'must be String or a class annotated with @Json; found '
        '${payloadType.getDisplayString()}.',
      );
    }

    // Optional StompMessage parameter.
    final wantsMessage = params.length == 2;
    if (wantsMessage) {
      final second = params[1].type;
      final ok = second is InterfaceType &&
          second.element.name == 'StompMessage' &&
          second.element.library.uri.toString().startsWith('package:diana/');
      if (!ok) {
        throw DianaSourceError(
          method,
          '@MessageMapping second parameter of $id must be StompMessage '
          'from package:diana; found ${second.getDisplayString()}.',
        );
      }
    }

    // Return type.
    final returnType = method.returnType;
    DartType inner = returnType;
    if (returnType is InterfaceType && returnType.isDartAsyncFuture) {
      inner = returnType.typeArguments.single;
    }
    String returnKind;
    TypeRef? returnRef;
    if (inner is VoidType) {
      returnKind = 'void';
    } else if (inner is InterfaceType && inner.isDartCoreString) {
      returnKind = 'text';
    } else if (inner is InterfaceType &&
        inner.element is ClassElement &&
        isJsonClass(inner.element as ClassElement)) {
      returnKind = 'json';
      returnRef = _typeRefOf(inner, method);
    } else {
      throw DianaSourceError(
        method,
        '@MessageMapping method $id returns ${returnType.getDisplayString()}; '
        'return values must be String or an @Json class (wrapped in Future '
        'if async).',
      );
    }

    // @SendTo pairing.
    final sendTo = sendToAnn?.getField('destination')?.toStringValue();
    if (returnKind == 'void' && sendTo != null) {
      throw DianaSourceError(
        method,
        '@SendTo on $id requires a non-void return value to publish.',
      );
    }
    if (returnKind != 'void' && sendTo == null) {
      throw DianaSourceError(
        method,
        '@MessageMapping method $id returns a value but has no @SendTo '
        "destination. Add @SendTo('/topic/...') or return void.",
      );
    }

    // Destination syntax.
    final destination = mappingAnn.getField('destination')!.toStringValue()!;
    if (!destination.startsWith('/')) {
      throw DianaSourceError(
        method,
        '@MessageMapping destination "$destination" on $id must start with '
        '"/".',
      );
    }
    if (sendTo != null && !sendTo.startsWith('/')) {
      throw DianaSourceError(
        method,
        '@SendTo destination "$sendTo" on $id must start with "/".',
      );
    }

    result.add(MessageMappingInfo(
      methodName: method.name!,
      destination: destination,
      payloadKind: payloadKind,
      payloadType: payloadRef,
      wantsMessage: wantsMessage,
      returnKind: returnKind,
      returnType: returnRef,
      sendTo: sendTo,
    ));
  }
  return result;
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
    final cron = ann.getField('cron')?.toStringValue();
    final provided =
        [fixedRate, fixedDelay, cron].where((v) => v != null).length;
    if (provided != 1) {
      throw DianaSourceError(
        method,
        '@Scheduled on ${cls.name}.${method.name} requires exactly one of '
        'fixedRate, fixedDelay or cron.',
      );
    }
    if (cron != null) _validateCron(method, cls, cron);
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
      cron: cron,
      initialDelayMs: ann.getField('initialDelay')?.toIntValue() ?? 0,
      perIsolate: ann.getField('perIsolate')?.toBoolValue() ?? false,
    ));
  }
  return result;
}

/// Known cron macros (mirrors `CronExpression` in `package:diana`, which the
/// generator cannot import). The reader only checks shape here — a 6-field
/// expression or a known macro; per-field range validation happens when the
/// runtime parses the expression at startup.
const _cronMacros = {
  '@yearly',
  '@annually',
  '@monthly',
  '@weekly',
  '@daily',
  '@midnight',
  '@hourly',
};

void _validateCron(MethodElement method, ClassElement cls, String cron) {
  final trimmed = cron.trim();
  if (_cronMacros.contains(trimmed.toLowerCase())) return;
  final fields = trimmed.split(RegExp(r'\s+'));
  if (fields.length != 6) {
    throw DianaSourceError(
      method,
      '@Scheduled cron on ${cls.name}.${method.name} must have 6 fields '
      '(second minute hour day-of-month month day-of-week) or be a macro '
      'like @daily; got ${fields.length}.',
    );
  }
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
      final reset =
          breakerAnn.getField('resetTimeoutMs')?.toIntValue() ?? 30000;
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
            bound: tp.bound == null ? null : _typeRefLenient(tp.bound!, method),
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
  final matches = cls.methods.where((m) => checker.hasAnnotationOf(m)).toList();
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
