/// Pure dependency-graph resolution over [LibrarySummary] data.
///
/// No analyzer, no build system: summaries in, resolved plan or a list of
/// human-readable errors out. Every diagnostic here is part of Diana's
/// public developer experience and is covered by exact-message tests.
library;

import '../model/summary.dart';

/// One resolved constructor dependency.
class ResolvedDep {
  final CtorParamInfo param;

  /// Provider key satisfying the dependency; `null` for `@Value` parameters
  /// (resolved from configuration, not the graph) and for the
  /// framework-provided event publisher.
  final String? providerKey;

  /// True when the parameter is Diana's `DianaEventPublisher`, satisfied by
  /// the context's event bus rather than a graph provider.
  final bool isEventPublisher;

  /// True when the parameter is diana_data's `Database`, satisfied by the
  /// context's database facade rather than a graph provider.
  final bool isDbExecutor;

  const ResolvedDep({
    required this.param,
    this.providerKey,
    this.isEventPublisher = false,
    this.isDbExecutor = false,
  });

  bool get isConfigValue => param.valueKey != null;
}

/// A provider with its dependencies resolved.
class ResolvedProvider {
  final InjectableInfo info;
  final String declaredIn;
  final List<ResolvedDep> deps;

  /// True for request-scoped providers, and for transient providers whose
  /// transitive dependencies include a request-scoped provider. Such
  /// providers live on `DianaRequestScope` instead of `DianaContext`.
  bool needsRequestScope;

  ResolvedProvider({
    required this.info,
    required this.declaredIn,
    required this.deps,
    this.needsRequestScope = false,
  });

  String get key => info.providerKey;
  String get scope => info.scope;
}

/// A fully-resolved dependency graph in instantiation order.
class DiGraph {
  /// Every provider, topologically sorted (dependencies first).
  final List<ResolvedProvider> ordered;
  final Map<String, ResolvedProvider> byKey;

  DiGraph({required this.ordered, required this.byKey});

  bool get hasRequestScope => ordered.any((p) => p.needsRequestScope);

  /// Whether the app declares `@EventListener` methods or injects
  /// `DianaEventPublisher` — gates all event-bus emission.
  bool get usesEvents => ordered.any((p) =>
      p.info.eventListeners.isNotEmpty ||
      p.deps.any((d) => d.isEventPublisher));

  /// Whether the app injects `Database` or declares `@Transactional`
  /// methods — gates all diana_data emission (database field, lifecycle,
  /// transactional proxies).
  bool get usesData => ordered.any((p) =>
      p.info.hasTx ||
      p.info.isQueryRepo ||
      p.deps.any((d) => d.isDbExecutor));
}

class DiGraphResult {
  final DiGraph? graph;
  final List<String> errors;

  const DiGraphResult({this.graph, this.errors = const []});
}

