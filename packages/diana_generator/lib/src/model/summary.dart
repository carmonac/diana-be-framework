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

  /// `@PostConstruct` method name, if any.
  final String? postConstruct;
  final bool postConstructAwaited;

  /// `@PreDestroy` method name, if any.
  final String? preDestroy;
  final bool preDestroyAwaited;

  /// `@Scheduled` methods of this provider.
  final List<ScheduledMethodInfo> scheduled;

  /// `@EventListener` methods of this provider.
  final List<EventListenerInfo> eventListeners;

  /// Aspect-annotated methods of this provider (`@Transactional`, `@Timed`,
  /// `@Cacheable`, `@Retryable`, `@CircuitBreaker`) — proxied by the
  /// generator.
  final List<AspectMethodInfo> aspectMethods;

  /// Present when this provider is an abstract query repository
  /// (`extends DianaRepository<E>`); the generator implements it.
  final QueryRepoInfo? queryRepo;

  /// `@MessageMapping` methods of this provider (STOMP).
  final List<MessageMappingInfo> messageMappings;

  const InjectableInfo({
    required this.type,
    required this.scope,
    this.qualifier,
    this.explicitAs,
    this.supertypes = const [],
    this.ctorParams = const [],
    this.kind = ProviderKind.normal,
    this.configPrefix,
    this.postConstruct,
    this.postConstructAwaited = false,
    this.preDestroy,
    this.preDestroyAwaited = false,
    this.scheduled = const [],
    this.eventListeners = const [],
    this.aspectMethods = const [],
    this.queryRepo,
    this.messageMappings = const [],
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
        if (postConstruct != null) 'postConstruct': postConstruct,
        if (postConstructAwaited) 'postConstructAwaited': true,
        if (preDestroy != null) 'preDestroy': preDestroy,
        if (preDestroyAwaited) 'preDestroyAwaited': true,
        if (scheduled.isNotEmpty)
          'scheduled': [for (final t in scheduled) t.toJson()],
        if (eventListeners.isNotEmpty)
          'eventListeners': [for (final l in eventListeners) l.toJson()],
        if (aspectMethods.isNotEmpty)
          'aspectMethods': [for (final t in aspectMethods) t.toJson()],
        if (queryRepo != null) 'queryRepo': queryRepo!.toJson(),
        if (messageMappings.isNotEmpty)
          'messageMappings': [for (final m in messageMappings) m.toJson()],
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
        postConstruct: json['postConstruct'] as String?,
        postConstructAwaited: json['postConstructAwaited'] as bool? ?? false,
        preDestroy: json['preDestroy'] as String?,
        preDestroyAwaited: json['preDestroyAwaited'] as bool? ?? false,
        scheduled: [
          for (final t in (json['scheduled'] as List<Object?>? ?? const []))
            ScheduledMethodInfo.fromJson((t as Map).cast<String, Object?>()),
        ],
        eventListeners: [
          for (final l
              in (json['eventListeners'] as List<Object?>? ?? const []))
            EventListenerInfo.fromJson((l as Map).cast<String, Object?>()),
        ],
        aspectMethods: [
          for (final t
              in (json['aspectMethods'] as List<Object?>? ?? const []))
            AspectMethodInfo.fromJson((t as Map).cast<String, Object?>()),
        ],
        queryRepo: json['queryRepo'] == null
            ? null
            : QueryRepoInfo.fromJson(
                (json['queryRepo'] as Map).cast<String, Object?>()),
        messageMappings: [
          for (final m
              in (json['messageMappings'] as List<Object?>? ?? const []))
            MessageMappingInfo.fromJson((m as Map).cast<String, Object?>()),
        ],
      );

  /// Whether the generator must implement this provider as a query
  /// repository (`\$Repo\$X`).
  bool get isQueryRepo => queryRepo != null;

  /// Whether any aspect method is transactional (gates diana_data wiring).
  bool get hasTx => aspectMethods.any((m) => m.transactional);

  /// Whether any method carries `@Timed` (gates the proxy observer param).
  bool get hasTimed => aspectMethods.any((m) => m.timed != null);

  /// Whether any method carries `@Cacheable` (gates the proxy store param
  /// when a `DianaCacheStore` provider exists).
  bool get hasCacheable => aspectMethods.any((m) => m.cacheable != null);

  /// Whether any method carries a non-transactional aspect (selects the
  /// `$Aspect$` proxy shape over the legacy `$Tx$` one).
  bool get hasNewAspects => aspectMethods.any((m) =>
      m.timed != null ||
      m.cacheable != null ||
      m.retryable != null ||
      m.circuitBreaker != null);
}

