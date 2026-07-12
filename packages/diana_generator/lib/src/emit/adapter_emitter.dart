/// Emits route adapter functions into the controller's part file.
///
/// Adapters are public (`$diana$Controller$method`) so the standalone
/// bootstrap library can reference them across libraries. They live in a
/// part file, so user types resolve exactly as written in the host library.
library;

import '../model/adapter_model.dart';

String emitAdapter(AdapterModel model) {
  final buffer = StringBuffer()
    ..writeln('Future<DianaResponse> ${model.adapterName}(')
    ..writeln('    ${model.className} c, DianaRequest req) async {');

  final positional = <String>[];
  final named = <String, String>{};
  var index = 0;
  for (final param in model.params) {
    final variable = _bindParam(buffer, param, index++);
    if (param.isNamed) {
      named[param.paramName] = variable;
    } else {
      positional.add(variable);
    }
  }

  final args = [
    ...positional,
    for (final e in named.entries) '${e.key}: ${e.value}',
  ].join(', ');
  final invocation =
      '${model.awaited ? 'await ' : ''}c.${model.methodName}($args)';
  final statusArg =
      model.status == null ? '' : ', statusCode: ${model.status}';

  switch (model.returnKind) {
    case ReturnKind.response:
      buffer.writeln('  return $invocation;');
    case ReturnKind.voidLike:
      buffer
        ..writeln('  $invocation;')
        ..writeln(model.status == null
            ? '  return const DianaResponse.noContent();'
            : '  return const DianaResponse(statusCode: ${model.status});');
    case ReturnKind.text:
      buffer
        ..writeln('  final result = $invocation;')
        ..writeln('  return DianaResponse.text(result$statusArg);');
    case ReturnKind.json:
      buffer.writeln('  final result = $invocation;');
      final q = model.nullableResult ? '?' : '';
      final payload = switch (model.jsonShape) {
        JsonShape.raw => 'result',
        JsonShape.dto => 'result$q.toJson()',
        JsonShape.dtoList =>
          model.nullableResult
              ? 'result == null ? null : [for (final e in result) e.toJson()]'
              : '[for (final e in result) e.toJson()]',
      };
      buffer.writeln('  return DianaResponse.json($payload$statusArg);');
  }

  buffer.writeln('}');
  return buffer.toString();
}

String _bindParam(StringBuffer buffer, AdapterParam param, int index) {
  final variable = '\$a$index';
  switch (param.kind) {
    case BindingKind.rawRequest:
      return 'req';
    case BindingKind.path:
      buffer.writeln(
          '  final $variable = bindPathParam<${param.typeDisplay}>(req, '
          "'${param.httpName}');");
    case BindingKind.query:
      final defaultArg = param.defaultValue == null
          ? ''
          : ", defaultValue: '${param.defaultValue}'";
      buffer.writeln(
          '  final $variable = bindQueryParam<${param.typeDisplay}>(req, '
          "'${param.httpName}'$defaultArg);");
    case BindingKind.header:
      buffer.writeln(
          '  final $variable = bindHeader<${param.typeDisplay}>(req, '
          "'${param.httpName}');");
    case BindingKind.bodyMap:
      buffer.writeln('  final $variable = await decodeJsonMapBody(req);');
    case BindingKind.bodyList:
      buffer.writeln(
          '  final $variable = (await decodeJsonListBody(req))'
          '.cast<${param.typeDisplay}>();');
    case BindingKind.bodyDto:
      buffer.writeln('  final $variable = ${param.dtoName}.fromJson('
          'await decodeJsonMapBody(req));');
      if (param.validate) {
        buffer.writeln('  const \$${param.dtoName}Validator()'
            '.validate($variable).throwIfInvalid();');
      }
    case BindingKind.bodyDtoList:
      buffer
        ..writeln('  final $variable = [')
        ..writeln('    for (final e in await decodeJsonListBody(req))')
        ..writeln('      ${param.dtoName}.fromJson('
            '(e as Map).cast<String, dynamic>()),')
        ..writeln('  ];');
      if (param.validate) {
        buffer.writeln('  for (final e in $variable) {');
        buffer.writeln(
            '    const \$${param.dtoName}Validator().validate(e)'
            '.throwIfInvalid();');
        buffer.writeln('  }');
      }
  }
  return variable;
}
