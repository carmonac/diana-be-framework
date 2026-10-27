import 'dart:convert';

import 'package:build/build.dart';
import 'package:code_builder/code_builder.dart';
import 'package:dart_style/dart_style.dart';
import 'package:glob/glob.dart';
import 'package:source_gen/source_gen.dart' show spanForElement;

import 'common.dart';
import 'emit/context_emitter.dart';
import 'graph/di_graph.dart';
import 'model/summary.dart';
import 'openapi/openapi_builder.dart';
import 'readers/library_reader.dart';

/// diana_auth guard/interceptor types are referenced by import URL only —
/// the generator never depends on diana_auth (mirrors `dianaGrpcLib`).
const String _dianaAuthLib = 'package:diana_auth/diana_auth.dart';

/// diana_observability's metrics handler is referenced by import URL only.
const String dianaObservabilityLib =
    'package:diana_observability/diana_observability.dart';

/// Aggregating builder. Runs on the library annotated with
/// `@DianaApplication`, discovers every `.diana.json` summary in the package,
/// resolves the dependency injection graph and emits the composition root
/// (`DianaContext`, `buildDianaServer`, `runDiana`) as a standalone
/// `.diana_app.dart` library.
class DianaBootstrapBuilder implements Builder {
  const DianaBootstrapBuilder();

  @override
  Map<String, List<String>> get buildExtensions => const {
        '.dart': ['.diana_app.dart'],
      };

  @override
  Future<void> build(BuildStep buildStep) async {
    final inputId = buildStep.inputId;
    if (!inputId.path.startsWith('lib/')) return;

    final source = await buildStep.readAsString(inputId);
    if (!dianaApplicationPattern.hasMatch(source)) return;
    if (!await buildStep.resolver.isLibrary(inputId)) return;

    final library = await buildStep.resolver.libraryFor(inputId);
    LibrarySummary ownSummary;
    try {
      ownSummary = readLibrary(library);
    } on DianaSourceError catch (e) {
      log.severe(spanForElement(e.element).message(e.message));
      return;
    }
    final app = ownSummary.app;
    if (app == null) return;

    final summaryIds =
        await buildStep.findAssets(Glob('lib/**.diana.json')).toList()
          ..sort((a, b) => a.path.compareTo(b.path));
    final summaries = <LibrarySummary>[
      for (final id in summaryIds)
        LibrarySummary.fromJson(
          (jsonDecode(await buildStep.readAsString(id)) as Map)
              .cast<String, Object?>(),
        ),
    ];

    final appEntries = [
      for (final s in summaries)
        if (s.app != null) '${s.app!.className} (${s.libraryUri})',
    ];
    if (appEntries.length > 1) {
      log.severe(
        'Multiple @DianaApplication classes found: '
        '${appEntries.join(', ')}. A package must declare exactly one '
        'application entrypoint.',
      );
      return;
    }

    final result = resolveGraph(summaries);
    final errors = [...result.errors];
    if (result.graph != null) {
      errors.addAll(_checkMiddlewareRefs(result.graph!, summaries));
      errors.addAll(_checkWebSockets(result.graph!, summaries));
      errors.addAll(_checkHealthIndicators(result.graph!));
      errors.addAll(_checkBodyCodecs(result.graph!));
      errors.addAll(_checkGrpcServices(result.graph!, summaries));
      errors.addAll(_checkGrpcSecurity(result.graph!, summaries));
      errors.addAll(_checkDatabase(result.graph!));
      errors.addAll(_checkObservability(result.graph!));
      errors.addAll(_checkCacheStore(result.graph!));
      errors.addAll(_checkStomp(result.graph!, summaries));
    }
    if (errors.isNotEmpty) {
      log.severe(
        'Diana failed to resolve the dependency graph '
        '(${errors.length} error${errors.length == 1 ? '' : 's'}):\n'
        '${errors.map((e) => ' • $e').join('\n')}',
      );
      return;
    }

    final output = _emitLibrary(result.graph!, summaries, app);
    await buildStep.writeAsString(
      inputId.changeExtension('.diana_app.dart'),
      output,
    );
  }

  /// Every `@UseMiddleware`/`@GlobalMiddleware` type must be a provider in
  /// the graph and implement Diana's `Middleware` interface.
  List<String> _checkMiddlewareRefs(
    DiGraph graph,
    List<LibrarySummary> summaries,
  ) {
    final errors = <String>[];

    void check(TypeRef type, String where) {
      final provider = graph.byKey['${type.key}|'];
      if (provider == null) {
        errors.add(
          '${type.displayName}, referenced by $where, is not an injectable '
          'class. Annotate it with @Component (or another injectable '
          'annotation).',
        );
        return;
      }
      final implementsMiddleware = provider.info.supertypes.any(
        (s) =>
            s.name == 'Middleware' && s.libraryUri.startsWith('package:diana/'),
      );
      if (!implementsMiddleware) {
        errors.add(
          '${type.displayName}, referenced by $where, does not implement '
          "Diana's Middleware interface.",
        );
      } else if (provider.needsRequestScope) {
        errors.add(
          '${type.displayName}, referenced by $where, is request-scoped; '
          'middleware must be singletons.',
        );
      }
    }

    for (final summary in summaries) {
      for (final mw in summary.globalMiddleware) {
        check(mw.type, '@GlobalMiddleware');
      }
      for (final ws in summary.webSockets) {
        for (final mw in ws.middleware) {
          check(
              mw,
              '@UseMiddleware on @WebSocketController '
              '${ws.type.displayName}');
        }
      }
      for (final controller in summary.controllers) {
        for (final mw in controller.middleware) {
          check(mw, '@UseMiddleware on ${controller.type.displayName}');
        }
        for (final route in controller.routes) {
          for (final mw in route.middleware) {
            check(
              mw,
              '@UseMiddleware on '
              '${controller.type.displayName}.${route.methodName}',
            );
          }
        }
      }
    }
    return errors;
  }

  /// Every `@WebSocketController` must implement Diana's `WebSocketHandler`
  /// interface, and endpoint paths must be unique.
  List<String> _checkWebSockets(
    DiGraph graph,
    List<LibrarySummary> summaries,
  ) {
    final errors = <String>[];
    final byPath = <String, WebSocketInfo>{};
    for (final summary in summaries) {
      for (final ws in summary.webSockets) {
        final provider = graph.byKey['${ws.type.key}|'];
        final implementsHandler = provider != null &&
            provider.info.supertypes.any(
              (s) =>
                  s.name == 'WebSocketHandler' &&
                  s.libraryUri.startsWith('package:diana/'),
            );
        if (!implementsHandler) {
          errors.add(
            '@WebSocketController class ${ws.type.displayName} '
            "(${summary.libraryUri}) does not implement Diana's "
            'WebSocketHandler interface. Implement it, or extend '
            'BaseWebSocketHandler.',
          );
        }
        final existing = byPath[ws.path];
        if (existing != null) {
          errors.add(
            'Duplicate WebSocket path "${ws.path}": handled by both '
            '${existing.type.displayName} and ${ws.type.displayName}.',
          );
        } else {
          byPath[ws.path] = ws;
        }
      }
    }
    return errors;
  }