/// One aspect-annotated method of a provider, with enough of its signature
/// captured to re-declare a faithful override in the generated proxy.
class AspectMethodInfo {
  final String methodName;
  final TypeRef returnType;

  /// Declared type parameters (generic methods), re-declared on overrides.
  final List<TypeParamInfo> typeParams;
  final List<AspectParamInfo> params;

  /// Wrapped in a transaction (`@Transactional`, the innermost layer).
  final bool transactional;

  final TimedInfo? timed;
  final CacheableInfo? cacheable;
  final RetryableInfo? retryable;
  final CircuitBreakerInfo? circuitBreaker;

  const AspectMethodInfo({
    required this.methodName,
    required this.returnType,
    this.typeParams = const [],
    this.params = const [],
    this.transactional = false,
    this.timed,
    this.cacheable,
    this.retryable,
    this.circuitBreaker,
  });

  Map<String, Object?> toJson() => {
        'method': methodName,
        'returnType': returnType.toJson(),
        if (typeParams.isNotEmpty)
          'typeParams': [for (final t in typeParams) t.toJson()],
        if (params.isNotEmpty)
          'params': [for (final p in params) p.toJson()],
        if (transactional) 'tx': true,
        if (timed != null) 'timed': timed!.toJson(),
        if (cacheable != null) 'cacheable': cacheable!.toJson(),
        if (retryable != null) 'retryable': retryable!.toJson(),
        if (circuitBreaker != null)
          'circuitBreaker': circuitBreaker!.toJson(),
      };

  factory AspectMethodInfo.fromJson(Map<String, Object?> json) =>
      AspectMethodInfo(
        methodName: json['method'] as String,
        returnType: TypeRef.fromJson(
            (json['returnType'] as Map).cast<String, Object?>()),
        typeParams: [
          for (final t in (json['typeParams'] as List<Object?>? ?? const []))
            TypeParamInfo.fromJson((t as Map).cast<String, Object?>()),
        ],
        params: [
          for (final p in (json['params'] as List<Object?>? ?? const []))
            AspectParamInfo.fromJson((p as Map).cast<String, Object?>()),
        ],
        transactional: json['tx'] as bool? ?? false,
        timed: json['timed'] == null
            ? null
            : TimedInfo.fromJson((json['timed'] as Map).cast()),
        cacheable: json['cacheable'] == null
            ? null
            : CacheableInfo.fromJson((json['cacheable'] as Map).cast()),
        retryable: json['retryable'] == null
            ? null
            : RetryableInfo.fromJson((json['retryable'] as Map).cast()),
        circuitBreaker: json['circuitBreaker'] == null
            ? null
            : CircuitBreakerInfo.fromJson(
                (json['circuitBreaker'] as Map).cast()),
      );
}

/// One declared type parameter of a generic aspect method.
class TypeParamInfo {
  final String name;

  /// The `extends` bound, or null for an unbounded parameter.
  final TypeRef? bound;

  const TypeParamInfo({required this.name, this.bound});

  Map<String, Object?> toJson() => {
        'name': name,
        if (bound != null) 'bound': bound!.toJson(),
      };

  factory TypeParamInfo.fromJson(Map<String, Object?> json) => TypeParamInfo(
        name: json['name'] as String,
        bound: json['bound'] == null
            ? null
            : TypeRef.fromJson((json['bound'] as Map).cast<String, Object?>()),
      );
}

/// `@Timed` spec (omit-if-default JSON).
class TimedInfo {
  /// Metric label override; null = `ClassName.methodName`.
  final String? name;

  const TimedInfo({this.name});

  Map<String, Object?> toJson() => {if (name != null) 'name': name};

  factory TimedInfo.fromJson(Map<String, Object?> json) =>
      TimedInfo(name: json['name'] as String?);
}

/// `@Cacheable` spec (omit-if-default JSON).
class CacheableInfo {
  final int ttlSeconds;
  final int maxEntries;

