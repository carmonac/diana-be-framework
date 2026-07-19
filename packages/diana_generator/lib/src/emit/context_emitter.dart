/// Emits the `DianaContext` (and, when needed, `DianaRequestScope`) classes
/// from a resolved [DiGraph] using code_builder.
///
/// The generated context IS the DI container: typed `late final` fields in
/// topological order for singletons, factory methods for transients — no
/// maps, no `Type` lookups, no reflection.
library;

import 'package:code_builder/code_builder.dart';

import '../graph/di_graph.dart';
import '../model/summary.dart';

const String dianaLib = 'package:diana/diana.dart';

/// diana_data runtime types are referenced by import URL only — the
/// generator never depends on diana_data (mirrors `dianaGrpcLib`).
const String dianaDataLib = 'package:diana_data/diana_data.dart';

Reference get dianaConfigRef => refer('DianaConfig', dianaLib);

/// Converts a summary [TypeRef] into a code_builder reference (imports are
/// handled by the emitter's allocator).
Reference referenceOf(TypeRef type) => TypeReference((b) {
      b
        ..symbol = type.name
        ..url = type.libraryUri.isEmpty ? null : type.libraryUri
        ..isNullable = type.nullable ? true : null;
      b.types.addAll([for (final a in type.typeArgs) referenceOf(a)]);
    });

/// Where each provider lives in the generated code, for use by the server
/// wiring emitter.
class ContextNames {
  /// providerKey -> field name (singleton fields, on their owner class).
  final Map<String, String> fields = {};

  /// providerKey -> factory method name (transients, on their owner class).
  final Map<String, String> methods = {};

  /// providerKey -> field name on the generated `DianaOverrides` class.
  final Map<String, String> overrideFields = {};

  /// Providers that live on `DianaRequestScope` instead of `DianaContext`.
  final Set<String> onRequestScope = {};

  bool hasRequestScope = false;

  /// The `Database` field name on `DianaContext`, when the app uses
  /// diana_data (else null).
  String? database;

  /// Expression reading provider [key] given an expression for the context
  /// ([ctx]) and, when inside the request scope, the scope itself ([scope]).
  Expression access(String key, {required Expression ctx, Expression? scope}) {
    final owner = onRequestScope.contains(key) ? scope! : ctx;
    final field = fields[key];
    if (field != null) return owner.property(field);
    return owner.property(methods[key]!).call(const []);
  }
}

class ContextEmission {
  final List<Spec> specs;
  final ContextNames names;
  ContextEmission(this.specs, this.names);
}

