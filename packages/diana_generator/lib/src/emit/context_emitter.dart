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

Reference get dianaConfigRef => refer('DianaConfig', dianaLib);

/// Converts a summary [TypeRef] into a code_builder reference (imports are
/// handled by the emitter's allocator).
Reference referenceOf(TypeRef type) => TypeReference((b) {
      b
        ..symbol = type.name
        ..url = type.libraryUri
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

  /// Providers that live on `DianaRequestScope` instead of `DianaContext`.
  final Set<String> onRequestScope = {};

  bool hasRequestScope = false;

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
  final used = <String>{'config'};

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
    } else {
      names.fields[provider.key] = allocate(base);
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

    if (provider.info.kind == ProviderKind.configProps) {
      return refer(
        '\$${provider.info.type.name}FromConfig',
        provider.info.type.libraryUri,
      ).call([configExpr()]);
    }
    final positional = <Expression>[];
    final named = <String, Expression>{};
    for (final dep in provider.deps) {
      if (dep.param.isNamed) {
        named[dep.param.name] = depExpr(dep);
      } else {
        positional.add(depExpr(dep));
      }
    }
    return referenceOf(provider.info.type).newInstance(positional, named);
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

  final contextClass = Class((c) {
    c
      ..name = 'DianaContext'
      ..fields.add(Field((f) => f
        ..name = 'config'
        ..modifier = FieldModifier.final$
        ..type = dianaConfigRef))
      ..constructors.add(Constructor((ctor) => ctor.requiredParameters.add(
          Parameter((p) => p
            ..name = 'config'
            ..toThis = true))));
    for (final provider in graph.ordered) {
      if (provider.needsRequestScope) continue;
      if (provider.scope == 'transient') {
        c.methods.add(providerMethod(provider, onScope: false));
      } else {
        c.fields.add(providerField(provider, onScope: false));
      }
    }
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
    [contextClass, if (scopeClass != null) scopeClass],
    names,
  );
}