  const CacheableInfo({this.ttlSeconds = 60, this.maxEntries = 1024});

  Map<String, Object?> toJson() => {
        if (ttlSeconds != 60) 'ttl': ttlSeconds,
        if (maxEntries != 1024) 'max': maxEntries,
      };

  factory CacheableInfo.fromJson(Map<String, Object?> json) => CacheableInfo(
        ttlSeconds: json['ttl'] as int? ?? 60,
        maxEntries: json['max'] as int? ?? 1024,
      );
}

/// `@Retryable` spec (omit-if-default JSON). [retryOn] carries the
/// exception types as [TypeRef]s; the emitter turns them into an
/// `e is X || ...` predicate.
class RetryableInfo {
  final int maxAttempts;
  final int backoffMs;
  final List<TypeRef> retryOn;

  const RetryableInfo({
    this.maxAttempts = 3,
    this.backoffMs = 200,
    this.retryOn = const [],
  });

  Map<String, Object?> toJson() => {
        if (maxAttempts != 3) 'attempts': maxAttempts,
        if (backoffMs != 200) 'backoff': backoffMs,
        if (retryOn.isNotEmpty)
          'retryOn': [for (final t in retryOn) t.toJson()],
      };

  factory RetryableInfo.fromJson(Map<String, Object?> json) => RetryableInfo(
        maxAttempts: json['attempts'] as int? ?? 3,
        backoffMs: json['backoff'] as int? ?? 200,
        retryOn: [
          for (final t in (json['retryOn'] as List<Object?>? ?? const []))
            TypeRef.fromJson((t as Map).cast<String, Object?>()),
        ],
      );
}

/// `@CircuitBreaker` spec (omit-if-default JSON).
class CircuitBreakerInfo {
  final int failureThreshold;
  final int resetTimeoutMs;

  const CircuitBreakerInfo({
    this.failureThreshold = 5,
    this.resetTimeoutMs = 30000,
  });

  Map<String, Object?> toJson() => {
        if (failureThreshold != 5) 'threshold': failureThreshold,
        if (resetTimeoutMs != 30000) 'reset': resetTimeoutMs,
      };

  factory CircuitBreakerInfo.fromJson(Map<String, Object?> json) =>
      CircuitBreakerInfo(
        failureThreshold: json['threshold'] as int? ?? 5,
        resetTimeoutMs: json['reset'] as int? ?? 30000,
      );
}

/// One parameter of an aspect-proxied method.
class AspectParamInfo {
  final String name;
  final TypeRef type;

  /// `requiredPositional`, `optionalPositional` or `named`.
  final String kind;
  final bool required;

  /// Verbatim default-value source (e.g. `const []`), or null.
  final String? defaultCode;

  const AspectParamInfo({
    required this.name,
    required this.type,
    required this.kind,
    this.required = false,
    this.defaultCode,
  });

  Map<String, Object?> toJson() => {
        'name': name,
        'type': type.toJson(),
        'kind': kind,
        if (required) 'required': true,
        if (defaultCode != null) 'default': defaultCode,
      };

  factory AspectParamInfo.fromJson(Map<String, Object?> json) =>
      AspectParamInfo(
        name: json['name'] as String,
        type: TypeRef.fromJson((json['type'] as Map).cast<String, Object?>()),
        kind: json['kind'] as String,
        required: json['required'] as bool? ?? false,
        defaultCode: json['default'] as String?,
      );
}

/// An abstract query repository: everything the generator needs to emit
/// its implementation, snapshotted from the entity at read time (the
/// entity may live in another library).
class QueryRepoInfo {
  /// The entity type; its `libraryUri` also locates the generated
  /// `\$EFromJson`/`\$EToJson` codecs (part-file members of that library).
  final TypeRef entity;

  /// Table name from `@Table`.
  final String table;

  /// Column of the entity's `id` field (used by findById/deleteById).
  final String idColumn;

  final List<QueryMethodInfo> methods;

  const QueryRepoInfo({
    required this.entity,
    required this.table,
    required this.idColumn,
    this.methods = const [],
  });

  Map<String, Object?> toJson() => {
        'entity': entity.toJson(),
        'table': table,
        'idColumn': idColumn,
        if (methods.isNotEmpty)
          'methods': [for (final m in methods) m.toJson()],
      };