  /// `HealthIndicator` implementations must be singletons (the aggregated
  /// endpoint holds direct references).
  List<String> _checkHealthIndicators(DiGraph graph) {
    final errors = <String>[];
    for (final provider in graph.ordered) {
      final implementsIndicator = provider.info.supertypes.any(
        (s) =>
            s.name == 'HealthIndicator' &&
            s.libraryUri.startsWith('package:diana/'),
      );
      if (implementsIndicator &&
          (provider.scope != 'singleton' || provider.needsRequestScope)) {
        errors.add(
          '${provider.info.type.displayName} implements HealthIndicator but '
          'is ${provider.scope}-scoped; health indicators must be '
          'singletons.',
        );
      }
    }
    return errors;
  }

  /// `BodyCodec` implementations must be singletons (the registry holds
  /// direct references).
  List<String> _checkBodyCodecs(DiGraph graph) {
    final errors = <String>[];
    for (final provider in graph.ordered) {
      final implementsCodec = provider.info.supertypes.any(
        (s) =>
            s.name == 'BodyCodec' && s.libraryUri.startsWith('package:diana/'),
      );
      if (implementsCodec &&
          (provider.scope != 'singleton' || provider.needsRequestScope)) {
        errors.add(
          '${provider.info.type.displayName} implements BodyCodec but is '
          '${provider.scope}-scoped; body codecs must be singletons.',
        );
      }
    }
    return errors;
  }

  /// `@GrpcService` classes must extend package:grpc's `Service` (via a
  /// protoc-generated `XServiceBase`).
  /// True when [a] and [b] describe the same security requirement.
  bool _sameSecurity(SecurityInfo? a, SecurityInfo? b) {
    if (a == null || b == null) {
      return identical(a, b) || (a == null && b == null);
    }
    final ar = a.roles, br = b.roles;
    if (ar == null || br == null) return ar == null && br == null;
    return ar.toSet().containsAll(br) && br.toSet().containsAll(ar);
  }

  /// The single `AuthenticationMiddleware` provider (diana_auth) in the
  /// graph, or `null` when absent or ambiguous.
  List<ResolvedProvider> _authMiddlewareProviders(DiGraph graph) => [
        for (final provider in graph.ordered)
          if (provider.info.supertypes.any(
            (s) =>
                s.name == 'AuthenticationMiddleware' &&
                s.libraryUri.startsWith('package:diana_auth/'),
          ))
            provider,
      ];

  /// The `DatabaseConnector` providers in the graph (discovered by
  /// supertype).
  List<ResolvedProvider> _connectorProviders(DiGraph graph) => [
        for (final provider in graph.ordered)
          if (provider.info.supertypes.any(
            (s) =>
                s.name == 'DatabaseConnector' &&
                s.libraryUri.startsWith('package:diana_data/'),
          ))
            provider,
      ];

  /// The `DianaObservability` providers in the graph (discovered by
  /// supertype).
  List<ResolvedProvider> _observabilityProviders(DiGraph graph) => [
        for (final provider in graph.ordered)
          if (provider.info.supertypes.any(
            (s) =>
                s.name == 'DianaObservability' &&
                s.libraryUri.startsWith('package:diana_observability/'),
          ))
            provider,
      ];

  /// The `DianaCacheStore` providers in the graph (discovered by
  /// supertype; the contract lives in `package:diana` core).
  List<ResolvedProvider> _cacheStoreProviders(DiGraph graph) => [
        for (final provider in graph.ordered)
          if (provider.info.supertypes.any(
            (s) =>
                s.name == 'DianaCacheStore' &&
                s.libraryUri.startsWith('package:diana/'),
          ))
            provider,
      ];

