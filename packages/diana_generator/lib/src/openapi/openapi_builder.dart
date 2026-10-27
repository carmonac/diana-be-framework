/// Pure OpenAPI 3.0 document generation from [LibrarySummary] data.
///
/// No build system, no analyzer: summaries in, a JSON-encodable map out.
/// All keys are emitted in sorted order for deterministic output.
library;

import '../common.dart';
import '../model/summary.dart';

/// Builds an OpenAPI 3.0 document for the application described by
/// [summaries]. `info.title`/`info.version` are placeholders patched at
/// runtime from configuration (`patchOpenApiInfo`).
Map<String, Object?> buildOpenApiDocument(List<LibrarySummary> summaries) {
  final dtoByName = <String, DtoInfo>{};
  for (final summary in summaries) {
    for (final dto in summary.dtos) {
      dtoByName[dto.type.name] = dto;
    }
  }

  final paths = <String, Map<String, Object?>>{};
  final controllers = [for (final s in summaries) ...s.controllers]
    ..sort((a, b) => a.type.key.compareTo(b.type.key));
  var anySecured = false;
  for (final controller in controllers) {
    for (final route in controller.routes) {
      final api = route.api;
      if (api == null) continue;
      final path = _openApiPath(joinPaths(controller.basePath, route.path));
      // Method-level replaces controller-level (same rule as the guards).
      final secured = (route.security ?? controller.security) != null;
      anySecured = anySecured || secured;
      final operation =
          _operation(controller, route, api, dtoByName, secured: secured);
      (paths[path] ??= {})[route.httpMethod.toLowerCase()] = operation;
    }
  }

  final schemas = <String, Object?>{
    for (final name in dtoByName.keys.toList()..sort())
      name: _schemaOf(dtoByName[name]!, dtoByName),
  };

  return {
    'openapi': '3.0.3',
    'info': {'title': 'Diana application', 'version': '0.0.0'},
    'paths': {
      for (final path in paths.keys.toList()..sort()) path: paths[path],
    },
    if (schemas.isNotEmpty || anySecured)
      'components': {
        if (schemas.isNotEmpty) 'schemas': schemas,
        // Runtime accepts several schemes; one generic bearer scheme is the
        // honest static answer (documented limitation).
        if (anySecured)
          'securitySchemes': {
            'bearerAuth': {'type': 'http', 'scheme': 'bearer'},
          },
      },
  };
}

/// `/todos/:id` → `/todos/{id}`.
String _openApiPath(String dianaPath) => dianaPath
    .split('/')
    .map((seg) => seg.startsWith(':') ? '{${seg.substring(1)}}' : seg)
    .join('/');

Map<String, Object?> _operation(
  ControllerInfo controller,
  RouteInfo route,
  RouteApi api,
  Map<String, DtoInfo> dtos, {
  required bool secured,
}) {
  final parameters = [
    for (final param in api.params)
      {
        'name': param.name,
        'in': param.kind,
        'required': param.kind == 'path' ? true : param.required,
        'schema': {
          ..._typeSchema(param.type, dtos),
          if (param.defaultValue != null) 'default': param.defaultValue,
        },
      },
  ];

  Map<String, Object?>? requestBody;
  if (api.bodyShape != null) {
    final consumesMimes = api.consumes ?? const ['application/json'];
    final bodySchema = switch (api.bodyShape) {
      'dto' => _refOrInline(api.bodyType, dtos),
      'dtoList' => {
          'type': 'array',
          'items': _refOrInline(api.bodyType, dtos),
        },
      _ => <String, Object?>{},
    };
    final content = switch (api.bodyShape) {
      'dto' || 'dtoList' || 'map' || 'list' => {
          for (final mime in consumesMimes) mime: {'schema': bodySchema},
        },
      'text' => {
          'text/plain': {
            'schema': {'type': 'string'},
          },
        },
      'form' => {
          'multipart/form-data': {'schema': <String, Object?>{}},
        },
      _ => <String, Object?>{},
    };
    requestBody = {'required': true, 'content': content};
  }

  final status = api.status ?? (api.returnShape == 'void' ? 204 : 200);
  final producesMimes = api.produces ?? const ['application/json'];
  final returnSchema = switch (api.returnShape) {
    'dto' => _refOrInline(api.returnType, dtos),
    'dtoList' => {
        'type': 'array',
        'items': _refOrInline(api.returnType, dtos),
      },
    _ => <String, Object?>{},
  };
  final responseContent = switch (api.returnShape) {
    'dto' || 'dtoList' || 'raw' => {
        for (final mime in producesMimes) mime: {'schema': returnSchema},
      },
    'text' => {
        'text/plain': {
          'schema': {'type': 'string'},
        },
      },
    _ => null, // void / response: unspecified content
  };

  return {
    'operationId': '${controller.type.name}_${route.methodName}',
    'tags': [controller.type.name],
    if (secured)
      'security': [
        {'bearerAuth': <Object?>[]},
      ],
    if (parameters.isNotEmpty) 'parameters': parameters,
    if (requestBody != null) 'requestBody': requestBody,
    'responses': {
      '$status': {
        'description': '',
        if (responseContent != null) 'content': responseContent,
      },
    },
  };
}

Map<String, Object?> _refOrInline(TypeRef? type, Map<String, DtoInfo> dtos) {
  if (type == null) return {};
  if (dtos.containsKey(type.name)) {
    return {r'$ref': '#/components/schemas/${type.name}'};
  }
  return _typeSchema(type, dtos);
}

Map<String, Object?> _typeSchema(TypeRef type, Map<String, DtoInfo> dtos) {
  switch (type.name) {
    case 'String':
      return {'type': 'string'};
    case 'int':
      return {'type': 'integer'};
    case 'double':
    case 'num':
      return {'type': 'number'};
    case 'bool':
      return {'type': 'boolean'};
    case 'DateTime':
      return {'type': 'string', 'format': 'date-time'};
    case 'List':
      return {
        'type': 'array',
        'items': type.typeArgs.isEmpty
            ? <String, Object?>{}
            : _refOrInline(type.typeArgs.single, dtos),
      };
    case 'Map':
      return {'type': 'object'};
  }
  if (dtos.containsKey(type.name)) return _refOrInline(type, dtos);
  return {}; // Unknown type: unconstrained schema (documented best effort).
}

Map<String, Object?> _schemaOf(DtoInfo dto, Map<String, DtoInfo> dtos) {
  final properties = <String, Object?>{};
  final required = <String>[];
  for (final field in dto.fields) {
    final schema = <String, Object?>{
      ..._typeSchema(field.type, dtos),
      if (field.enumValues != null) 'enum': field.enumValues,
    };
    final c = field.constraints;
    if (c['minLength'] != null) schema['minLength'] = c['minLength'];
    if (c['maxLength'] != null) schema['maxLength'] = c['maxLength'];
    if (c['min'] != null) schema['minimum'] = c['min'];
    if (c['max'] != null) schema['maximum'] = c['max'];
    if (c['pattern'] != null) schema['pattern'] = c['pattern'];
    if (c['email'] == true) schema['format'] = 'email';
    if (c['notBlank'] == true || c['notEmpty'] == true) {
      schema['minLength'] ??= 1;
    }
    properties[field.jsonName] = schema;
    if (!field.nullable) required.add(field.jsonName);
  }
  return {
    'type': 'object',
    'properties': {
      for (final key in properties.keys.toList()..sort()) key: properties[key],
    },
    if (required.isNotEmpty) 'required': required..sort(),
  };
}