  factory QueryRepoInfo.fromJson(Map<String, Object?> json) => QueryRepoInfo(
        entity:
            TypeRef.fromJson((json['entity'] as Map).cast<String, Object?>()),
        table: json['table'] as String,
        idColumn: json['idColumn'] as String,
        methods: [
          for (final m in (json['methods'] as List<Object?>? ?? const []))
            QueryMethodInfo.fromJson((m as Map).cast<String, Object?>()),
        ],
      );
}

/// One parsed query method. Conditions consume [params] positionally
/// (isNull/isNotNull take 0, between takes 2, everything else 1).
class QueryMethodInfo {
  /// The declared method name (diagnostics/emission).
  final String name;

  /// `find`, `findFirst`, `count`, `exists` or `delete`.
  final String subject;

  /// `and` (default) or `or` — a method uses exactly one connector.
  final String connector;

  final List<QueryConditionInfo> conditions;
  final List<QueryOrderInfo> orderBy;
  final List<QueryParamInfo> params;

  const QueryMethodInfo({
    required this.name,
    required this.subject,
    this.connector = 'and',
    this.conditions = const [],
    this.orderBy = const [],
    this.params = const [],
  });

  Map<String, Object?> toJson() => {
        'name': name,
        'subject': subject,
        if (connector != 'and') 'connector': connector,
        if (conditions.isNotEmpty)
          'conditions': [for (final c in conditions) c.toJson()],
        if (orderBy.isNotEmpty)
          'orderBy': [for (final o in orderBy) o.toJson()],
        if (params.isNotEmpty)
          'params': [for (final p in params) p.toJson()],
      };

  factory QueryMethodInfo.fromJson(Map<String, Object?> json) =>
      QueryMethodInfo(
        name: json['name'] as String,
        subject: json['subject'] as String,
        connector: json['connector'] as String? ?? 'and',
        conditions: [
          for (final c in (json['conditions'] as List<Object?>? ?? const []))
            QueryConditionInfo.fromJson((c as Map).cast<String, Object?>()),
        ],
        orderBy: [
          for (final o in (json['orderBy'] as List<Object?>? ?? const []))
            QueryOrderInfo.fromJson((o as Map).cast<String, Object?>()),
        ],
        params: [
          for (final p in (json['params'] as List<Object?>? ?? const []))
            QueryParamInfo.fromJson((p as Map).cast<String, Object?>()),
        ],
      );
}

/// One condition: a resolved column and an operator.
class QueryConditionInfo {
  final String column;

  /// `eq` (default) | `not` | `gt` | `gte` | `lt` | `lte` | `like` |
  /// `contains` | `startsWith` | `endsWith` | `inList` | `notIn` |
  /// `between` | `isNull` | `isNotNull`.
  final String op;

  const QueryConditionInfo({required this.column, this.op = 'eq'});

  Map<String, Object?> toJson() => {
        'column': column,
        if (op != 'eq') 'op': op,
      };

  factory QueryConditionInfo.fromJson(Map<String, Object?> json) =>
      QueryConditionInfo(
        column: json['column'] as String,
        op: json['op'] as String? ?? 'eq',
      );
}

/// One OrderBy clause entry.
class QueryOrderInfo {
  final String column;
  final bool desc;

  const QueryOrderInfo({required this.column, this.desc = false});

  Map<String, Object?> toJson() => {
        'column': column,
        if (desc) 'desc': true,
      };

  factory QueryOrderInfo.fromJson(Map<String, Object?> json) =>
      QueryOrderInfo(
        column: json['column'] as String,
        desc: json['desc'] as bool? ?? false,
      );
}

/// One required positional parameter of a query method.
class QueryParamInfo {
  final String name;
  final TypeRef type;

  const QueryParamInfo({required this.name, required this.type});

  Map<String, Object?> toJson() =>
      {'name': name, 'type': type.toJson()};

  factory QueryParamInfo.fromJson(Map<String, Object?> json) => QueryParamInfo(
        name: json['name'] as String,
        type: TypeRef.fromJson((json['type'] as Map).cast<String, Object?>()),
      );
}

/// One `@MessageMapping` method: how the generator emits its broker
/// registration.
class MessageMappingInfo {
  final String methodName;

  /// Destination without the app prefix (e.g. `/chat`).
  final String destination;