/// Resolves the dependency graph across all [summaries].
///
/// All problems are collected and reported together rather than failing on
/// the first one.
DiGraphResult resolveGraph(List<LibrarySummary> summaries) {
  final errors = <String>[];

  final providers = <ResolvedProvider>[];
  final byKey = <String, ResolvedProvider>{};
  for (final summary in summaries) {
    for (final info in summary.injectables) {
      final provider = ResolvedProvider(
        info: info,
        declaredIn: summary.libraryUri,
        deps: [],
      );
      final existing = byKey[provider.key];
      if (existing != null) {
        errors.add(
          'Duplicate provider for ${info.type.displayName}'
          '${info.qualifier != null ? ' (qualifier "${info.qualifier}")' : ''}: '
          'declared in both ${existing.declaredIn} and ${summary.libraryUri}.',
        );
        continue;
      }
      byKey[provider.key] = provider;
      providers.add(provider);
    }
  }

  // Binding index: strong bindings (self type, explicit `as:`) win over
  // auto-binding candidates (implemented supertypes).
  final strong = <String, List<ResolvedProvider>>{};
  final candidates = <String, List<ResolvedProvider>>{};
  String bindKey(TypeRef type, String? qualifier) =>
      '${type.key}|${qualifier ?? ''}';

  for (final provider in providers) {
    final q = provider.info.qualifier;
    (strong[bindKey(provider.info.type, q)] ??= []).add(provider);
    final explicitAs = provider.info.explicitAs;
    if (explicitAs != null) {
      (strong[bindKey(explicitAs, q)] ??= []).add(provider);
    }
    for (final st in provider.info.supertypes) {
      if (st.key == explicitAs?.key) continue;
      (candidates[bindKey(st, q)] ??= []).add(provider);
    }
  }

  for (final entry in strong.entries) {
    if (entry.value.length > 1) {
      errors.add(
        'Multiple providers bound to '
        '${entry.value.first.info.explicitAs?.displayName ?? entry.value.first.info.type.displayName}: '
        '${entry.value.map((p) => '${p.info.type.displayName} (${p.declaredIn})').join(', ')}. '
        'Remove one, or qualify them with `name:` and select with @Named.',
      );
    }
  }

  // Resolve each constructor dependency.
  for (final provider in providers) {
    for (final param in provider.info.ctorParams) {
      if (param.valueKey != null) {
        provider.deps.add(ResolvedDep(param: param));
        continue;
      }
      if (param.type.name == 'DianaEventPublisher' &&
          param.type.libraryUri.startsWith('package:diana/')) {
        provider.deps.add(ResolvedDep(param: param, isEventPublisher: true));
        continue;
      }
      if (param.type.name == 'Database' &&
          param.type.libraryUri.startsWith('package:diana_data/')) {
        provider.deps.add(ResolvedDep(param: param, isDbExecutor: true));
        continue;
      }
      final key = bindKey(param.type, param.qualifier);
      final requiredBy =
          'required by constructor parameter "${param.name}" of '
          '${provider.info.type.displayName} (${provider.declaredIn})';

      final strongHits = strong[key] ?? const [];
      if (strongHits.length == 1) {
        provider.deps.add(
          ResolvedDep(param: param, providerKey: strongHits.single.key),
        );
        continue;
      }
      if (strongHits.length > 1) {
        // Already reported as a duplicate-binding error above.
        continue;
      }
      final candidateHits = candidates[key] ?? const [];
      if (candidateHits.length == 1) {
        provider.deps.add(
          ResolvedDep(param: param, providerKey: candidateHits.single.key),
        );
        continue;
      }
      if (candidateHits.length > 1) {
        errors.add(
          'Multiple providers implement ${param.type.displayName}: '
          '${candidateHits.map((p) => '${p.info.type.displayName} (${p.declaredIn})').join(', ')} '
          '— $requiredBy. Disambiguate with @Named or bind one explicitly '
          'with `as:`.',
        );
        continue;
      }
      errors.add(
        'No provider found for ${param.type.displayName}'
        '${param.qualifier != null ? ' with qualifier "${param.qualifier}"' : ''} '
        '— $requiredBy. Annotate a providing class with @Service/@Component, '
        'or check the type and qualifier.',
      );
    }
  }

  // Topological sort (Kahn). Runs even with resolution errors so cycle
  // diagnostics still appear alongside them.
  final indegree = <String, int>{for (final p in providers) p.key: 0};
  final dependents = <String, List<String>>{};
  for (final provider in providers) {
    for (final dep in provider.deps) {
      final target = dep.providerKey;
      if (target == null) continue;
      indegree[provider.key] = indegree[provider.key]! + 1;
      (dependents[target] ??= []).add(provider.key);
    }
  }
  final queue = [
    for (final p in providers)
      if (indegree[p.key] == 0) p.key,
  ]..sort();
  final ordered = <ResolvedProvider>[];
  while (queue.isNotEmpty) {
    final key = queue.removeAt(0);
    ordered.add(byKey[key]!);
    for (final dependent in dependents[key] ?? const <String>[]) {
      final remaining = indegree[dependent]! - 1;
      indegree[dependent] = remaining;
      if (remaining == 0) queue.add(dependent);
    }
  }
  if (ordered.length != providers.length) {
    final cycle = _findCycle(providers, byKey);
    if (cycle != null) {
      errors.add(
        'Dependency cycle detected: '
        '${cycle.map((p) => p.info.type.displayName).join(' -> ')}. '
        'Break the cycle, e.g. by extracting an interface or inverting one '
        'dependency.',
      );
    }
  }

  // Scope analysis: nothing reachable from a singleton may be
  // request-scoped, and transients inherit "request-ness" from their deps.
  _computeRequestScope(providers, byKey, errors);

  if (errors.isNotEmpty) return DiGraphResult(errors: errors);
  return DiGraphResult(graph: DiGraph(ordered: ordered, byKey: byKey));
}

List<ResolvedProvider>? _findCycle(
  List<ResolvedProvider> providers,
  Map<String, ResolvedProvider> byKey,
) {
  final visiting = <String>{};
  final done = <String>{};
  final stack = <ResolvedProvider>[];

  List<ResolvedProvider>? visit(ResolvedProvider provider) {
    if (done.contains(provider.key)) return null;
    if (visiting.contains(provider.key)) {
      final start = stack.indexWhere((p) => p.key == provider.key);
      return [...stack.sublist(start), provider];
    }
    visiting.add(provider.key);
    stack.add(provider);
    for (final dep in provider.deps) {
      final target = dep.providerKey == null ? null : byKey[dep.providerKey!];
      if (target == null) continue;
      final cycle = visit(target);
      if (cycle != null) return cycle;
    }
    stack.removeLast();
    visiting.remove(provider.key);
    done.add(provider.key);
    return null;
  }

  for (final provider in providers) {
    final cycle = visit(provider);
    if (cycle != null) return cycle;
  }
  return null;
}

void _computeRequestScope(
  List<ResolvedProvider> providers,
  Map<String, ResolvedProvider> byKey,
  List<String> errors,
) {
  // needsRequestScope: request providers, plus transients that (transitively
  // through other transients) depend on one.
  final memo = <String, bool>{};

  bool needsRequest(ResolvedProvider provider, Set<String> path) {
    final cached = memo[provider.key];
    if (cached != null) return cached;
    if (path.contains(provider.key)) return false; // cycle: reported already
    if (provider.scope == 'request') return memo[provider.key] = true;
    if (provider.scope == 'singleton') return memo[provider.key] = false;
    // transient: inherits from dependencies.
    final result = provider.deps.any((d) {
      final target = d.providerKey == null ? null : byKey[d.providerKey!];
      return target != null &&
          needsRequest(target, {...path, provider.key});
    });
    return memo[provider.key] = result;
  }

  for (final provider in providers) {
    provider.needsRequestScope = needsRequest(provider, {});
  }

  for (final provider in providers) {
    if (provider.scope != 'singleton') continue;
    for (final dep in provider.deps) {
      final target = dep.providerKey == null ? null : byKey[dep.providerKey!];
      if (target != null && target.needsRequestScope) {
        errors.add(
          'Singleton ${provider.info.type.displayName} '
          '(${provider.declaredIn}) depends on request-scoped '
          '${target.info.type.displayName}: a singleton outlives every '
          'request. Make ${provider.info.type.displayName} request-scoped, '
          'or make ${target.info.type.displayName} a singleton.',
        );
      }
    }
  }
}
