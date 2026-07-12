/// Plain-data model describing every Diana-annotated declaration of a
/// library. Produced by the metadata builder, serialized as `.diana.json`,
/// consumed by the aggregating bootstrap builder.
///
/// Nothing in this file may import the analyzer: builders communicate
/// exclusively through this model.
library;

/// A fully-instantiated type reference, resolvable and printable across
/// builders.
class TypeRef {
  final String libraryUri;
  final String name;
  final List<TypeRef> typeArgs;
  final bool nullable;

  const TypeRef({
    required this.libraryUri,
    required this.name,
    this.typeArgs = const [],
    this.nullable = false,
  });

  /// Identity used for provider matching. Nullability is intentionally
  /// excluded.
  String get key =>
      '$libraryUri#$name'
      '${typeArgs.isEmpty ? '' : '<${typeArgs.map((t) => t.key).join(',')}>'}';

  /// Human-readable form for diagnostics.
  String get displayName =>
      '$name'
      '${typeArgs.isEmpty ? '' : '<${typeArgs.map((t) => t.displayName).join(', ')}>'}'
      '${nullable ? '?' : ''}';

  Map<String, Object?> toJson() => {
        'lib': libraryUri,
        'name': name,
        if (typeArgs.isNotEmpty)
          'args': [for (final t in typeArgs) t.toJson()],
        if (nullable) 'nullable': true,
      };

  factory TypeRef.fromJson(Map<String, Object?> json) => TypeRef(
        libraryUri: json['lib'] as String,
        name: json['name'] as String,
        typeArgs: [
          for (final t in (json['args'] as List<Object?>? ?? const []))
            TypeRef.fromJson((t as Map).cast<String, Object?>()),
        ],
        nullable: json['nullable'] as bool? ?? false,
      );

  @override
  bool operator ==(Object other) => other is TypeRef && other.key == key;

  @override
  int get hashCode => key.hashCode;

  @override
  String toString() => displayName;
}

/// A constructor parameter of an injectable class.
class CtorParamInfo {
  final String name;
  final bool isNamed;
  final TypeRef type;

  /// Qualifier from `@Named`, selecting a qualified provider.
  final String? qualifier;

  /// Config key from `@Value`; when set the parameter is resolved from
  /// configuration instead of the DI graph.
  final String? valueKey;

  /// JSON-encodable default from `@Value(defaultValue: ...)`.
  final Object? valueDefault;
  final bool hasValueDefault;

  const CtorParamInfo({
    required this.name,
    required this.isNamed,
    required this.type,
    this.qualifier,
    this.valueKey,
    this.valueDefault,
    this.hasValueDefault = false,
  });

  Map<String, Object?> toJson() => {
        'name': name,
        if (isNamed) 'named': true,
        'type': type.toJson(),
        if (qualifier != null) 'qualifier': qualifier,
        if (valueKey != null) 'valueKey': valueKey,
        if (hasValueDefault) 'valueDefault': valueDefault,
        if (hasValueDefault) 'hasValueDefault': true,
      };

  factory CtorParamInfo.fromJson(Map<String, Object?> json) => CtorParamInfo(
        name: json['name'] as String,
        isNamed: json['named'] as bool? ?? false,
        type: TypeRef.fromJson((json['type'] as Map).cast<String, Object?>()),
        qualifier: json['qualifier'] as String?,
        valueKey: json['valueKey'] as String?,
        valueDefault: json['valueDefault'],
        hasValueDefault: json['hasValueDefault'] as bool? ?? false,
      );
}

/// How a provider is constructed.
enum ProviderKind {
  /// Regular class instantiated through its constructor.
  normal,

  /// `@ConfigurationProperties` class built by its generated config binder.
  configProps,
}

/// A provider in the dependency injection graph. Controllers, middleware,
/// advices and configuration-properties classes are all providers too.
class InjectableInfo {
  final TypeRef type;

  /// `singleton`, `request` or `transient`.
  final String scope;
  final String? qualifier;

  /// Explicit binding from `Injectable(as: ...)`.
  final TypeRef? explicitAs;

  /// Auto-binding candidates: every non-`dart:` supertype.
  final List<TypeRef> supertypes;
  final List<CtorParamInfo> ctorParams;
  final ProviderKind kind;

  /// Prefix from `@ConfigurationProperties`.
  final String? configPrefix;

  const InjectableInfo({
    required this.type,
    required this.scope,
    this.qualifier,
    this.explicitAs,
    this.supertypes = const [],
    this.ctorParams = const [],
    this.kind = ProviderKind.normal,
    this.configPrefix,
  });