  /// `text` (raw String payload) or `json` (@Json DTO).
  final String payloadKind;

  /// The DTO type when [payloadKind] is `json`.
  final TypeRef? payloadType;

  /// Whether a second `StompMessage` parameter is declared.
  final bool wantsMessage;

  /// `void` (default), `text` or `json`.
  final String returnKind;

  /// The DTO type when [returnKind] is `json`.
  final TypeRef? returnType;

  /// `@SendTo` destination, when the method returns a value.
  final String? sendTo;

  const MessageMappingInfo({
    required this.methodName,
    required this.destination,
    required this.payloadKind,
    this.payloadType,
    this.wantsMessage = false,
    this.returnKind = 'void',
    this.returnType,
    this.sendTo,
  });

  Map<String, Object?> toJson() => {
        'method': methodName,
        'destination': destination,
        'payloadKind': payloadKind,
        if (payloadType != null) 'payloadType': payloadType!.toJson(),
        if (wantsMessage) 'wantsMessage': true,
        if (returnKind != 'void') 'returnKind': returnKind,
        if (returnType != null) 'returnType': returnType!.toJson(),
        if (sendTo != null) 'sendTo': sendTo,
      };

  factory MessageMappingInfo.fromJson(Map<String, Object?> json) =>
      MessageMappingInfo(
        methodName: json['method'] as String,
        destination: json['destination'] as String,
        payloadKind: json['payloadKind'] as String,
        payloadType: json['payloadType'] == null
            ? null
            : TypeRef.fromJson(
                (json['payloadType'] as Map).cast<String, Object?>()),
        wantsMessage: json['wantsMessage'] as bool? ?? false,
        returnKind: json['returnKind'] as String? ?? 'void',
        returnType: json['returnType'] == null
            ? null
            : TypeRef.fromJson(
                (json['returnType'] as Map).cast<String, Object?>()),
        sendTo: json['sendTo'] as String?,
      );
}

/// One `@EventListener` method of a provider.
class EventListenerInfo {
  final String methodName;

  /// The listener's single parameter type — the event it subscribes to.
  final TypeRef eventType;

  const EventListenerInfo({required this.methodName, required this.eventType});

  Map<String, Object?> toJson() => {
        'method': methodName,
        'eventType': eventType.toJson(),
      };

  factory EventListenerInfo.fromJson(Map<String, Object?> json) =>
      EventListenerInfo(
        methodName: json['method'] as String,
        eventType: TypeRef.fromJson(
            (json['eventType'] as Map).cast<String, Object?>()),
      );
}

/// One `@Scheduled` method of a provider.
class ScheduledMethodInfo {
  final String methodName;
  final int? fixedRateMs;
  final int? fixedDelayMs;

  /// A 6-field cron expression (macros pre-expanded by the reader), or null.
  final String? cron;
  final int initialDelayMs;
  final bool perIsolate;

  const ScheduledMethodInfo({
    required this.methodName,
    this.fixedRateMs,
    this.fixedDelayMs,
    this.cron,
    this.initialDelayMs = 0,
    this.perIsolate = false,
  });

  Map<String, Object?> toJson() => {
        'method': methodName,
        if (fixedRateMs != null) 'fixedRate': fixedRateMs,
        if (fixedDelayMs != null) 'fixedDelay': fixedDelayMs,
        if (cron != null) 'cron': cron,
        if (initialDelayMs != 0) 'initialDelay': initialDelayMs,
        if (perIsolate) 'perIsolate': true,
      };

  factory ScheduledMethodInfo.fromJson(Map<String, Object?> json) =>
      ScheduledMethodInfo(
        methodName: json['method'] as String,
        fixedRateMs: json['fixedRate'] as int?,
        fixedDelayMs: json['fixedDelay'] as int?,
        cron: json['cron'] as String?,
        initialDelayMs: json['initialDelay'] as int? ?? 0,
        perIsolate: json['perIsolate'] as bool? ?? false,
      );
}

/// A `@CrossOrigin` policy on a controller or route.
class CorsInfo {
  final List<String> origins;
  final List<String>? methods;
  final List<String> headers;
  final List<String> exposedHeaders;
  final bool credentials;
  final int maxAge;