  /// At most one `DianaCacheStore` provider, and it must be a singleton
  /// (every cached method routes through the same instance).
  List<String> _checkCacheStore(DiGraph graph) {
    final providers = _cacheStoreProviders(graph);
    if (providers.length > 1) {
      return [
        'Multiple DianaCacheStore providers: '
            '${providers.map((p) => '${p.info.type.displayName} '
                '(${p.declaredIn})').join(', ')}. Declare exactly one.',
      ];
    }
    if (providers.isNotEmpty) {
      final p = providers.single;
      if (p.scope != 'singleton' || p.needsRequestScope) {
        return [
          '${p.info.type.displayName} extends DianaCacheStore but is '
              '${p.scope}-scoped; cache stores must be singletons.',
        ];
      }
    }
    return const [];
  }

  /// STOMP validation: every `StompEndpoint` must be a singleton
  /// `@WebSocketController`, `@MessageMapping` destinations must be unique
  /// across the app, and mappings need at least one endpoint to reach them.
  List<String> _checkStomp(DiGraph graph, List<LibrarySummary> summaries) {
    final errors = <String>[];
    final wsTypeKeys = {
      for (final s in summaries)
        for (final ws in s.webSockets) ws.type.key,
    };
    final endpoints = [
      for (final p in graph.ordered)
        if (p.info.supertypes.any((s) =>
            s.name == 'StompEndpoint' &&
            s.libraryUri.startsWith('package:diana/')))
          p,
    ];
    for (final endpoint in endpoints) {
      if (!wsTypeKeys.contains(endpoint.info.type.key)) {
        errors.add(
          'Class ${endpoint.info.type.displayName} '
          '(${endpoint.declaredIn}) extends StompEndpoint but is not '
          'annotated with @WebSocketController. Annotate it with '
          "@WebSocketController('/path') to expose the STOMP endpoint.",
        );
      } else if (endpoint.scope != 'singleton') {
        errors.add(
          '${endpoint.info.type.displayName} extends StompEndpoint but is '
          '${endpoint.scope}-scoped; STOMP endpoints must be singletons '
          '(one shared broker serves every connection).',
        );
      }
    }

    final seen =
        <String, (String, String, String)>{}; // dest -> (class, method, lib)
    for (final p in graph.ordered) {
      for (final mapping in p.info.messageMappings) {
        final prior = seen[mapping.destination];
        if (prior != null) {
          errors.add(
            '@MessageMapping destination "${mapping.destination}" is handled '
            'by both ${prior.$1}.${prior.$2} (${prior.$3}) and '
            '${p.info.type.displayName}.${mapping.methodName} '
            '(${p.declaredIn}). Destinations must be unique across the '
            'application.',
          );
        } else {
          seen[mapping.destination] =
              (p.info.type.displayName, mapping.methodName, p.declaredIn);
        }
      }
    }

    final hasMappings =
        graph.ordered.any((p) => p.info.messageMappings.isNotEmpty);
    if (hasMappings && endpoints.isEmpty) {
      errors.add(
        '@MessageMapping methods were found but no @WebSocketController '
        'extends StompEndpoint. Declare a singleton endpoint class extending '
        'StompEndpoint to accept STOMP connections.',
      );
    }
    return errors;
  }

  /// At most one `DianaObservability` provider, and it must be a singleton
  /// (the server, scheduler, bus and database all hold the same instance).
  List<String> _checkObservability(DiGraph graph) {
    final providers = _observabilityProviders(graph);
    if (providers.length > 1) {
      return [
        'Multiple DianaObservability providers: '
            '${providers.map((p) => '${p.info.type.displayName} '
                '(${p.declaredIn})').join(', ')}. Declare exactly one.',
      ];
    }
    if (providers.isNotEmpty) {
      final p = providers.single;
      if (p.scope != 'singleton' || p.needsRequestScope) {
        return [
          '${p.info.type.displayName} extends DianaObservability but is '
              '${p.scope}-scoped; observability providers must be singletons.',
        ];
      }
    }
    return const [];
  }

  /// When the app uses diana_data (injects `Database` or declares
  /// `@Transactional`), it needs exactly one `DatabaseConnector` to open the
  /// connection.
  List<String> _checkDatabase(DiGraph graph) {
    final connectors = _connectorProviders(graph);
    if (!graph.usesData && connectors.isEmpty) return const [];
    if (connectors.isEmpty) {
      return [
        '@Transactional/Database/DianaRepository usage found but no '
            'DatabaseConnector provider was declared. Add a @Component '
            'extending diana_data\'s DatabaseConnector.',
      ];
    }
    if (connectors.length > 1) {
      return [
        'Multiple DatabaseConnector providers: '
            '${connectors.map((p) => '${p.info.type.displayName} '
                '(${p.declaredIn})').join(', ')}. Declare exactly one.',
      ];
    }
    return const [];
  }

  /// gRPC interceptors are server-wide, so v1 requires every `@GrpcService`
  /// to declare identical security and exactly one singleton
  /// `AuthenticationMiddleware` to enforce it.
  List<String> _checkGrpcSecurity(
    DiGraph graph,
    List<LibrarySummary> summaries,
  ) {
    final services = [for (final s in summaries) ...s.grpcServices];
    final secured = services.where((s) => s.security != null).toList();
    if (secured.isEmpty) return const [];

    final errors = <String>[];
    final reference = secured.first;
    for (final service in services) {
      if (!_sameSecurity(service.security, reference.security)) {
        errors.add(
          'gRPC security is server-wide in this version; all @GrpcService '
          'classes must declare identical @Secured/@RolesAllowed (found '
          'differing declarations on ${reference.type.displayName} and '
          '${service.type.displayName}).',
        );
        break;
      }
    }

    final providers = _authMiddlewareProviders(graph);
    final singletons = providers
        .where((p) => p.scope == 'singleton' && !p.needsRequestScope)
        .toList();
    if (singletons.length != 1) {
      final found = providers.isEmpty
          ? 'none'
          : '${providers.length}: '
              '${providers.map((p) => p.info.type.displayName).join(', ')}';
      errors.add(
        '@Secured/@RolesAllowed on @GrpcService ${reference.type.displayName} '
        "requires exactly one singleton provider extending diana_auth's "
        'AuthenticationMiddleware; found $found.',
      );
    }
    return errors;
  }

  List<String> _checkGrpcServices(
    DiGraph graph,
    List<LibrarySummary> summaries,
  ) {
    final errors = <String>[];
    for (final summary in summaries) {
      for (final service in summary.grpcServices) {
        final provider = graph.byKey['${service.type.key}|'];
        final extendsService = provider != null &&
            provider.info.supertypes.any(
              (s) =>
                  s.name == 'Service' &&
                  s.libraryUri.startsWith('package:grpc/'),
            );
        if (!extendsService) {
          errors.add(
            '@GrpcService class ${service.type.displayName} does not extend '
            'a grpc service base class. Extend your protoc-generated '
            'XServiceBase (package:grpc Service).',
          );
        }
      }
    }
    return errors;
  }

  /// Generates proxy subclasses for every provider with aspect-annotated
  /// methods: the historical `$Tx$X` shape when only `@Transactional` is
  /// used (byte-identical output for existing apps), or `$Aspect$X` when
  /// any new aspect (@Timed/@Cacheable/@Retryable/@CircuitBreaker) is
  /// present — each override nests the aspect runtimes in the fixed order
  /// Timed → Cacheable → CircuitBreaker → Retryable → Transactional.
  List<Spec> _aspectProxies(DiGraph graph) {
    final proxies = <Spec>[];
    final useStore = _cacheStoreProviders(graph).isNotEmpty;
    for (final provider in graph.ordered) {
      if (provider.info.aspectMethods.isEmpty) continue;
      proxies.add(provider.info.hasNewAspects
          ? _aspectProxy(provider, useStore: useStore)
          : _txOnlyProxy(provider));
    }
    return proxies;
  }

  /// The historical `$Tx$X` proxy — the emission is kept verbatim so
  /// transactional-only apps stay byte-identical.
  Spec _txOnlyProxy(ResolvedProvider provider) {
    final txMethods = [
      for (final m in provider.info.aspectMethods)
        if (m.transactional) m,
    ];
    final base = provider.info.type;

    return Class((c) {
      c
        ..name = '\$Tx\$${base.name}'
        ..extend = referenceOf(base)
        ..fields.add(Field((f) => f
          ..name = '_db'
          ..modifier = FieldModifier.final$
          ..type = refer('Database', dianaDataLib)));

      // Constructor: (Database _db, <base ctor params>) : super(<forward>).
      final forwardPositional = <String>[];
      final forwardNamed = <String>[];
      c.constructors.add(Constructor((ctor) {
        ctor.requiredParameters.add(Parameter((p) => p
          ..name = '_db'
          ..toThis = true));
        for (final param in provider.info.ctorParams) {
          if (param.isNamed) {
            ctor.optionalParameters.add(Parameter((p) => p
              ..name = param.name
              ..named = true
              ..required = true
              ..type = referenceOf(param.type)));
            forwardNamed.add('${param.name}: ${param.name}');
          } else {
            ctor.requiredParameters.add(Parameter((p) => p
              ..name = param.name
              ..type = referenceOf(param.type)));
            forwardPositional.add(param.name);
          }
        }
        final superArgs = [...forwardPositional, ...forwardNamed].join(', ');
        ctor.initializers.add(Code('super($superArgs)'));
      }));

      // One override per @Transactional method.
      for (final method in txMethods) {
        final forwardArgs = <String>[];
        c.methods.add(Method((m) {
          m
            ..annotations.add(refer('override'))
            ..name = method.methodName
            ..returns = referenceOf(method.returnType);
          _declareTypeParams(m, method);
          for (final param in method.params) {
            final p = Parameter((b) {
              b
                ..name = param.name
                ..type = referenceOf(param.type);
              if (param.defaultCode != null) {
                b.defaultTo = Code(param.defaultCode!);
              }
              if (param.kind == 'named') b.named = true;
            });
            switch (param.kind) {
              case 'named':
                m.optionalParameters.add(p);
                forwardArgs.add('${param.name}: ${param.name}');
              case 'optionalPositional':
                m.optionalParameters.add(p);
                forwardArgs.add(param.name);
              default:
                m.requiredParameters.add(p);
                forwardArgs.add(param.name);
            }
          }
          m
            ..lambda = true
            ..body = Code('_db.runTransactional(() => '
                'super.${method.methodName}(${forwardArgs.join(', ')}))');
        }));
      }
    });
  }

  /// The `$Aspect$X` proxy: per-method cache/retry/breaker state fields and
  /// overrides nesting the aspect runtimes around `super.m(...)`.
  Spec _aspectProxy(ResolvedProvider provider, {required bool useStore}) {
    final info = provider.info;
    final base = info.type;
    // The store slot exists only when the app declares a DianaCacheStore
    // AND this class caches — otherwise the built-in MethodCache fields are
    // emitted verbatim (byte-identity for store-less apps).
    final storeSlot = useStore && info.hasCacheable;

    return Class((c) {
      c
        ..name = '\$Aspect\$${base.name}'
        ..extend = referenceOf(base);

      if (info.hasTimed) {
        c.fields.add(Field((f) => f
          ..name = '_observer'
          ..modifier = FieldModifier.final$
          ..type = TypeReference((t) => t
            ..symbol = 'DianaObserver'
            ..url = dianaLib
            ..isNullable = true)));
      }
      if (storeSlot) {
        c.fields.add(Field((f) => f
          ..name = '_cacheStore'
          ..modifier = FieldModifier.final$
          ..type = refer('DianaCacheStore', dianaLib)));
      }
      if (info.hasTx) {
        c.fields.add(Field((f) => f
          ..name = '_db'
          ..modifier = FieldModifier.final$
          ..type = refer('Database', dianaDataLib)));
      }

      // Per-method aspect state (method names are unique per class).
      for (final method in info.aspectMethods) {
        final name = method.methodName;
        final cacheable = method.cacheable;
        if (cacheable != null && storeSlot) {
          // With a store the cache field becomes a const spec handed to it.
          c.fields.add(Field((f) => f
            ..name = '_spec\$$name'
            ..static = true
            ..modifier = FieldModifier.constant
            ..assignment = Code.scope(
                (allocate) => '${allocate(refer('CacheSpec', dianaLib))}('
                    "method: '${base.name}.$name', "
                    'ttl: Duration(seconds: ${cacheable.ttlSeconds}), '
                    'maxEntries: ${cacheable.maxEntries})')));
        } else if (cacheable != null) {
          final valueType = method.returnType.typeArgs.isEmpty
              ? const TypeRef(libraryUri: '', name: 'dynamic')
              : method.returnType.typeArgs.first;
          c.fields.add(Field((f) => f
            ..name = '_cache\$$name'
            ..modifier = FieldModifier.final$
            ..assignment = Code.scope(
                (allocate) => '${allocate(refer('MethodCache', dianaLib))}'
                    '<${_typeCode(valueType, allocate)}>('
                    'ttl: const Duration(seconds: ${cacheable.ttlSeconds}), '
                    'maxEntries: ${cacheable.maxEntries})')));
        }
        final breaker = method.circuitBreaker;
        if (breaker != null) {
          c.fields.add(Field((f) => f
            ..name = '_breaker\$$name'
            ..modifier = FieldModifier.final$
            ..assignment = Code.scope((allocate) =>
                '${allocate(refer('CircuitBreakerPolicy', dianaLib))}('
                'failureThreshold: ${breaker.failureThreshold}, '
                'resetTimeout: const Duration('
                'milliseconds: ${breaker.resetTimeoutMs}))')));
        }
        final retryable = method.retryable;
        if (retryable != null) {
          c.fields.add(Field((f) => f
            ..name = '_retry\$$name'
            ..modifier = FieldModifier.final$
            ..assignment = Code.scope((allocate) {
              final predicate = retryable.retryOn.isEmpty
                  ? ''
                  : ', retryWhen: (e) => ${retryable.retryOn.map(
                        (t) => 'e is ${_typeCode(t, allocate)}',
                      ).join(' || ')}';
              return '${allocate(refer('RetryPolicy', dianaLib))}('
                  'maxAttempts: ${retryable.maxAttempts}, '
                  'backoff: const Duration('
                  'milliseconds: ${retryable.backoffMs})$predicate)';
            })));
        }
      }

      // Constructor: ([observer,] [db,] <base ctor params>) : super(...).
      final forwardPositional = <String>[];
      final forwardNamed = <String>[];
      c.constructors.add(Constructor((ctor) {
        if (info.hasTimed) {
          ctor.requiredParameters.add(Parameter((p) => p
            ..name = '_observer'
            ..toThis = true));
        }
        if (storeSlot) {
          ctor.requiredParameters.add(Parameter((p) => p
            ..name = '_cacheStore'
            ..toThis = true));
        }
        if (info.hasTx) {
          ctor.requiredParameters.add(Parameter((p) => p
            ..name = '_db'
            ..toThis = true));
        }
        for (final param in info.ctorParams) {
          if (param.isNamed) {
            ctor.optionalParameters.add(Parameter((p) => p
              ..name = param.name
              ..named = true
              ..required = true
              ..type = referenceOf(param.type)));
            forwardNamed.add('${param.name}: ${param.name}');
          } else {
            ctor.requiredParameters.add(Parameter((p) => p
              ..name = param.name
              ..type = referenceOf(param.type)));
            forwardPositional.add(param.name);
          }
        }
        final superArgs = [...forwardPositional, ...forwardNamed].join(', ');
        ctor.initializers.add(Code('super($superArgs)'));
      }));

      // One override per aspect method, layers nested in the fixed order.
      for (final method in info.aspectMethods) {
        final name = method.methodName;
        final forwardArgs = <String>[];
        final keyArgs = <String>[];
        c.methods.add(Method((m) {
          m
            ..annotations.add(refer('override'))
            ..name = name
            ..returns = referenceOf(method.returnType);
          _declareTypeParams(m, method);
          for (final param in method.params) {
            final p = Parameter((b) {
              b
                ..name = param.name
                ..type = referenceOf(param.type);
              if (param.defaultCode != null) {
                b.defaultTo = Code(param.defaultCode!);
              }
              if (param.kind == 'named') b.named = true;
            });
            switch (param.kind) {
              case 'named':
                m.optionalParameters.add(p);
                forwardArgs.add('${param.name}: ${param.name}');
              case 'optionalPositional':
                m.optionalParameters.add(p);
                forwardArgs.add(param.name);
              default:
                m.requiredParameters.add(p);
                forwardArgs.add(param.name);
            }
            keyArgs.add(param.name);
          }
          m
            ..lambda = true
            ..body = Code.scope((allocate) {
              var body = 'super.$name(${forwardArgs.join(', ')})';
              if (method.transactional) {
                body = '_db.runTransactional(() => $body)';
              }
              if (method.retryable != null) {
                body = '_retry\$$name.run(() => $body)';
              }
              if (method.circuitBreaker != null) {
                body = '_breaker\$$name.run(() => $body)';
              }
              if (method.cacheable != null) {
                body = storeSlot
                    ? '_cacheStore.run('
                        '_spec\$$name, [${keyArgs.join(', ')}], () => $body)'
                    : '_cache\$$name.run('
                        '[${keyArgs.join(', ')}], () => $body)';
              }
              if (method.timed != null) {
                final label = method.timed!.name ?? '${base.name}.$name';
                body = '${allocate(refer('runTimed', dianaLib))}('
                    "_observer, '$label', () => $body)";
              }
              return body;
            });
        }));
      }
    });
  }

  /// Re-declares a generic method's `<T extends B>` on its override.
  void _declareTypeParams(MethodBuilder m, AspectMethodInfo method) {
    for (final tp in method.typeParams) {
      m.types.add(TypeReference((t) {
        t.symbol = tp.name;
        final bound = tp.bound;
        if (bound != null) t.bound = referenceOf(bound);
      }));
    }
  }

  /// Renders a [TypeRef] as source inside a `Code.scope`, allocating the
  /// import prefix for it and its type arguments.
  String _typeCode(TypeRef type, String Function(Reference) allocate) {
    final baseName = type.libraryUri.isEmpty
        ? type.name
        : allocate(refer(type.name, type.libraryUri));
    final args = type.typeArgs.isEmpty
        ? ''
        : '<${type.typeArgs.map((t) => _typeCode(t, allocate)).join(', ')}>';
    return '$baseName$args${type.nullable ? '?' : ''}';
  }

  /// Generates `$Repo$X` implementations for every abstract query
  /// repository: the four CRUD methods plus one override per parsed query
  /// method, each a single fluent chain on the injected `Database`.
  List<Spec> _queryRepoImpls(DiGraph graph) => [
        for (final provider in graph.ordered)
          if (provider.info.queryRepo != null)
            _queryRepoImpl(provider, provider.info.queryRepo!),
      ];

  Spec _queryRepoImpl(ResolvedProvider provider, QueryRepoInfo repo) {
    final base = provider.info.type;
    final entity = repo.entity;
    final entityRef = referenceOf(entity);
    final entityNullableRef = referenceOf(TypeRef(
      libraryUri: entity.libraryUri,
      name: entity.name,
      nullable: true,
    ));
    final fromJson = refer('\$${entity.name}FromJson', entity.libraryUri);
    final toJson = refer('\$${entity.name}ToJson', entity.libraryUri);

    Reference futureOf(Reference inner) => TypeReference((t) => t
      ..symbol = 'Future'
      ..types.add(inner));
    Reference listOf(Reference inner) => TypeReference((t) => t
      ..symbol = 'List'
      ..types.add(inner));

    /// The WHERE/ORDER chain for [method], starting from `db.table(...)`.
    String chainOf(QueryMethodInfo method) {
      final buffer = StringBuffer("db.table('${repo.table}')");
      final or = method.connector == 'or';
      var slot = 0;
      var first = true;
      for (final condition in method.conditions) {
        final useOr = or && !first;
        first = false;
        final col = condition.column;
        String arg() => method.params[slot++].name;
        switch (condition.op) {
          case 'eq':
            buffer.write(
                ".${useOr ? 'orWhere' : 'where'}('$col', '=', ${arg()})");
          case 'not':
            buffer.write(
                ".${useOr ? 'orWhere' : 'where'}('$col', '<>', ${arg()})");
          case 'gt':
            buffer.write(
                ".${useOr ? 'orWhere' : 'where'}('$col', '>', ${arg()})");
          case 'gte':
            buffer.write(
                ".${useOr ? 'orWhere' : 'where'}('$col', '>=', ${arg()})");
          case 'lt':
            buffer.write(
                ".${useOr ? 'orWhere' : 'where'}('$col', '<', ${arg()})");
          case 'lte':
            buffer.write(
                ".${useOr ? 'orWhere' : 'where'}('$col', '<=', ${arg()})");
          case 'like':
            buffer.write(
                ".${useOr ? 'orWhere' : 'where'}('$col', 'like', ${arg()})");
          case 'contains':
            buffer.write(".${useOr ? 'orWhere' : 'where'}"
                "('$col', 'like', '%\$${arg()}%')");
          case 'startsWith':
            buffer.write(".${useOr ? 'orWhere' : 'where'}"
                "('$col', 'like', '\$${arg()}%')");
          case 'endsWith':
            buffer.write(".${useOr ? 'orWhere' : 'where'}"
                "('$col', 'like', '%\$${arg()}')");
          case 'inList':
            buffer.write(".whereIn('$col', ${arg()})");
          case 'notIn':
            buffer.write(
                ".${useOr ? 'orWhereNotIn' : 'whereNotIn'}('$col', ${arg()})");
          case 'between':
            final a = arg();
            final b = arg();
            buffer.write(".${useOr ? 'orWhereBetween' : 'whereBetween'}"
                "('$col', [$a, $b])");
          case 'isNull':
            buffer.write(".${useOr ? 'orWhereNull' : 'whereNull'}('$col')");
          case 'isNotNull':
            buffer
                .write(".${useOr ? 'orWhereNotNull' : 'whereNotNull'}('$col')");
        }
      }
      for (final order in method.orderBy) {
        buffer.write(
            ".orderBy('${order.column}', '${order.desc ? 'desc' : 'asc'}')");
      }
      return buffer.toString();
    }

    return Class((c) {
      c
        ..name = '\$Repo\$${base.name}'
        ..extend = referenceOf(base);

      // Constructor: forward the user's ctor params (the Database among
      // them) to super.
      final forwardPositional = <String>[];
      final forwardNamed = <String>[];
      c.constructors.add(Constructor((ctor) {
        for (final param in provider.info.ctorParams) {
          if (param.isNamed) {
            ctor.optionalParameters.add(Parameter((p) => p
              ..name = param.name
              ..named = true
              ..required = true
              ..type = referenceOf(param.type)));
            forwardNamed.add('${param.name}: ${param.name}');
          } else {
            ctor.requiredParameters.add(Parameter((p) => p
              ..name = param.name
              ..type = referenceOf(param.type)));
            forwardPositional.add(param.name);
          }
        }
        final superArgs = [...forwardPositional, ...forwardNamed].join(', ');
        ctor.initializers.add(Code('super($superArgs)'));
      }));

      // CRUD: findAll / findById / save / deleteById.
      c.methods.add(Method((m) => m
        ..annotations.add(refer('override'))
        ..name = 'findAll'
        ..returns = futureOf(listOf(entityRef))
        ..modifier = MethodModifier.async
        ..lambda = true
        ..body = Code.scope((allocate) => '[\n'
            "    for (final row in await db.select(db.table('${repo.table}')))\n"
            '      ${allocate(fromJson)}(row),\n'
            '  ]')));
      c.methods.add(Method((m) => m
        ..annotations.add(refer('override'))
        ..name = 'findById'
        ..requiredParameters.add(Parameter((p) => p
          ..name = 'id'
          ..type = refer('Object')))
        ..returns = futureOf(entityNullableRef)
        ..modifier = MethodModifier.async
        ..body = Code.scope((allocate) => 'final rows = await db.select('
            "db.table('${repo.table}').where('${repo.idColumn}', '=', id)"
            '.limit(1));\n'
            'return rows.isEmpty ? null : ${allocate(fromJson)}(rows.first);')));
      c.methods.add(Method((m) => m
        ..annotations.add(refer('override'))
        ..name = 'save'
        ..requiredParameters.add(Parameter((p) => p
          ..name = 'entity'
          ..type = entityRef))
        ..returns = futureOf(refer('void'))
        ..lambda = true
        ..body = Code.scope(
            (allocate) => "db.insert(db.table('${repo.table}').insert("
                '${allocate(toJson)}(entity)'
                '..removeWhere((k, v) => v == null)))')));
      c.methods.add(Method((m) => m
        ..annotations.add(refer('override'))
        ..name = 'deleteById'
        ..requiredParameters.add(Parameter((p) => p
          ..name = 'id'
          ..type = refer('Object')))
        ..returns = futureOf(refer('void'))
        ..lambda = true
        ..body = Code("db.delete(db.table('${repo.table}')"
            ".where('${repo.idColumn}', '=', id).delete())")));

      // Parsed query methods.
      for (final method in repo.methods) {
        c.methods.add(Method((m) {
          m
            ..annotations.add(refer('override'))
            ..name = method.name;
          for (final param in method.params) {
            m.requiredParameters.add(Parameter((p) => p
              ..name = param.name
              ..type = referenceOf(param.type)));
          }
          final chain = chainOf(method);
          switch (method.subject) {
            case 'find':
              m
                ..returns = futureOf(listOf(entityRef))
                ..modifier = MethodModifier.async
                ..lambda = true
                ..body = Code.scope((allocate) => '[\n'
                    '    for (final row in await db.select($chain))\n'
                    '      ${allocate(fromJson)}(row),\n'
                    '  ]');
            case 'findFirst':
              m
                ..returns = futureOf(entityNullableRef)
                ..modifier = MethodModifier.async
                ..body = Code.scope((allocate) =>
                    'final rows = await db.select($chain.limit(1));\n'
                    'return rows.isEmpty ? null : '
                    '${allocate(fromJson)}(rows.first);');
            case 'count':
              m
                ..returns = futureOf(refer('int'))
                ..lambda = true
                ..body = Code('runCount($chain)');
            case 'exists':
              m
                ..returns = futureOf(refer('bool'))
                ..lambda = true
                ..body = Code('runExists($chain)');
            default: // delete
              m
                ..returns = futureOf(refer('void'))
                ..lambda = true
                ..body = Code('db.delete($chain.delete())');
          }
        }));
      }
    });
  }

  /// A `const SecuredGuard()` / `const RolesGuard([...])` from diana_auth
  /// (referenced by URL string only — the generator never depends on it).
  Expression _guardExpr(SecurityInfo security) => security.roles == null
      ? refer('SecuredGuard', _dianaAuthLib).constInstance(const [])
      : refer('RolesGuard', _dianaAuthLib).constInstance([
          literalConstList([for (final r in security.roles!) literalString(r)]),
        ]);

  Expression _corsPolicyExpr(CorsInfo cors) =>
      refer('CorsPolicy', dianaLib).newInstance([], {
        'allowedOrigins':
            literalList([for (final o in cors.origins) literalString(o)]),
        if (cors.methods != null)
          'allowedMethods':
              literalList([for (final m in cors.methods!) literalString(m)]),
        'allowedHeaders':
            literalList([for (final h in cors.headers) literalString(h)]),
        if (cors.exposedHeaders.isNotEmpty)
          'exposedHeaders': literalList(
              [for (final h in cors.exposedHeaders) literalString(h)]),
        if (cors.credentials) 'allowCredentials': literalBool(true),
        'maxAgeSeconds': literalNum(cors.maxAge),
      });

  String _emitLibrary(
    DiGraph graph,
    List<LibrarySummary> summaries,
    AppInfo app,
  ) {
    final emission = emitContext(graph);
    final names = emission.names;

    final nullableConfigParam = Parameter((p) => p
      ..name = 'config'
      ..named = true
      ..type = TypeReference((t) => t
        ..symbol = 'DianaConfig'
        ..url = dianaLib
        ..isNullable = true));

    final overridesParam = Parameter((p) => p
      ..name = 'overrides'
      ..named = true
      ..type = refer('DianaOverrides')
      ..defaultTo = const Code('const DianaOverrides()'));

    final buildContextFn = Method((m) => m
      ..name = 'buildDianaContext'
      ..returns = refer('DianaContext')
      ..optionalParameters.addAll([nullableConfigParam, overridesParam])
      ..lambda = true
      ..body = refer('DianaContext').newInstance([
        refer('config')
            .ifNullThen(dianaConfigRef.constInstanceNamed('empty', const [])),
        refer('overrides'),
      ]).code);

    // Global middleware sorted by (order, type name) for determinism.
    final globalMiddleware = [
      for (final s in summaries) ...s.globalMiddleware,
    ]..sort((a, b) {
        final byOrder = a.order.compareTo(b.order);
        return byOrder != 0 ? byOrder : a.type.key.compareTo(b.type.key);
      });

    // Controllers sorted by type; routes stay in declaration order.
    final controllers = [for (final s in summaries) ...s.controllers]
      ..sort((a, b) => a.type.key.compareTo(b.type.key));

    Expression providerAccess(TypeRef type) =>
        names.access('${type.key}|', ctx: refer('ctx'));

    // Body codecs discovered through the DI graph (sorted for determinism).
    final bodyCodecProviders = [
      for (final provider in graph.ordered)
        if (provider.info.supertypes.any((s) =>
            s.name == 'BodyCodec' && s.libraryUri.startsWith('package:diana/')))
          provider,
    ];

    // The observability provider (validated by _checkObservability), used to
    // wire the observer into the server/scheduler/metrics endpoint.
    final observabilityProviders = _observabilityProviders(graph);
    final Expression? observabilityField = observabilityProviders.isEmpty
        ? null
        : refer('ctx')
            .property(names.fields[observabilityProviders.single.key]!);

    // Exception handlers across all advices, most specific exception type
    // first (ties broken by advice type then declaration order).
    final advices = [for (final s in summaries) ...s.advices]
      ..sort((a, b) => a.type.key.compareTo(b.type.key));
    final handlers = <(AdviceInfo, HandlerInfo)>[
      for (final advice in advices)
        for (final handler in advice.handlers) (advice, handler),
    ];
    final handlerOrder = {
      for (final (i, entry) in handlers.indexed) entry: i,
    };
    handlers.sort((a, b) {
      final byDepth = b.$2.depth.compareTo(a.$2.depth);
      return byDepth != 0
          ? byDepth
          : handlerOrder[a]!.compareTo(handlerOrder[b]!);
    });

    Method? mapExceptionFn;
    if (handlers.isNotEmpty) {
      mapExceptionFn = Method((m) => m
        ..name = '_mapException'
        ..returns = TypeReference((t) => t
          ..symbol = 'FutureOr'
          ..url = 'dart:async'
          ..types.add(TypeReference((r) => r
            ..symbol = 'DianaResponse'
            ..url = dianaLib
            ..isNullable = true)))
        ..requiredParameters.addAll([
          Parameter((p) => p
            ..name = 'ctx'
            ..type = refer('DianaContext')),
          Parameter((p) => p
            ..name = 'e'
            ..type = refer('Object')),
          Parameter((p) => p
            ..name = 'req'
            ..type = refer('DianaRequest', dianaLib)),
        ])
        ..body = Block.of([
          for (final (advice, handler) in handlers)
            Code.scope((allocate) {
              final adviceField = names.fields['${advice.type.key}|']!;
              final excType = allocate(referenceOf(handler.exceptionType));
              final args = handler.takesRequest ? 'e, req' : 'e';
              return 'if (e is $excType) '
                  'return ctx.$adviceField.${handler.methodName}($args);';
            }),
          const Code('return null;'),
        ]));
    }

    final serverStatements = <Code>[
      declareFinal('cfg')
          .assign(refer('config').ifNullThen(dianaConfigRef
              .property('load')
              .call([literalString(app.configFile)]).awaited))
          .statement,
      declareFinal('ctx')
          .assign(refer('DianaContext')
              .newInstance([refer('cfg'), refer('overrides')]))
          .statement,
      declareFinal('server')
          .assign(refer('DianaServer', dianaLib).newInstance([], {
            'config': refer('cfg'),
            if (globalMiddleware.isNotEmpty)
              'globalMiddleware': literalList([
                for (final mw in globalMiddleware) providerAccess(mw.type),
              ]),
            if (bodyCodecProviders.isNotEmpty)
              'bodyCodecs': literalList([
                for (final codec in bodyCodecProviders)
                  refer('ctx').property(names.fields[codec.key]!),
              ]),
            if (observabilityField != null) 'observer': observabilityField,
            if (mapExceptionFn != null)
              'exceptionMapper': Method((m) => m
                    ..requiredParameters.addAll([
                      Parameter((p) => p..name = 'e'),
                      Parameter((p) => p..name = 'st'),
                      Parameter((p) => p..name = 'req'),
                    ])
                    ..lambda = true
                    ..body = refer('_mapException')
                        .call([refer('ctx'), refer('e'), refer('req')]).code)
                  .closure,
          }))
          .statement,
    ];

    for (final controller in controllers) {
      final controllerKey = '${controller.type.key}|';
      final onRequestScope = names.onRequestScope.contains(controllerKey);
      for (final route in controller.routes) {
        final adapterRef = refer(route.adapterName, controller.type.libraryUri);
        final handler = Method((m) {
          m.requiredParameters.add(Parameter((p) => p..name = 'req'));
          if (onRequestScope) {
            m.body = Block.of([
              declareFinal('scope')
                  .assign(
                      refer('DianaRequestScope').newInstance([refer('ctx')]))
                  .statement,
              adapterRef
                  .call([
                    names.access(controllerKey,
                        ctx: refer('ctx'), scope: refer('scope')),
                    refer('req'),
                  ])
                  .returned
                  .statement,
            ]);
          } else {
            m.lambda = true;
            m.body = adapterRef.call([
              names.access(controllerKey, ctx: refer('ctx')),
              refer('req'),
            ]).code;
          }
        }).closure;

        final cors = route.cors ?? controller.cors;
        final security = route.security ?? controller.security;
        // Guards run after any authentication middleware and immediately
        // before the handler ⇒ appended last in the per-route chain.
        final routeMiddleware = <Expression>[
          for (final mw in controller.middleware) providerAccess(mw),
          for (final mw in route.middleware) providerAccess(mw),
          if (security != null) _guardExpr(security),
        ];
        serverStatements.add(refer('server').property('register').call(
          [
            refer('HttpMethod', dianaLib)
                .property(route.httpMethod.toLowerCase()),
            literalString(joinPaths(controller.basePath, route.path)),
            handler,
          ],
          {
            if (routeMiddleware.isNotEmpty)
              'middleware': literalList(routeMiddleware),
            if (cors != null) 'cors': _corsPolicyExpr(cors),
          },
        ).statement);
      }
    }
    // Actuator endpoints, guarded at runtime by management.enabled.
    final healthIndicators = <ResolvedProvider>[];
    for (final provider in graph.ordered) {
      final implementsIndicator = provider.info.supertypes.any(
        (s) =>
            s.name == 'HealthIndicator' &&
            s.libraryUri.startsWith('package:diana/'),
      );
      if (implementsIndicator) healthIndicators.add(provider);
    }
    serverStatements.add(Code.scope((allocate) {
      final httpMethod = allocate(refer('HttpMethod', dianaLib));
      final healthHandler = allocate(refer('healthEndpointHandler', dianaLib));
      final infoHandler = allocate(refer('infoEndpointHandler', dianaLib));
      final livenessHandler =
          allocate(refer('livenessEndpointHandler', dianaLib));
      final readinessHandler =
          allocate(refer('readinessEndpointHandler', dianaLib));
      final indicators =
          healthIndicators.map((p) => 'ctx.${names.fields[p.key]!}').join(', ');
      // /actuator/metrics is emitted only when an observability provider
      // exists (compile-time gate — apps without it stay byte-identical).
      String metricsLine = '';
      if (observabilityField != null) {
        final metricsHandler =
            allocate(refer('metricsEndpointHandler', dianaObservabilityLib));
        final field = names.fields[observabilityProviders.single.key]!;
        metricsLine = '''
  server.register(
    $httpMethod.get,
    '/actuator/metrics',
    $metricsHandler(ctx.$field),
  );
''';
      }
      return '''
if (cfg.get<bool>('management.enabled', defaultValue: false)) {
  server.register(
    $httpMethod.get,
    '/actuator/health',
    $healthHandler([$indicators]),
  );
  server.register(
    $httpMethod.get,
    '/actuator/health/liveness',
    $livenessHandler(),
  );
  server.register(
    $httpMethod.get,
    '/actuator/health/readiness',
    $readinessHandler([$indicators]),
  );
  server.register(
    $httpMethod.get,
    '/actuator/info',
    $infoHandler(cfg),
  );
$metricsLine}
''';
    }));

    // OpenAPI: served at GET /openapi.json when server.openapi.enabled.
    serverStatements.add(Code.scope((allocate) {
      final httpMethod = allocate(refer('HttpMethod', dianaLib));
      final dianaResponse = allocate(refer('DianaResponse', dianaLib));
      final patch = allocate(refer('patchOpenApiInfo', dianaLib));
      return '''
if (cfg.get<bool>('server.openapi.enabled', defaultValue: false)) {
  final openApiBody = $patch(dianaOpenApiJson, cfg);
  server.register(
    $httpMethod.get,
    '/openapi.json',
    (req) => $dianaResponse(
      statusCode: 200,
      bodyText: openApiBody,
      mimeType: 'application/json',
    ),
  );
}
''';
    }));

    // WebSocket endpoints, sorted by path for deterministic output.
    final webSockets = [for (final s in summaries) ...s.webSockets]
      ..sort((a, b) => a.path.compareTo(b.path));
    for (final ws in webSockets) {
      final factory = Method((m) => m
            ..lambda = true
            ..body = names.access('${ws.type.key}|', ctx: refer('ctx')).code)
          .closure;
      // Guards run as handshake interceptors, after the (controller-level)
      // authentication middleware and last before the upgrade.
      final wsMiddleware = <Expression>[
        for (final mw in ws.middleware) providerAccess(mw),
        if (ws.security != null) _guardExpr(ws.security!),
      ];
      serverStatements.add(refer('server').property('registerWebSocket').call(
        [literalString(ws.path), factory],
        {
          if (wsMiddleware.isNotEmpty) 'middleware': literalList(wsMiddleware),
        },
      ).statement);
    }

    // gRPC services (sorted for determinism); referenced by URL string so
    // the generator itself never depends on diana_grpc.
    const dianaGrpcLib = 'package:diana_grpc/diana_grpc.dart';
    final grpcServices = [for (final s in summaries) ...s.grpcServices]
      ..sort((a, b) => a.type.key.compareTo(b.type.key));

    if (grpcServices.isNotEmpty) {
      final grpcSecurity = grpcServices
          .firstWhere((s) => s.security != null,
              orElse: () => grpcServices.first)
          .security;
      Expression? interceptors;
      if (grpcSecurity != null) {
        // Validated by _checkGrpcSecurity: exactly one singleton provider.
        final authField =
            names.fields[_authMiddlewareProviders(graph).single.key]!;
        interceptors = literalList([
          refer('grpcAuthInterceptor', dianaGrpcLib).call([
            refer('ctx').property(authField).property('authorizeMetadata'),
          ], {
            if (grpcSecurity.roles != null)
              'rolesAllowed': literalList(
                  [for (final r in grpcSecurity.roles!) literalString(r)]),
          }),
        ]);
      }
      serverStatements.add(declareFinal('grpcServer')
          .assign(refer('DianaGrpcServer', dianaGrpcLib).newInstance([
            refer('cfg')
          ], {
            'services': literalList([
              for (final service in grpcServices)
                refer('ctx').property(names.fields['${service.type.key}|']!),
            ]),
            if (interceptors != null) 'interceptors': interceptors,
          }))
          .statement);
    }

    serverStatements.add(refer('DianaApp')
        .newInstance([
          refer('ctx'),
          refer('server'),
          if (grpcServices.isNotEmpty) refer('grpcServer'),
        ])
        .returned
        .statement);

    // Scheduled tasks across all singleton providers.
    final scheduledEntries =
        <({String field, String typeName, ScheduledMethodInfo task})>[];
    for (final provider in graph.ordered) {
      for (final task in provider.info.scheduled) {
        scheduledEntries.add((
          field: names.fields[provider.key]!,
          typeName: provider.info.type.name,
          task: task,
        ));
      }
    }
    final schedulerObserver = observabilityProviders.isEmpty
        ? ''
        : 'observer: context.${names.fields[observabilityProviders.single.key]!}';

    final appClass = Class((c) {
      c
        ..name = 'DianaApp'
        ..docs.add('/// The assembled application: context, server and '
            'lifecycle entrypoints.')
        ..fields.addAll([
          Field((f) => f
            ..name = 'context'
            ..modifier = FieldModifier.final$
            ..type = refer('DianaContext')),
          Field((f) => f
            ..name = 'server'
            ..modifier = FieldModifier.final$
            ..type = refer('DianaServer', dianaLib)),
          if (grpcServices.isNotEmpty)
            Field((f) => f
              ..name = 'grpcServer'
              ..modifier = FieldModifier.final$
              ..type = refer('DianaGrpcServer', dianaGrpcLib)),
        ])
        ..constructors
            .add(Constructor((ctor) => ctor.requiredParameters.addAll([
                  Parameter((p) => p
                    ..name = 'context'
                    ..toThis = true),
                  Parameter((p) => p
                    ..name = 'server'
                    ..toThis = true),
                  if (grpcServices.isNotEmpty)
                    Parameter((p) => p
                      ..name = 'grpcServer'
                      ..toThis = true),
                ])));
      if (scheduledEntries.isEmpty && grpcServices.isEmpty) {
        c.methods.addAll([
          Method((m) => m
            ..name = 'initialize'
            ..returns = refer('Future<void>')
            ..lambda = true
            ..body =
                refer('context').property('initialize').call(const []).code),
          Method((m) => m
            ..name = 'dispose'
            ..returns = refer('Future<void>')
            ..lambda = true
            ..body = refer('context').property('dispose').call(const []).code),
        ]);
      } else {
        if (scheduledEntries.isNotEmpty) {
          c.fields.add(Field((f) => f
            ..name = 'scheduler'
            ..late = true
            ..modifier = FieldModifier.final$
            ..type = refer('DianaScheduler', dianaLib)
            ..assignment = Code.scope((allocate) {
              final scheduler = allocate(refer('DianaScheduler', dianaLib));
              final buffer = StringBuffer('$scheduler($schedulerObserver)');
              for (final entry in scheduledEntries) {
                final task = entry.task;
                buffer.write('\n    ..schedule(task: () async => '
                    'context.${entry.field}.${task.methodName}(), ');
                if (task.fixedRateMs != null) {
                  buffer.write('fixedRateMs: ${task.fixedRateMs}');
                } else if (task.fixedDelayMs != null) {
                  buffer.write('fixedDelayMs: ${task.fixedDelayMs}');
                } else {
                  final literal =
                      task.cron!.replaceAll(r'\', r'\\').replaceAll("'", r"\'");
                  buffer.write("cron: '$literal'");
                }
                if (task.initialDelayMs != 0) {
                  buffer.write(', initialDelayMs: ${task.initialDelayMs}');
                }
                if (task.perIsolate) {
                  buffer.write(', perIsolate: true');
                }
                // The task name labels observability metrics; emitted only
                // when observability is in use (byte-identical otherwise).
                if (schedulerObserver.isNotEmpty) {
                  buffer
                      .write(", name: '${entry.typeName}.${task.methodName}'");
                }
                buffer.write(')');
              }
              return buffer.toString();
            })));
        }
        c.methods.addAll([
          Method((m) => m
            ..name = 'initialize'
            ..returns = refer('Future<void>')
            ..modifier = MethodModifier.async
            ..body = Block.of([
              refer('context')
                  .property('initialize')
                  .call(const [])
                  .awaited
                  .statement,
              if (scheduledEntries.isNotEmpty)
                refer('scheduler').property('start').call(const []).statement,
              if (grpcServices.isNotEmpty)
                refer('grpcServer')
                    .property('serve')
                    .call(const [])
                    .awaited
                    .statement,
            ])),
          Method((m) => m
            ..name = 'dispose'
            ..returns = refer('Future<void>')
            ..modifier = MethodModifier.async
            ..body = Block.of([
              if (grpcServices.isNotEmpty)
                refer('grpcServer')
                    .property('shutdown')
                    .call(const [])
                    .awaited
                    .statement,
              if (scheduledEntries.isNotEmpty)
                refer('scheduler')
                    .property('stop')
                    .call(const [])
                    .awaited
                    .statement,
              refer('context')
                  .property('dispose')
                  .call(const [])
                  .awaited
                  .statement,
            ])),
        ]);
      }
    });

    final buildAppFn = Method((m) => m
      ..name = 'buildDianaApp'
      ..returns = refer('Future<DianaApp>')
      ..optionalParameters.addAll([nullableConfigParam, overridesParam])
      ..modifier = MethodModifier.async
      ..body = Block.of(serverStatements));

    final buildServerFn = Method((m) => m
      ..name = 'buildDianaServer'
      ..returns = TypeReference((t) => t
        ..symbol = 'Future'
        ..types.add(refer('DianaServer', dianaLib)))
      ..optionalParameters.addAll([nullableConfigParam, overridesParam])
      ..modifier = MethodModifier.async
      ..body = Block.of([
        declareFinal('app')
            .assign(refer('buildDianaApp').call([], {
              'config': refer('config'),
              'overrides': refer('overrides'),
            }).awaited)
            .statement,
        refer('app').property('server').returned.statement,
      ]));

    final runFn = Method((m) => m
      ..name = 'runDiana'
      ..returns = refer('Future<void>')
      ..optionalParameters.addAll([nullableConfigParam, overridesParam])
      ..body = refer('DianaRuntime', dianaLib).property('run').call([
        Method((b) => b
          ..modifier = MethodModifier.async
          ..body = Block.of([
            declareFinal('app')
                .assign(refer('buildDianaApp').call([], {
                  'config': refer('config'),
                  'overrides': refer('overrides'),
                }).awaited)
                .statement,
            refer('DianaRunnable', dianaLib)
                .newInstance([], {
                  'server': refer('app').property('server'),
                  'initialize': refer('app').property('initialize'),
                  'dispose': refer('app').property('dispose'),
                  if (graph.usesEvents || graph.usesStomp)
                    'eventBus':
                        refer('app').property('context').property('eventBus'),
                })
                .returned
                .statement,
          ])).closure,
      ]).code
      ..lambda = true);

    final openApiJson =
        _jsonStringLiteral(jsonEncode(buildOpenApiDocument(summaries)));
    final openApiConst = Field((f) => f
      ..name = 'dianaOpenApiJson'
      ..modifier = FieldModifier.constant
      ..type = refer('String')
      ..docs.add('/// Build-time OpenAPI 3 document (info patched from '
          'config at startup).')
      ..assignment = Code(openApiJson));

    final generated = Library((b) => b
      ..body.addAll([
        ...emission.specs,
        ..._aspectProxies(graph),
        ..._queryRepoImpls(graph),
        appClass,
        buildContextFn,
        if (mapExceptionFn != null) mapExceptionFn,
        openApiConst,
        buildAppFn,
        buildServerFn,
        runFn,
      ]));

    final emitter = DartEmitter(
      allocator: Allocator.simplePrefixing(),
      orderDirectives: true,
      useNullSafetySyntax: true,
    );
    final raw = '$generatedHeader\n${generated.accept(emitter)}';
    return DartFormatter(
      languageVersion: DartFormatter.latestLanguageVersion,
    ).format(raw);
  }
}

/// Escapes a JSON document into a single-quoted Dart string literal.
String _jsonStringLiteral(String value) {
  final escaped = value
      .replaceAll('\\', '\\\\')
      .replaceAll(r'$', r'\$')
      .replaceAll("'", r"\'");
  return "'$escaped'";
}