/// Builds the context (and request scope) class specs for [graph].
ContextEmission emitContext(DiGraph graph) {
  final names = ContextNames();

  // The single DatabaseConnector provider (validated by _checkDatabase), used
  // to construct the context's Database field.
  ResolvedProvider? connectorProvider;
  if (graph.usesData) {
    for (final p in graph.ordered) {
      if (p.info.supertypes.any((s) =>
          s.name == 'DatabaseConnector' &&
          s.libraryUri.startsWith('package:diana_data/'))) {
        connectorProvider = p;
        break;
      }
    }
  }
  final usesData = graph.usesData && connectorProvider != null;

  // The single DianaObservability provider (validated in the bootstrap), if
  // any — threaded as `observer:` into the event bus and database.
  ResolvedProvider? observabilityProvider;
  for (final p in graph.ordered) {
    if (p.info.supertypes.any((s) =>
        s.name == 'DianaObservability' &&
        s.libraryUri.startsWith('package:diana_observability/'))) {
      observabilityProvider = p;
      break;
    }
  }

  // The single DianaCacheStore provider (validated in the bootstrap), if
  // any — threaded as the proxy's `_cacheStore` slot for cached classes.
  ResolvedProvider? cacheStoreProvider;
  for (final p in graph.ordered) {
    if (p.info.supertypes.any((s) =>
        s.name == 'DianaCacheStore' &&
        s.libraryUri.startsWith('package:diana/'))) {
      cacheStoreProvider = p;
      break;
    }
  }

  // 'eventBus'/'database'/'stompBroker' are reserved only when used, so apps
  // without those features keep byte-identical output. STOMP reuses the
  // event bus for cross-isolate relay, so it also needs 'eventBus'.
  final usesStomp = graph.usesStomp;
  final used = <String>{
    'config',
    if (graph.usesEvents || usesStomp) 'eventBus',
    if (usesData) 'database',
    if (usesStomp) 'stompBroker',
  };
  if (usesData) names.database = 'database';

  String allocate(String base) {
    var name = base;
    var counter = 1;
    while (used.contains(name)) {
      name = '$base\$${counter++}';
    }
    used.add(name);
    return name;
  }

  String lowerFirst(String s) =>
      s.isEmpty ? s : s[0].toLowerCase() + s.substring(1);

  for (final provider in graph.ordered) {
    final base = lowerFirst(provider.info.type.name);
    if (provider.scope == 'transient') {
      names.methods[provider.key] =
          allocate('create${provider.info.type.name}');
      names.overrideFields[provider.key] = allocate(base);
    } else {
      final field = allocate(base);
      names.fields[provider.key] = field;
      names.overrideFields[provider.key] = field;
    }
    if (provider.needsRequestScope) {
      names.onRequestScope.add(provider.key);
      names.hasRequestScope = true;
    }
  }

  Expression construct(ResolvedProvider provider, {required bool onScope}) {
    Expression ctxProp(String name) =>
        onScope ? refer('_ctx').property(name) : refer(name);
    Expression configExpr() =>
        onScope ? refer('_ctx').property('config') : refer('config');

    Expression depExpr(ResolvedDep dep) {
      if (dep.isConfigValue) {
        final param = dep.param;
        return configExpr().property('get').call(
          [literalString(param.valueKey!)],
          {
            if (param.hasValueDefault)
              'defaultValue': literal(param.valueDefault),
          },
          [referenceOf(param.type)],
        );
      }
      if (dep.isEventPublisher) return ctxProp('eventBus');
      if (dep.isDbExecutor) return ctxProp(names.database!);
      if (dep.isStompBroker) return ctxProp('stompBroker');
      final key = dep.providerKey!;
      final method = names.methods[key];
      final onScopeDep = names.onRequestScope.contains(key);
      if (method != null) {
        final target = onScopeDep ? refer(method) : ctxProp(method);
        return target.call(const []);
      }
      final field = names.fields[key]!;
      return onScopeDep ? refer(field) : ctxProp(field);
    }

    Expression construction;
    if (provider.info.kind == ProviderKind.configProps) {
      construction = refer(
        '\$${provider.info.type.name}FromConfig',
        provider.info.type.libraryUri,
      ).call([configExpr()]);
    } else {
      final positional = <Expression>[];
      final named = <String, Expression>{};
      for (final dep in provider.deps) {
        if (dep.param.isNamed) {
          named[dep.param.name] = depExpr(dep);
        } else {
          positional.add(depExpr(dep));
        }
      }
      // Aspect-annotated providers are constructed as a generated proxy
      // subclass, local to the app library: the historical $Tx$X (Database
      // first) when only @Transactional is used, or $Aspect$X — observer
      // and/or Database prepended — when new aspects are present.
      final info = provider.info;
      final observability = observabilityProvider;
      final cacheStore = cacheStoreProvider;
      if (info.isQueryRepo) {
        // Abstract query repositories are constructed as their generated
        // implementation; deps (the Database among them) flow through the
        // user-declared constructor unchanged.
        construction = refer('\$Repo\$${info.type.name}')
            .newInstance(positional, named);
      } else if (info.hasNewAspects) {
        construction = refer('\$Aspect\$${info.type.name}').newInstance(
          [
            if (info.hasTimed)
              observability == null
                  ? literalNull
                  : ctxProp(names.fields[observability.key]!),
            if (info.hasCacheable && cacheStore != null)
              ctxProp(names.fields[cacheStore.key]!),
            if (info.hasTx) ctxProp(names.database!),
            ...positional,
          ],
          named,
        );
      } else if (info.hasTx) {
        construction = refer('\$Tx\$${info.type.name}').newInstance(
          [ctxProp(names.database!), ...positional],
          named,
        );
      } else {
        construction =
            referenceOf(info.type).newInstance(positional, named);
      }
    }
    final overridesExpr =
        onScope ? refer('_ctx').property('_overrides') : refer('_overrides');
    return overridesExpr
        .property(names.overrideFields[provider.key]!)
        .ifNullThen(construction);
  }

  Field providerField(ResolvedProvider provider, {required bool onScope}) =>
      Field((f) => f
        ..name = names.fields[provider.key]!
        ..late = true
        ..modifier = FieldModifier.final$
        ..type = referenceOf(provider.info.type)
        ..assignment = construct(provider, onScope: onScope).code);

  Method providerMethod(ResolvedProvider provider, {required bool onScope}) =>
      Method((m) => m
        ..name = names.methods[provider.key]!
        ..returns = referenceOf(provider.info.type)
        ..lambda = true
        ..body = construct(provider, onScope: onScope).code);

  final overridesClass = Class((c) {
    c
      ..name = 'DianaOverrides'
      ..docs.add('/// Per-provider overrides for tests: a non-null field '
          'replaces the real provider everywhere it is injected.')
      ..constructors.add(Constructor((ctor) {
        ctor.constant = true;
        for (final provider in graph.ordered) {
          ctor.optionalParameters.add(Parameter((p) => p
            ..name = names.overrideFields[provider.key]!
            ..named = true
            ..toThis = true));
        }
      }));
    for (final provider in graph.ordered) {
      c.fields.add(Field((f) => f
        ..name = names.overrideFields[provider.key]!
        ..modifier = FieldModifier.final$
        ..type = TypeReference((t) => t
          ..symbol = provider.info.type.name
          ..url = provider.info.type.libraryUri
          ..isNullable = true)));
    }
  });

  final initializables = [
    for (final provider in graph.ordered)
      if (!provider.needsRequestScope && provider.scope != 'transient')
        provider,
  ];

  final initializeMethod = Method((m) => m
    ..name = 'initialize'
    ..returns = refer('Future<void>')
    ..modifier = MethodModifier.async
    ..docs.add('/// Constructs every singleton in dependency order and '
        'runs @PostConstruct hooks.')
    ..body = Block.of([
      // Open the database (and run migrations) before any provider so a
      // repository's @PostConstruct can already query.
      if (usesData) ...[
        Code('await ${names.database}.open();'),
        Code('await ${names.database}.migrate();'),
      ],
      for (final provider in initializables)
        provider.info.postConstruct == null
            ? Code('${names.fields[provider.key]!};')
            : Code('${provider.info.postConstructAwaited ? 'await ' : ''}'
                '${names.fields[provider.key]!}'
                '.${provider.info.postConstruct}();'),
    ]));

  final disposeMethod = Method((m) => m
    ..name = 'dispose'
    ..returns = refer('Future<void>')
    ..modifier = MethodModifier.async
    ..docs.add('/// Runs @PreDestroy hooks in reverse dependency order; '
        'call after initialize().')
    ..body = Block.of([
      for (final provider in initializables.reversed)
        if (provider.info.preDestroy != null)
          Code('${provider.info.preDestroyAwaited ? 'await ' : ''}'
              '${names.fields[provider.key]!}'
              '.${provider.info.preDestroy}();'),
      // Close the connection after @PreDestroy hooks have run.
      if (usesData) Code('await ${names.database}.close();'),
    ]));

  final contextClass = Class((c) {
    c
      ..name = 'DianaContext'
      ..fields.add(Field((f) => f
        ..name = 'config'
        ..modifier = FieldModifier.final$
        ..type = dianaConfigRef))
      ..fields.add(Field((f) => f
        ..name = '_overrides'
        ..modifier = FieldModifier.final$
        ..type = refer('DianaOverrides')))
      ..constructors.add(Constructor((ctor) {
        ctor
          ..requiredParameters.add(Parameter((p) => p
            ..name = 'config'
            ..toThis = true))
          ..optionalParameters.add(Parameter((p) => p
            ..name = '_overrides'
            ..toThis = true
            ..defaultTo = const Code('const DianaOverrides()')));
        // Listener registration happens in the constructor so publishes
        // during initialize() (@PostConstruct) are already delivered. The
        // closures dereference the late provider fields only when an event
        // fires — no eager construction.
        final ctorStatements = <Code>[
          for (final provider in graph.ordered)
            for (final listener in provider.info.eventListeners)
              Code.scope((allocate) =>
                  'eventBus.on<${allocate(referenceOf(listener.eventType))}>'
                  '((e) => ${names.fields[provider.key]!}'
                  '.${listener.methodName}(e));'),
          for (final provider in graph.ordered)
            for (final mapping in provider.info.messageMappings)
              _mappingRegistration(provider, mapping, names),
        ];
        // The broker registers its cross-isolate relay listener in its ctor,
        // so it must be constructed before any remote broadcast — touch it
        // even when there are no mappings.
        if (usesStomp && ctorStatements.isEmpty) {
          ctorStatements.add(const Code('stompBroker;'));
        } else if (usesStomp &&
            !graph.ordered
                .any((p) => p.info.messageMappings.isNotEmpty)) {
          ctorStatements.add(const Code('stompBroker;'));
        }
        if (ctorStatements.isNotEmpty) {
          ctor.body = Block.of(ctorStatements);
        }
      }));
    // Observability is a regular provider; its field carries the observer.
    final observerArgs = observabilityProvider == null
        ? const <String, Expression>{}
        : {'observer': refer(names.fields[observabilityProvider.key]!)};
    if (graph.usesEvents || usesStomp) {
      c.fields.add(Field((f) => f
        ..name = 'eventBus'
        // `late` only when the initializer references another field (the
        // observer); event-only apps keep the plain `final` form.
        ..late = observabilityProvider != null
        ..modifier = FieldModifier.final$
        ..type = refer('DianaEventBus', dianaLib)
        ..assignment = refer('DianaEventBus', dianaLib)
            .newInstance(const [], observerArgs)
            .code));
    }
    if (usesStomp) {
      // The broker relays topic publishes across isolates through the event
      // bus; `late` because its initializer references the eventBus field.
      c.fields.add(Field((f) => f
        ..name = 'stompBroker'
        ..late = true
        ..modifier = FieldModifier.final$
        ..assignment = refer('StompBroker', dianaLib)
            .newInstance([refer('eventBus'), refer('config')]).code));
    }
    if (usesData) {
      // Opened at the start of initialize() and closed at the end of
      // dispose(); the connector is constructed lazily on first access.
      c.fields.add(Field((f) => f
        ..name = names.database!
        ..late = true
        ..modifier = FieldModifier.final$
        ..type = refer('Database', dianaDataLib)
        ..assignment = refer('Database', dianaDataLib).newInstance([
          refer(names.fields[connectorProvider!.key]!),
          refer('config'),
        ], observerArgs).code));
    }
    for (final provider in graph.ordered) {
      if (provider.needsRequestScope) continue;
      if (provider.scope == 'transient') {
        c.methods.add(providerMethod(provider, onScope: false));
      } else {
        c.fields.add(providerField(provider, onScope: false));
      }
    }
    c.methods.addAll([initializeMethod, disposeMethod]);
  });

  Class? scopeClass;
  if (names.hasRequestScope) {
    scopeClass = Class((c) {
      c
        ..name = 'DianaRequestScope'
        ..fields.add(Field((f) => f
          ..name = '_ctx'
          ..modifier = FieldModifier.final$
          ..type = refer('DianaContext')))
        ..constructors.add(Constructor((ctor) => ctor.requiredParameters.add(
            Parameter((p) => p
              ..name = '_ctx'
              ..toThis = true))));
      for (final provider in graph.ordered) {
        if (!provider.needsRequestScope) continue;
        if (provider.scope == 'transient') {
          c.methods.add(providerMethod(provider, onScope: true));
        } else {
          c.fields.add(providerField(provider, onScope: true));
        }
      }
    });
  }

  return ContextEmission(
    [contextClass, overridesClass, if (scopeClass != null) scopeClass],
    names,
  );
}