  const CorsInfo({
    this.origins = const ['*'],
    this.methods,
    this.headers = const ['*'],
    this.exposedHeaders = const [],
    this.credentials = false,
    this.maxAge = 3600,
  });

  Map<String, Object?> toJson() => {
        'origins': origins,
        if (methods != null) 'methods': methods,
        'headers': headers,
        if (exposedHeaders.isNotEmpty) 'exposedHeaders': exposedHeaders,
        if (credentials) 'credentials': true,
        'maxAge': maxAge,
      };

  factory CorsInfo.fromJson(Map<String, Object?> json) => CorsInfo(
        origins: (json['origins'] as List).cast<String>(),
        methods: (json['methods'] as List?)?.cast<String>(),
        headers: (json['headers'] as List).cast<String>(),
        exposedHeaders:
            (json['exposedHeaders'] as List?)?.cast<String>() ?? const [],
        credentials: json['credentials'] as bool? ?? false,
        maxAge: json['maxAge'] as int,
      );
}


/// A `@Secured`/`@RolesAllowed` declaration on a controller, route,
/// WebSocket controller or gRPC service.
class SecurityInfo {
  /// Roles required by `@RolesAllowed` (any-of). Null means `@Secured`
  /// alone (authentication required, no specific role).
  final List<String>? roles;

  const SecurityInfo({this.roles});

  Map<String, Object?> toJson() => {
        if (roles != null) 'roles': roles,
      };

  factory SecurityInfo.fromJson(Map<String, Object?> json) => SecurityInfo(
        roles: (json['roles'] as List?)?.cast<String>(),
      );
}

/// One bindable parameter of a route, for OpenAPI generation.
class RouteParamApi {
  /// `path`, `query` or `header`.
  final String kind;
  final String name;
  final TypeRef type;
  final bool required;
  final String? defaultValue;

  const RouteParamApi({
    required this.kind,
    required this.name,
    required this.type,
    required this.required,
    this.defaultValue,
  });

  Map<String, Object?> toJson() => {
        'kind': kind,
        'name': name,
        'type': type.toJson(),
        if (required) 'required': true,
        if (defaultValue != null) 'default': defaultValue,
      };

  factory RouteParamApi.fromJson(Map<String, Object?> json) => RouteParamApi(
        kind: json['kind'] as String,
        name: json['name'] as String,
        type: TypeRef.fromJson((json['type'] as Map).cast<String, Object?>()),
        required: json['required'] as bool? ?? false,
        defaultValue: json['default'] as String?,
      );
}

/// API surface of one route (parameters, body, response) for OpenAPI.
class RouteApi {
  final List<RouteParamApi> params;

  /// `dto`, `dtoList`, `map`, `list`, `text` or `form`; null = no body.
  final String? bodyShape;
  final TypeRef? bodyType;

  /// `dto`, `dtoList`, `raw`, `text`, `void` or `response`.
  final String returnShape;
  final TypeRef? returnType;
  final int? status;

  /// From `@Consumes`; null = JSON default.
  final List<String>? consumes;

  /// From `@Produces`; null = JSON default.
  final List<String>? produces;

  const RouteApi({
    this.params = const [],
    this.bodyShape,
    this.bodyType,
    required this.returnShape,
    this.returnType,
    this.status,
    this.consumes,
    this.produces,
  });

  Map<String, Object?> toJson() => {
        if (params.isNotEmpty) 'params': [for (final p in params) p.toJson()],
        if (bodyShape != null) 'bodyShape': bodyShape,
        if (bodyType != null) 'bodyType': bodyType!.toJson(),
        'returnShape': returnShape,
        if (returnType != null) 'returnType': returnType!.toJson(),
        if (status != null) 'status': status,
        if (consumes != null) 'consumes': consumes,
        if (produces != null) 'produces': produces,
      };

  factory RouteApi.fromJson(Map<String, Object?> json) => RouteApi(
        params: [
          for (final p in (json['params'] as List<Object?>? ?? const []))
            RouteParamApi.fromJson((p as Map).cast<String, Object?>()),
        ],
        bodyShape: json['bodyShape'] as String?,
        bodyType: json['bodyType'] == null
            ? null
            : TypeRef.fromJson(
                (json['bodyType'] as Map).cast<String, Object?>()),
        returnShape: json['returnShape'] as String,
        returnType: json['returnType'] == null
            ? null
            : TypeRef.fromJson(
                (json['returnType'] as Map).cast<String, Object?>()),
        status: json['status'] as int?,
        consumes: (json['consumes'] as List?)?.cast<String>(),
        produces: (json['produces'] as List?)?.cast<String>(),
      );
}

