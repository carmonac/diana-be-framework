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
    final variable = _bindParam(buffer, param, index++, model.consumes);
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
    case ReturnKind.sse:
      buffer.writeln('  final result = $invocation;');
      if (model.sseShape == SseShape.dto) {
        final encode = model.returnJsonGenerated
            ? '\$${model.returnDtoName}ToJson(e)'
            : 'e.toJson()';
        buffer.writeln('  return sseResponse('
            'req, result.map((e) => ServerSentEvent.json($encode)));');
      } else {
        buffer.writeln('  return sseResponse(req, result);');
      }
    case ReturnKind.json:
      buffer.writeln('  final result = $invocation;');
      final String payload;
      final producesArg = model.produces == null
          ? null
          : "const [${model.produces!.map((m) => "'$m'").join(', ')}]";
      if (model.returnJsonGenerated) {
        final encode = '\$${model.returnDtoName}ToJson';
        payload = switch (model.jsonShape) {
          JsonShape.raw => 'result',
          JsonShape.dto => model.nullableResult
              ? 'result == null ? null : $encode(result!)'
              : '$encode(result)',
          JsonShape.dtoList => model.nullableResult
              ? 'result == null ? null : [for (final e in result) $encode(e)]'
              : '[for (final e in result) $encode(e)]',
        };
      } else {
        final q = model.nullableResult ? '?' : '';
        payload = switch (model.jsonShape) {
          JsonShape.raw => 'result',
          JsonShape.dto => 'result$q.toJson()',
          JsonShape.dtoList =>
            model.nullableResult
                ? 'result == null ? null : [for (final e in result) e.toJson()]'
                : '[for (final e in result) e.toJson()]',
        };
      }
      if (producesArg != null) {
        final statusNamed =
            model.status == null ? '' : ', statusCode: ${model.status}';
        buffer.writeln('  return negotiatedResponse(req, $payload, '
            'produces: $producesArg$statusNamed);');
      } else {
        buffer.writeln('  return DianaResponse.json($payload$statusArg);');
      }
  }

  buffer.writeln('}');
  return buffer.toString();
}

String _bindParam(
  StringBuffer buffer,
  AdapterParam param,
  int index,
  List<String>? consumes,
) {
  final variable = '\$a$index';
  final consumesArg = consumes == null
      ? null
      : "const [${consumes.map((m) => "'$m'").join(', ')}]";
  final mapBody = consumesArg == null
      ? 'await decodeJsonMapBody(req)'
      : 'await decodeMapBody(req, consumes: $consumesArg)';
  final listBody = consumesArg == null
      ? 'await decodeJsonListBody(req)'
      : 'await decodeListBody(req, consumes: $consumesArg)';
  switch (param.kind) {
    case BindingKind.rawRequest:
      return 'req';
    case BindingKind.principal:
      // bindPrincipal is exported from package:diana, so the part file
      // resolves it without importing diana_auth.
      return 'bindPrincipal<${param.typeDisplay}>(req)';
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
    case BindingKind.bodyText:
      buffer.writeln('  final $variable = await req.readBodyAsString();');
    case BindingKind.bodyForm:
      buffer.writeln('  final $variable = await decodeFormBody(req);');
    case BindingKind.bodyMap:
      buffer.writeln('  final $variable = $mapBody;');
    case BindingKind.bodyList:
      buffer.writeln(
          '  final $variable = ($listBody)'
          '.cast<${param.typeDisplay}>();');
    case BindingKind.bodyDto:
      final decode = param.jsonGenerated
          ? '\$${param.dtoName}FromJson($variable\$json)'
          : '${param.dtoName}.fromJson($variable\$json)';
      buffer
        ..writeln('  final $variable\$json = $mapBody;')
        ..writeln('  final $variable = decodeDto(() => $decode);');
      if (param.validate) {
        buffer.writeln('  const \$${param.dtoName}Validator()'
            '.validate($variable).throwIfInvalid();');
      }
    case BindingKind.bodyDtoList:
      final decodeElement = param.jsonGenerated
          ? '\$${param.dtoName}FromJson((e as Map).cast<String, dynamic>())'
          : '${param.dtoName}.fromJson((e as Map).cast<String, dynamic>())';
      buffer
        ..writeln('  final $variable\$json = $listBody;')
        ..writeln('  final $variable = decodeDto(() => [')
        ..writeln('    for (final e in $variable\$json) $decodeElement,')
        ..writeln('  ]);');
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