  /// Unique key of this provider in the graph.
  String get providerKey => '${type.key}|${qualifier ?? ''}';

  Map<String, Object?> toJson() => {
        'type': type.toJson(),
        'scope': scope,
        if (qualifier != null) 'qualifier': qualifier,
        if (explicitAs != null) 'as': explicitAs!.toJson(),
        if (supertypes.isNotEmpty)
          'supertypes': [for (final t in supertypes) t.toJson()],
        if (ctorParams.isNotEmpty)
          'ctorParams': [for (final p in ctorParams) p.toJson()],
        if (kind != ProviderKind.normal) 'kind': kind.name,
        if (configPrefix != null) 'configPrefix': configPrefix,
      };

  factory InjectableInfo.fromJson(Map<String, Object?> json) => InjectableInfo(
        type: TypeRef.fromJson((json['type'] as Map).cast<String, Object?>()),
        scope: json['scope'] as String,
        qualifier: json['qualifier'] as String?,
        explicitAs: json['as'] == null
            ? null
            : TypeRef.fromJson((json['as'] as Map).cast<String, Object?>()),
        supertypes: [
          for (final t in (json['supertypes'] as List<Object?>? ?? const []))
            TypeRef.fromJson((t as Map).cast<String, Object?>()),
        ],
        ctorParams: [
          for (final p in (json['ctorParams'] as List<Object?>? ?? const []))
            CtorParamInfo.fromJson((p as Map).cast<String, Object?>()),
        ],
        kind: ProviderKind.values.byName(json['kind'] as String? ?? 'normal'),
        configPrefix: json['configPrefix'] as String?,
      );
}

/// One HTTP route of a controller.
class RouteInfo {
  final String httpMethod;

  /// Path relative to the controller base path.
  final String path;
  final String methodName;

  /// Name of the generated public route adapter in the controller's part
  /// file.
  final String adapterName;
  final List<TypeRef> middleware;

  const RouteInfo({
    required this.httpMethod,
    required this.path,
    required this.methodName,
    required this.adapterName,
    this.middleware = const [],
  });

  Map<String, Object?> toJson() => {
        'method': httpMethod,
        'path': path,
        'dartMethod': methodName,
        'adapter': adapterName,
        if (middleware.isNotEmpty)
          'middleware': [for (final t in middleware) t.toJson()],
      };

  factory RouteInfo.fromJson(Map<String, Object?> json) => RouteInfo(
        httpMethod: json['method'] as String,
        path: json['path'] as String,
        methodName: json['dartMethod'] as String,
        adapterName: json['adapter'] as String,
        middleware: [
          for (final t in (json['middleware'] as List<Object?>? ?? const []))
            TypeRef.fromJson((t as Map).cast<String, Object?>()),
        ],
      );
}

/// A `@RestController` class.
class ControllerInfo {
  final TypeRef type;
  final String basePath;
  final List<TypeRef> middleware;
  final List<RouteInfo> routes;

  const ControllerInfo({
    required this.type,
    required this.basePath,
    this.middleware = const [],
    this.routes = const [],
  });

  Map<String, Object?> toJson() => {
        'type': type.toJson(),
        'basePath': basePath,
        if (middleware.isNotEmpty)
          'middleware': [for (final t in middleware) t.toJson()],
        'routes': [for (final r in routes) r.toJson()],
      };

  factory ControllerInfo.fromJson(Map<String, Object?> json) => ControllerInfo(
        type: TypeRef.fromJson((json['type'] as Map).cast<String, Object?>()),
        basePath: json['basePath'] as String,
        middleware: [
          for (final t in (json['middleware'] as List<Object?>? ?? const []))
            TypeRef.fromJson((t as Map).cast<String, Object?>()),
        ],
        routes: [
          for (final r in (json['routes'] as List<Object?>? ?? const []))
            RouteInfo.fromJson((r as Map).cast<String, Object?>()),
        ],
      );
}

/// A `@GlobalMiddleware` class.
class GlobalMiddlewareInfo {
  final TypeRef type;
  final int order;

  const GlobalMiddlewareInfo({required this.type, required this.order});

  Map<String, Object?> toJson() => {'type': type.toJson(), 'order': order};

  factory GlobalMiddlewareInfo.fromJson(Map<String, Object?> json) =>
      GlobalMiddlewareInfo(
        type: TypeRef.fromJson((json['type'] as Map).cast<String, Object?>()),
        order: json['order'] as int,
      );
}