/// A DTO field, with JSON name and validation constraints, for OpenAPI
/// schema generation.
class DtoFieldInfo {
  final String name;
  final String jsonName;
  final TypeRef type;
  final bool nullable;

  /// Enum constant names when the field type is an enum.
  final List<String>? enumValues;

  /// Validation constraints (keys: minLength, maxLength, min, max, pattern,
  /// email, notBlank, notEmpty).
  final Map<String, Object?> constraints;

  const DtoFieldInfo({
    required this.name,
    required this.jsonName,
    required this.type,
    required this.nullable,
    this.enumValues,
    this.constraints = const {},
  });

  Map<String, Object?> toJson() => {
        'name': name,
        if (jsonName != name) 'jsonName': jsonName,
        'type': type.toJson(),
        if (nullable) 'nullable': true,
        if (enumValues != null) 'enumValues': enumValues,
        if (constraints.isNotEmpty) 'constraints': constraints,
      };

  factory DtoFieldInfo.fromJson(Map<String, Object?> json) => DtoFieldInfo(
        name: json['name'] as String,
        jsonName: json['jsonName'] as String? ?? json['name'] as String,
        type: TypeRef.fromJson((json['type'] as Map).cast<String, Object?>()),
        nullable: json['nullable'] as bool? ?? false,
        enumValues: (json['enumValues'] as List?)?.cast<String>(),
        constraints:
            (json['constraints'] as Map?)?.cast<String, Object?>() ?? const {},
      );
}

/// A DTO exposed in the API (a `@Json` class or a validated class).
class DtoInfo {
  final TypeRef type;
  final List<DtoFieldInfo> fields;

  const DtoInfo({required this.type, this.fields = const []});

  Map<String, Object?> toJson() => {
        'type': type.toJson(),
        'fields': [for (final f in fields) f.toJson()],
      };

  factory DtoInfo.fromJson(Map<String, Object?> json) => DtoInfo(
        type: TypeRef.fromJson((json['type'] as Map).cast<String, Object?>()),
        fields: [
          for (final f in (json['fields'] as List<Object?>? ?? const []))
            DtoFieldInfo.fromJson((f as Map).cast<String, Object?>()),
        ],
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
  final CorsInfo? cors;
  final SecurityInfo? security;

  /// API surface for OpenAPI generation.
  final RouteApi? api;

  const RouteInfo({
    required this.httpMethod,
    required this.path,
    required this.methodName,
    required this.adapterName,
    this.middleware = const [],
    this.cors,
    this.security,
    this.api,
  });

  Map<String, Object?> toJson() => {
        'method': httpMethod,
        'path': path,
        'dartMethod': methodName,
        'adapter': adapterName,
        if (middleware.isNotEmpty)
          'middleware': [for (final t in middleware) t.toJson()],
        if (cors != null) 'cors': cors!.toJson(),
        if (security != null) 'security': security!.toJson(),
        if (api != null) 'api': api!.toJson(),
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
        cors: json['cors'] == null
            ? null
            : CorsInfo.fromJson((json['cors'] as Map).cast<String, Object?>()),
        security: json['security'] == null
            ? null
            : SecurityInfo.fromJson(
                (json['security'] as Map).cast<String, Object?>()),
        api: json['api'] == null
            ? null
            : RouteApi.fromJson((json['api'] as Map).cast<String, Object?>()),
      );
}

/// A `@RestController` class.
class ControllerInfo {
  final TypeRef type;
  final String basePath;
  final List<TypeRef> middleware;
  final List<RouteInfo> routes;
  final CorsInfo? cors;
  final SecurityInfo? security;

  const ControllerInfo({
    required this.type,
    required this.basePath,
    this.middleware = const [],
    this.routes = const [],
    this.cors,
    this.security,
  });