/// One `stompBroker.registerMapping(...)` statement for a `@MessageMapping`
/// method — a thin one-liner: decode the payload, call the handler, and
/// (for a `@SendTo` method) encode the reply.
Code _mappingRegistration(
  ResolvedProvider provider,
  MessageMappingInfo mapping,
  ContextNames names,
) {
  final field = names.fields[provider.key]!;
  return Code.scope((allocate) {
    final payload = mapping.payloadKind == 'json'
        ? '${allocate(refer('\$${mapping.payloadType!.name}FromJson', mapping.payloadType!.libraryUri))}'
            '(${allocate(refer('stompJsonMap', dianaLib))}(m.body))'
        : 'm.body';
    final args = mapping.wantsMessage ? '$payload, m' : payload;
    // A void handler is wrapped in an async block that awaits and returns
    // null, so it satisfies `FutureOr<Object?>` and is still awaited in
    // arrival order; a value-returning handler flows straight through.
    final handler = mapping.returnKind == 'void'
        ? '(m) async { await $field.${mapping.methodName}($args); return null; }'
        : '(m) => $field.${mapping.methodName}($args)';
    final buffer = StringBuffer(
        "stompBroker.registerMapping('${mapping.destination}', $handler");
    if (mapping.sendTo != null) {
      buffer.write(", sendTo: '${mapping.sendTo}'");
      if (mapping.returnKind == 'json') {
        final toJson = allocate(refer(
            '\$${mapping.returnType!.name}ToJson', mapping.returnType!.libraryUri));
        final typeCode = allocate(referenceOf(mapping.returnType!));
        buffer.write(', encode: (r) => '
            '${allocate(refer('stompJsonBody', dianaLib))}'
            '($toJson(r as $typeCode))');
      }
    }
    buffer.write(');');
    return buffer.toString();
  });
}
