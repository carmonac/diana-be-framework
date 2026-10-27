import 'package:diana_generator/src/graph/di_graph.dart';
import 'package:diana_generator/src/model/summary.dart';
import 'package:test/test.dart';

TypeRef t(String name, {String lib = 'package:app/app.dart'}) =>
    TypeRef(libraryUri: lib, name: name);

CtorParamInfo dep(String name, TypeRef type,
        {String? qualifier, String? valueKey}) =>
    CtorParamInfo(
      name: name,
      isNamed: false,
      type: type,
      qualifier: qualifier,
      valueKey: valueKey,
    );

InjectableInfo inj(
  String name, {
  String scope = 'singleton',
  String? qualifier,
  TypeRef? explicitAs,
  List<TypeRef> supertypes = const [],
  List<CtorParamInfo> params = const [],
}) =>
    InjectableInfo(
      type: t(name),
      scope: scope,
      qualifier: qualifier,
      explicitAs: explicitAs,
      supertypes: supertypes,
      ctorParams: params,
    );

LibrarySummary lib(List<InjectableInfo> injectables) => LibrarySummary(
      libraryUri: 'package:app/app.dart',
      injectables: injectables,
    );

void main() {
  test('resolves a linear chain in topological order', () {
    final result = resolveGraph([
      lib([
        inj('Controller', params: [dep('service', t('Service'))]),
        inj('Service', params: [dep('repo', t('Repo'))]),
        inj('Repo'),
      ]),
    ]);
    expect(result.errors, isEmpty);
    final order = result.graph!.ordered.map((p) => p.info.type.name).toList();
    expect(order, ['Repo', 'Service', 'Controller']);
  });

  test('auto-binds an interface with exactly one implementation', () {
    final result = resolveGraph([
      lib([
        inj('InMemoryRepo', supertypes: [t('Repo')]),
        inj('Service', params: [dep('repo', t('Repo'))]),
      ]),
    ]);
    expect(result.errors, isEmpty);
    final service = result.graph!.byKey.values
        .firstWhere((p) => p.info.type.name == 'Service');
    expect(service.deps.single.providerKey, contains('InMemoryRepo'));
  });

  test('explicit `as:` binding wins over a competing candidate', () {
    final result = resolveGraph([
      lib([
        inj('PostgresRepo', supertypes: [t('Repo')], explicitAs: t('Repo')),
        inj('InMemoryRepo', supertypes: [t('Repo')]),
        inj('Service', params: [dep('repo', t('Repo'))]),
      ]),
    ]);
    expect(result.errors, isEmpty);
    final service = result.graph!.byKey.values
        .firstWhere((p) => p.info.type.name == 'Service');
    expect(service.deps.single.providerKey, contains('PostgresRepo'));
  });

  test('reports ambiguous implementations with both locations', () {
    final result = resolveGraph([
      lib([
        inj('PostgresRepo', supertypes: [t('Repo')]),
        inj('InMemoryRepo', supertypes: [t('Repo')]),
        inj('Service', params: [dep('repo', t('Repo'))]),
      ]),
    ]);
    expect(result.graph, isNull);
    expect(
      result.errors.single,
      'Multiple providers implement Repo: '
      'PostgresRepo (package:app/app.dart), '
      'InMemoryRepo (package:app/app.dart) '
      '— required by constructor parameter "repo" of Service '
      '(package:app/app.dart). Disambiguate with @Named or bind one '
      'explicitly with `as:`.',
    );
  });

  test('reports missing providers with the requiring location', () {
    final result = resolveGraph([
      lib([
        inj('Service', params: [dep('clock', t('Clock'))]),
      ]),
    ]);
    expect(
      result.errors.single,
      'No provider found for Clock '
      '— required by constructor parameter "clock" of Service '
      '(package:app/app.dart). Annotate a providing class with '
      '@Service/@Component, or check the type and qualifier.',
    );
  });

  test('reports dependency cycles with the full path', () {
    final result = resolveGraph([
      lib([
        inj('A', params: [dep('b', t('B'))]),
        inj('B', params: [dep('a', t('A'))]),
      ]),
    ]);
    expect(
      result.errors.single,
      'Dependency cycle detected: A -> B -> A. Break the cycle, e.g. by '
      'extracting an interface or inverting one dependency.',
    );
  });

  test('qualified providers are only visible through @Named', () {
    final result = resolveGraph([
      lib([
        inj('SmtpSender', qualifier: 'smtp', supertypes: [t('Sender')]),
        inj('Notifier',
            params: [dep('sender', t('Sender'), qualifier: 'smtp')]),
      ]),
    ]);
    expect(result.errors, isEmpty);

    final unqualified = resolveGraph([
      lib([
        inj('SmtpSender', qualifier: 'smtp', supertypes: [t('Sender')]),
        inj('Notifier', params: [dep('sender', t('Sender'))]),
      ]),
    ]);
    expect(unqualified.errors.single, startsWith('No provider found'));
  });

  test('reports duplicate providers for the same type', () {
    final result = resolveGraph([
      LibrarySummary(libraryUri: 'package:app/a.dart', injectables: [
        InjectableInfo(
            type: t('Repo', lib: 'package:app/x.dart'), scope: 'singleton'),
      ]),
      LibrarySummary(libraryUri: 'package:app/b.dart', injectables: [
        InjectableInfo(
            type: t('Repo', lib: 'package:app/x.dart'), scope: 'singleton'),
      ]),
    ]);
    expect(
      result.errors.single,
      'Duplicate provider for Repo: declared in both package:app/a.dart '
      'and package:app/b.dart.',
    );
  });

  test('rejects singleton depending on request-scoped provider', () {
    final result = resolveGraph([
      lib([
        inj('Session', scope: 'request'),
        inj('Cache', params: [dep('session', t('Session'))]),
      ]),
    ]);
    expect(
      result.errors.single,
      'Singleton Cache (package:app/app.dart) depends on request-scoped '
      'Session: a singleton outlives every request. Make Cache '
      'request-scoped, or make Session a singleton.',
    );
  });

  test('transients inherit request-ness through the chain', () {
    final result = resolveGraph([
      lib([
        inj('Session', scope: 'request'),
        inj('Helper', scope: 'transient', params: [
          dep('session', t('Session')),
        ]),
        inj('Handler', scope: 'request', params: [dep('h', t('Helper'))]),
      ]),
    ]);
    expect(result.errors, isEmpty);
    final helper = result.graph!.byKey.values
        .firstWhere((p) => p.info.type.name == 'Helper');
    expect(helper.needsRequestScope, isTrue);
    expect(result.graph!.hasRequestScope, isTrue);
  });

  test('@Value parameters are config deps, not graph deps', () {
    final result = resolveGraph([
      lib([
        inj('Greeter', params: [
          dep('greeting', t('String', lib: 'dart:core'),
              valueKey: 'app.greeting'),
        ]),
      ]),
    ]);
    expect(result.errors, isEmpty);
    final greeter = result.graph!.ordered.single;
    expect(greeter.deps.single.isConfigValue, isTrue);
    expect(greeter.deps.single.providerKey, isNull);
  });
}