/// One `@ExceptionHandler` method of an advice class.
class HandlerInfo {
  final TypeRef exceptionType;
  final String methodName;

  /// Whether the handler takes `(exception, DianaRequest)` rather than just
  /// `(exception)`.
  final bool takesRequest;

  /// Length of the exception type's supertype chain; deeper types are more
  /// specific and win over shallower ones.
  final int depth;

  const HandlerInfo({
    required this.exceptionType,
    required this.methodName,
    required this.takesRequest,
    required this.depth,
  });

  Map<String, Object?> toJson() => {
        'exception': exceptionType.toJson(),
        'method': methodName,
        if (takesRequest) 'takesRequest': true,
        'depth': depth,
      };

  factory HandlerInfo.fromJson(Map<String, Object?> json) => HandlerInfo(
        exceptionType:
            TypeRef.fromJson((json['exception'] as Map).cast<String, Object?>()),
        methodName: json['method'] as String,
        takesRequest: json['takesRequest'] as bool? ?? false,
        depth: json['depth'] as int,
      );
}

/// A `@ControllerAdvice` class.
class AdviceInfo {
  final TypeRef type;
  final List<HandlerInfo> handlers;

  const AdviceInfo({required this.type, this.handlers = const []});

  Map<String, Object?> toJson() => {
        'type': type.toJson(),
        'handlers': [for (final h in handlers) h.toJson()],
      };

  factory AdviceInfo.fromJson(Map<String, Object?> json) => AdviceInfo(
        type: TypeRef.fromJson((json['type'] as Map).cast<String, Object?>()),
        handlers: [
          for (final h in (json['handlers'] as List<Object?>? ?? const []))
            HandlerInfo.fromJson((h as Map).cast<String, Object?>()),
        ],
      );
}

/// The `@DianaApplication` entrypoint.
class AppInfo {
  final String className;
  final String configFile;

  const AppInfo({required this.className, required this.configFile});

  Map<String, Object?> toJson() =>
      {'className': className, 'configFile': configFile};

  factory AppInfo.fromJson(Map<String, Object?> json) => AppInfo(
        className: json['className'] as String,
        configFile: json['configFile'] as String,
      );
}

/// Everything Diana knows about one library.
class LibrarySummary {
  final String libraryUri;
  final List<InjectableInfo> injectables;
  final List<ControllerInfo> controllers;
  final List<GlobalMiddlewareInfo> globalMiddleware;
  final List<AdviceInfo> advices;
  final AppInfo? app;

  const LibrarySummary({
    required this.libraryUri,
    this.injectables = const [],
    this.controllers = const [],
    this.globalMiddleware = const [],
    this.advices = const [],
    this.app,
  });

  bool get isEmpty =>
      injectables.isEmpty &&
      controllers.isEmpty &&
      globalMiddleware.isEmpty &&
      advices.isEmpty &&
      app == null;

  Map<String, Object?> toJson() => {
        'library': libraryUri,
        if (injectables.isNotEmpty)
          'injectables': [for (final i in injectables) i.toJson()],
        if (controllers.isNotEmpty)
          'controllers': [for (final c in controllers) c.toJson()],
        if (globalMiddleware.isNotEmpty)
          'globalMiddleware': [for (final m in globalMiddleware) m.toJson()],
        if (advices.isNotEmpty)
          'advices': [for (final a in advices) a.toJson()],
        if (app != null) 'app': app!.toJson(),
      };

  factory LibrarySummary.fromJson(Map<String, Object?> json) => LibrarySummary(
        libraryUri: json['library'] as String,
        injectables: [
          for (final i in (json['injectables'] as List<Object?>? ?? const []))
            InjectableInfo.fromJson((i as Map).cast<String, Object?>()),
        ],
        controllers: [
          for (final c in (json['controllers'] as List<Object?>? ?? const []))
            ControllerInfo.fromJson((c as Map).cast<String, Object?>()),
        ],
        globalMiddleware: [
          for (final m
              in (json['globalMiddleware'] as List<Object?>? ?? const []))
            GlobalMiddlewareInfo.fromJson((m as Map).cast<String, Object?>()),
        ],
        advices: [
          for (final a in (json['advices'] as List<Object?>? ?? const []))
            AdviceInfo.fromJson((a as Map).cast<String, Object?>()),
        ],
        app: json['app'] == null
            ? null
            : AppInfo.fromJson((json['app'] as Map).cast<String, Object?>()),
      );
}