  Map<String, Object?> toJson() => {
        'type': type.toJson(),
        'basePath': basePath,
        if (middleware.isNotEmpty)
          'middleware': [for (final t in middleware) t.toJson()],
        'routes': [for (final r in routes) r.toJson()],
        if (cors != null) 'cors': cors!.toJson(),
        if (security != null) 'security': security!.toJson(),
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
        cors: json['cors'] == null
            ? null
            : CorsInfo.fromJson((json['cors'] as Map).cast<String, Object?>()),
        security: json['security'] == null
            ? null
            : SecurityInfo.fromJson(
                (json['security'] as Map).cast<String, Object?>()),
      );
}

/// A `@GrpcService` class.
class GrpcServiceInfo {
  final TypeRef type;
  final SecurityInfo? security;

  const GrpcServiceInfo({required this.type, this.security});

  Map<String, Object?> toJson() => {
        'type': type.toJson(),
        if (security != null) 'security': security!.toJson(),
      };

  factory GrpcServiceInfo.fromJson(Map<String, Object?> json) =>
      GrpcServiceInfo(
        type: TypeRef.fromJson((json['type'] as Map).cast<String, Object?>()),
        security: json['security'] == null
            ? null
            : SecurityInfo.fromJson(
                (json['security'] as Map).cast<String, Object?>()),
      );
}

/// A `@WebSocketController` class.
class WebSocketInfo {
  final TypeRef type;
  final String path;

  /// Handshake interceptors from `@UseMiddleware` on the class.
  final List<TypeRef> middleware;
  final SecurityInfo? security;

  const WebSocketInfo({
    required this.type,
    required this.path,
    this.middleware = const [],
    this.security,
  });

  Map<String, Object?> toJson() => {
        'type': type.toJson(),
        'path': path,
        if (middleware.isNotEmpty)
          'middleware': [for (final t in middleware) t.toJson()],
        if (security != null) 'security': security!.toJson(),
      };

  factory WebSocketInfo.fromJson(Map<String, Object?> json) => WebSocketInfo(
        type: TypeRef.fromJson((json['type'] as Map).cast<String, Object?>()),
        path: json['path'] as String,
        middleware: [
          for (final t in (json['middleware'] as List<Object?>? ?? const []))
            TypeRef.fromJson((t as Map).cast<String, Object?>()),
        ],
        security: json['security'] == null
            ? null
            : SecurityInfo.fromJson(
                (json['security'] as Map).cast<String, Object?>()),
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
  final List<DtoInfo> dtos;
  final List<WebSocketInfo> webSockets;
  final List<GrpcServiceInfo> grpcServices;
  final List<GlobalMiddlewareInfo> globalMiddleware;
  final List<AdviceInfo> advices;
  final AppInfo? app;

  const LibrarySummary({
    required this.libraryUri,
    this.injectables = const [],
    this.controllers = const [],
    this.dtos = const [],
    this.webSockets = const [],
    this.grpcServices = const [],
    this.globalMiddleware = const [],
    this.advices = const [],
    this.app,
  });

  bool get isEmpty =>
      injectables.isEmpty &&
      controllers.isEmpty &&
      dtos.isEmpty &&
      webSockets.isEmpty &&
      grpcServices.isEmpty &&
      globalMiddleware.isEmpty &&
      advices.isEmpty &&
      app == null;

  Map<String, Object?> toJson() => {
        'library': libraryUri,
        if (injectables.isNotEmpty)
          'injectables': [for (final i in injectables) i.toJson()],
        if (controllers.isNotEmpty)
          'controllers': [for (final c in controllers) c.toJson()],
        if (dtos.isNotEmpty) 'dtos': [for (final d in dtos) d.toJson()],
        if (webSockets.isNotEmpty)
          'webSockets': [for (final w in webSockets) w.toJson()],
        if (grpcServices.isNotEmpty)
          'grpcServices': [for (final g in grpcServices) g.toJson()],
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
        dtos: [
          for (final d in (json['dtos'] as List<Object?>? ?? const []))
            DtoInfo.fromJson((d as Map).cast<String, Object?>()),
        ],
        webSockets: [
          for (final w in (json['webSockets'] as List<Object?>? ?? const []))
            WebSocketInfo.fromJson((w as Map).cast<String, Object?>()),
        ],
        grpcServices: [
          for (final g
              in (json['grpcServices'] as List<Object?>? ?? const []))
            GrpcServiceInfo.fromJson((g as Map).cast<String, Object?>()),
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
