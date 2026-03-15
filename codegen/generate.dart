#!/usr/bin/env dart
// codegen/generate.dart
//
// Dart code generator for lzt-api.
// Reads an OpenAPI 3.x JSON schema and emits a Dart client class.
//
// Usage:
//   dart run codegen/generate.dart \
//     --schema schemas/forum.json \
//     --output lib/src/forum/forum_client.dart \
//     --class-name ForumClient \
//     --base-url https://api.lzt.market

import 'dart:convert';
import 'dart:io';

// ─── Simple CLI arg parser ────────────────────────────────────────────────────

Map<String, String> parseArgs(List<String> args) {
  final result = <String, String>{};
  for (var i = 0; i < args.length - 1; i++) {
    if (args[i].startsWith('--')) {
      result[args[i].substring(2)] = args[i + 1];
    }
  }
  return result;
}

// ─── OpenAPI helpers ──────────────────────────────────────────────────────────

String operationIdToMethodName(String operationId) {
  // Split on dots, underscores, hyphens, spaces — all are separators.
  // e.g. "autopayments.create" → "autopaymentsCreate"
  //      "proxy.get"           → "proxyGet"
  //      "threads_list"        → "threadsList"
  //      "item_confirm-buy"    → "itemConfirmBuy"
  final parts = operationId.split(RegExp(r'[._\-\s]+'));
  if (parts.isEmpty) return operationId;
  return parts.first.toLowerCase() +
      parts.skip(1).map((p) {
        if (p.isEmpty) return '';
        return p[0].toUpperCase() + p.substring(1).toLowerCase();
      }).join();
}


// Resolve a $ref string like "#/components/schemas/CurrencyModel"
// against the root schema. Returns the referenced schema map or null.
Map<String, dynamic>? resolveRef(String ref, Map<String, dynamic> rootSchema) {
  // Only handle local $refs (#/...)
  if (!ref.startsWith('#/')) return null;
  final parts = ref.substring(2).split('/');
  dynamic node = rootSchema;
  for (final part in parts) {
    if (node is Map) {
      node = node[part];
    } else {
      return null;
    }
  }
  if (node is Map) {
    // Cast safely regardless of exact generic type
    return Map<String, dynamic>.from(node as Map);
  }
  return null;
}

// Heuristic: derive a Dart primitive type from a $ref name when resolution fails.
// e.g. "UserIDModel" → int, "CurrencyModel" → String, "ExtraModel" → Map<String,dynamic>
String _refNameToFallbackType(String ref, {bool nullable = false}) {
  final name = ref.split('/').last.toLowerCase();
  String dartType;
  if (name.contains('id')) {
    dartType = 'int';
  } else if (name.contains('currency') || name.contains('code') || name.contains('string')) {
    dartType = 'String';
  } else if (name.contains('flag') || name.contains('bool') || name.contains('enable')) {
    dartType = 'bool';
  } else if (name.contains('count') || name.contains('num') || name.contains('amount')) {
    dartType = 'int';
  } else {
    // Unknown model — use dynamic, safe for any shape
    dartType = 'dynamic';
  }
  return nullable ? '$dartType?' : dartType;
}

String openApiTypeToDart(dynamic schema, {bool nullable = false, Map<String, dynamic>? rootSchema}) {
  if (schema == null) return 'dynamic';
  if (schema is! Map) return 'dynamic';

  // $ref — resolve to primitive if possible, never emit unknown class names
  final ref = schema['\$ref'];
  if (ref is String) {
    if (rootSchema != null) {
      final resolved = resolveRef(ref, rootSchema);
      if (resolved != null) {
        return openApiTypeToDart(resolved, nullable: nullable, rootSchema: rootSchema);
      }
    }
    // Can't resolve — use heuristic based on ref name
    return _refNameToFallbackType(ref, nullable: nullable);
  }

  // oneOf / anyOf / allOf — try first branch, otherwise dynamic
  for (final key in ['oneOf', 'anyOf', 'allOf']) {
    final list = schema[key];
    if (list is List && list.isNotEmpty) {
      // Try to find a non-null branch
      for (final branch in list) {
        final t = openApiTypeToDart(branch, nullable: nullable, rootSchema: rootSchema);
        if (t != 'dynamic') return t;
      }
      return 'dynamic';
    }
  }

  // `type` can be String OR List e.g. ["string", "null"]
  final rawType = schema['type'];
  String? type;
  bool isNullable = nullable;

  if (rawType is String) {
    type = rawType;
  } else if (rawType is List) {
    final nonNull = rawType.whereType<String>().where((t) => t != 'null').toList();
    type = nonNull.isNotEmpty ? nonNull.first : null;
    if (rawType.contains('null')) isNullable = true;
  }

  // enum with string values → String
  final enumValues = schema['enum'];
  if (enumValues is List && type == null) {
    type = 'string';
  }

  final format = schema['format'];

  String dartType;
  switch (type) {
    case 'integer':
      dartType = 'int';
    case 'number':
      dartType = (format == 'float' || format == 'double') ? 'double' : 'num';
    case 'boolean':
      dartType = 'bool';
    case 'array':
      dartType = 'List<${openApiTypeToDart(schema['items'], rootSchema: rootSchema)}>';
    case 'object':
      dartType = 'Map<String, dynamic>';
    case 'string':
      dartType = 'String';
    default:
      dartType = 'dynamic';
  }

  return isNullable ? '$dartType?' : dartType;
}


// ─── Parameter model ──────────────────────────────────────────────────────────

class Param {
  final String name;
  final String dartName;
  final String dartType;
  final bool required;
  final String location; // 'path', 'query', 'header'
  final String? description;

  Param({
    required this.name,
    required this.dartName,
    required this.dartType,
    required this.required,
    required this.location,
    this.description,
  });
}

String toSnakeCamel(String name) {
  // Strip chars invalid in Dart identifiers (e.g. "[]" from "email_provider[]")
  var clean = name.replaceAll(RegExp(r'[^\w\s\-]'), '');

  // If no separators exist AND name already has uppercase letters (camelCase), keep it as-is.
  if (!clean.contains(RegExp(r'[_\-\s]')) && clean.contains(RegExp(r'[A-Z]'))) {
    clean = clean[0].toLowerCase() + clean.substring(1);
    // Prefix digit-starting identifiers with 'p' (e.g. "2fa" → "p2fa")
    if (clean.isNotEmpty && RegExp(r'\d').hasMatch(clean[0])) clean = 'p$clean';
    return clean;
  }

  final parts = clean.split(RegExp(r'[_\-\s]+'));
  final nonEmpty = parts.where((p) => p.isNotEmpty).toList();
  if (nonEmpty.isEmpty) return 'param';
  var result = nonEmpty.first.toLowerCase() +
      nonEmpty.skip(1).map((p) => p.isEmpty ? '' : p[0].toUpperCase() + p.substring(1)).join();
  // Prefix digit-starting identifiers
  if (result.isNotEmpty && RegExp(r'\d').hasMatch(result[0])) result = 'p$result';
  return result;
}

// ─── Reserved identifier guard ───────────────────────────────────────────────

// Names that conflict with BaseClient HTTP methods or Dart built-ins.
// Any param with one of these names gets a trailing underscore.
const _reservedNames = {
  // BaseClient HTTP methods
  'get', 'post', 'put', 'patch', 'delete',
  // Dart keywords and common built-ins
  'in', 'is', 'as', 'do', 'if', 'for', 'new', 'var', 'try',
  'null', 'true', 'false', 'void', 'this', 'super', 'class',
  'return', 'import', 'switch', 'default', 'extends', 'abstract',
  // Common param names that shadow built-ins
  'close', 'call', 'toString', 'hashCode', 'runtimeType',
};

String safeDartName(String name) {
  return _reservedNames.contains(name) ? '${name}_' : name;
}

// ─── Code generation ──────────────────────────────────────────────────────────

// Shared param parser used for both inline and $ref-resolved params.
Param? _parseParam(Map<String, dynamic> pMap, Map<String, dynamic> rootSchema) {
  final name = pMap['name'] as String?;
  final location = pMap['in'] as String?;
  if (name == null || location == null) return null;
  final pSchema = pMap['schema'] ?? {};
  final isRequired = pMap['required'] == true || location == 'path';
  return Param(
    name: name,
    dartName: safeDartName(toSnakeCamel(name)),
    dartType: openApiTypeToDart(pSchema, nullable: !isRequired, rootSchema: rootSchema),
    required: isRequired,
    location: location,
    description: pMap['description']?.toString(),
  );
}

String generateClient({
  required String className,
  required String baseUrl,
  required String schemaPath,
  required Map<String, dynamic> schema,
}) {
  final paths = schema['paths'] as Map<String, dynamic>? ?? {};
  final methods = <String>[];
  final usedNames = <String>{};

  for (final entry in paths.entries) {
    final path = entry.key;
    if (entry.value is! Map<String, dynamic>) continue;
    final pathItem = entry.value as Map<String, dynamic>;

    for (final httpMethod in ['get', 'post', 'put', 'delete', 'patch']) {
      final operation = pathItem[httpMethod] as Map<String, dynamic>?;
      if (operation == null) continue;

      final operationId = operation['operationId'] as String?;
      if (operationId == null) continue;

      // Deduplicate method names — if two operationIds map to the same camelCase,
      // suffix with the HTTP method (e.g. "proxyGet2" → "proxyGetDelete")
      var methodName = operationIdToMethodName(operationId);
      if (usedNames.contains(methodName)) {
        methodName = methodName + httpMethod[0].toUpperCase() + httpMethod.substring(1);
      }
      usedNames.add(methodName);
      final summary = operation['summary'] as String?;
      final description = operation['description'] as String?;

      // Collect parameters
      final rawParams = <dynamic>[
        ...((pathItem['parameters'] as List?)?.cast<dynamic>() ?? []),
        ...((operation['parameters'] as List?)?.cast<dynamic>() ?? []),
      ];

      final params = rawParams
          .map<Param?>((p) {
            if (p is! Map<String, dynamic>) return null;
            final pMap = p;

            // $ref-only param — resolve it from components/parameters
            if (pMap.containsKey('\$ref') && !pMap.containsKey('name')) {
              final refStr = pMap['\$ref'] as String?;
              if (refStr == null) return null;
              final resolved = resolveRef(refStr, schema);
              if (resolved == null) return null;
              return _parseParam(resolved, schema);
            }

            return _parseParam(pMap, schema);
          })
          .whereType<Param>()
          .toList();

      // ── Ensure all path template vars have a corresponding param ──────────
      // Some schemas omit path params from the parameters list entirely.
      // Extract them from the path template and inject int params if missing.
      // Also fix existing path params that got a wrong type from $ref resolution.
      String _pathParamType(String varName) {
        final lower = varName.toLowerCase();
        // Anything ending in "id" or named like "userId", "forumId" → int
        if (lower.endsWith('id') || lower.contains('_id')) return 'int';
        return 'int'; // path params are almost always IDs — default to int
      }

      final pathVarRe = RegExp(r'\{(\w+)\}');
      for (final match in pathVarRe.allMatches(path)) {
        final varName = match.group(1)!;
        final dartName = toSnakeCamel(varName);
        final safeName = safeDartName(dartName);
        final existingIdx = params.indexWhere((p) => p.name == varName || p.dartName == safeName || p.dartName == dartName);
        if (existingIdx == -1) {
          // Missing entirely — inject
          params.add(Param(
            name: varName,
            dartName: safeDartName(dartName),
            dartType: _pathParamType(varName),
            required: true,
            location: 'path',
          ));
        } else {
          // Already declared — check if type makes sense for a path param
          final existing = params[existingIdx];
          final badPathType = existing.dartType == 'bool' ||
              existing.dartType == 'bool?' ||
              existing.dartType == 'dynamic' ||
              existing.dartType.startsWith('Map') ||
              existing.dartType.startsWith('List');
          if (badPathType) {
            params[existingIdx] = Param(
              name: existing.name,
              dartName: existing.dartName,
              dartType: _pathParamType(existing.name),
              required: true,
              location: 'path',
              description: existing.description,
            );
          }
        }
      }

      // ── Extract typed body params from requestBody schema ────────────────
      final bodyParams = <Param>[];
      bool isMultipart = false;
      final isBodyMethod = ['post', 'put', 'patch'].contains(httpMethod);
      if (isBodyMethod && operation.containsKey('requestBody')) {
        final rb = operation['requestBody'];
        if (rb is Map) {
          final content = rb['content'];
          Map? schemaMap;
          if (content is Map) {
            // Prefer application/json; fall back to multipart/form-data or first entry
            Map? selectedContent;
            if (content.containsKey('application/json')) {
              selectedContent = content['application/json'] as Map?;
            } else if (content.containsKey('multipart/form-data')) {
              selectedContent = content['multipart/form-data'] as Map?;
              isMultipart = true;
            } else {
              final first = content.values.firstOrNull;
              if (first is Map) selectedContent = first;
              // Check if any key indicates multipart
              if (content.keys.any((k) => k.toString().contains('multipart'))) {
                isMultipart = true;
              }
            }
            if (selectedContent is Map) {
              schemaMap = selectedContent['schema'] as Map?;
            }
          }
          if (schemaMap != null) {
            final props = schemaMap['properties'];
            final required = schemaMap['required'];
            final requiredSet = <String>{};
            if (required is List) requiredSet.addAll(required.whereType<String>());

            if (props is Map) {
              for (final propEntry in props.entries) {
                final propName = propEntry.key as String;
                final propSchema = propEntry.value;
                final isReq = requiredSet.contains(propName);
                // binary format fields → Uint8List for file uploads
                String bodyDartType;
                if (propSchema is Map &&
                    propSchema['type'] == 'string' &&
                    propSchema['format'] == 'binary') {
                  bodyDartType = isReq ? 'List<int>' : 'List<int>?';
                } else {
                  bodyDartType = openApiTypeToDart(propSchema, nullable: !isReq, rootSchema: schema);
                }
                bodyParams.add(Param(
                  name: propName,
                  dartName: safeDartName(toSnakeCamel(propName)),
                  dartType: bodyDartType,
                  required: isReq,
                  location: isMultipart ? 'multipart' : 'body',
                  description: propSchema is Map ? propSchema['description']?.toString() : null,
                ));
              }
            }
          }
        }
      }
      final hasBody = isBodyMethod && operation.containsKey('requestBody');
      // If schema had no parseable properties, fall back to raw Map
      final useRawBody = hasBody && bodyParams.isEmpty;

      // ── Build method signature ─────────────────────────────────────────────
      final allParams = [...params];
      final requiredPathQuery = allParams.where((p) => p.required).toList();
      final optionalPathQuery = allParams.where((p) => !p.required).toList();
      final requiredBody = bodyParams.where((p) => p.required).toList();
      final optionalBody = bodyParams.where((p) => !p.required).toList();

      final sigParts = <String>[];
      for (final p in requiredPathQuery) {
        sigParts.add('required ${p.dartType} ${p.dartName}');
      }
      for (final p in requiredBody) {
        sigParts.add('required ${p.dartType} ${p.dartName}');
      }
      for (final p in optionalPathQuery) {
        sigParts.add('${p.dartType} ${p.dartName}');
      }
      for (final p in optionalBody) {
        sigParts.add('${p.dartType} ${p.dartName}');
      }
      if (useRawBody) sigParts.add('Map<String, dynamic>? body');

      final namedParams = sigParts.isNotEmpty ? '{\n    ${sigParts.join(',\n    ')},\n  }' : '';

      // ── Build path with substitutions ─────────────────────────────────────
      // Find the declared type for each path variable to decide if we need .toString()
      var dartPath = path.replaceAllMapped(
        RegExp(r'\{(\w+)\}'),
        (m) {
          final varName = m[1]!;
          final dartName = safeDartName(toSnakeCamel(varName));
          final pathParam = params.firstWhere(
            (p) => p.name == varName || p.dartName == dartName,
            orElse: () => Param(name: varName, dartName: dartName, dartType: 'int', required: true, location: 'path'),
          );
          final needsToString = !pathParam.dartType.startsWith('String') &&
              !pathParam.dartType.startsWith('int') &&
              !pathParam.dartType.startsWith('num');
          return needsToString ? '\${$dartName.toString()}' : '\$$dartName';
        },
      );

      // ── Build query params map ─────────────────────────────────────────────
      final queryParams = params.where((p) => p.location == 'query').toList();
      String queryMapCode = '';
      if (queryParams.isNotEmpty) {
        final entries = queryParams.map((p) {
          // Use the sanitized dartName (no []) as both variable and key reference.
          // For the map key we use the original p.name (the actual API param name).
          if (p.dartType.startsWith('String')) {
            return p.required
                ? "      '${p.name}': ${p.dartName},"
                : "      if (${p.dartName} != null) '${p.name}': ${p.dartName}!,";
          } else if (p.dartType.startsWith('List')) {
            // List params: join with comma or repeat key — send as comma-separated string
            return p.required
                ? "      '${p.name}': ${p.dartName}.join(','),"
                : "      if (${p.dartName} != null) '${p.name}': ${p.dartName}!.join(','),";
          } else {
            // num, int, bool, etc — convert to string
            return p.required
                ? "      '${p.name}': ${p.dartName}.toString(),"
                : "      if (${p.dartName} != null) '${p.name}': ${p.dartName}!.toString(),";
          }
        });
        queryMapCode = '''
    final _queryArgs = <String, String>{
${entries.join('\n')}
    };''';
      }

      // ── Build body map from typed params ──────────────────────────────────
      String bodyMapCode = '';
      String bodyArg = '';
      if (hasBody && !useRawBody) {
        if (isMultipart) {
          // multipart/form-data — build Map<String, dynamic> for multipart method
          final entries = bodyParams.map((p) => p.required
              ? "        '${p.name}': ${p.dartName},"
              : "        if (${p.dartName} != null) '${p.name}': ${p.dartName},");
          bodyMapCode = '''
    final multipartFields = <String, dynamic>{
${entries.join('\n')}
    };''';
          bodyArg = ', fields: multipartFields';
        } else {
          final entries = bodyParams.map((p) => p.required
              ? "        '${p.name}': ${p.dartName},"
              : "        if (${p.dartName} != null) '${p.name}': ${p.dartName},");
          bodyMapCode = '''
    final bodyMap = <String, dynamic>{
${entries.join('\n')}
    };''';
          bodyArg = ', body: bodyMap';
        }
      } else if (useRawBody) {
        bodyArg = ', body: body';
      }

      // ── Build method call ──────────────────────────────────────────────────
      final qArg = queryParams.isNotEmpty ? ', params: _queryArgs' : '';
      final effectiveBodyArg = isMultipart
          ? bodyArg.replaceFirst(', body:', ', fields:')
          : bodyArg;
      final httpCall = switch (httpMethod) {
        'get'    => "return get('$dartPath'$qArg);",
        'post'   => isMultipart
            ? "return multipart('POST', '$dartPath'$qArg$effectiveBodyArg);"
            : "return post('$dartPath'$qArg$bodyArg);",
        'put'    => isMultipart
            ? "return multipart('PUT', '$dartPath'$qArg$effectiveBodyArg);"
            : "return put('$dartPath'$qArg$bodyArg);",
        'patch'  => isMultipart
            ? "return multipart('PATCH', '$dartPath'$qArg$effectiveBodyArg);"
            : "return patch('$dartPath'$qArg$bodyArg);",
        'delete' => "return delete('$dartPath'$qArg$bodyArg);",
        _        => "return get('$dartPath');",
      };

      // ── Doc comment ───────────────────────────────────────────────────────
      // Sanitize text: strip leading/trailing whitespace per line, drop empty
      // lines inside param descriptions, and cap total length so long markdown
      // blocks from the OpenAPI spec don't bleed into the code.
      String sanitizeDoc(String text, {int maxLines = 6}) {
        final lines = text
            .split('\n')
            .map((l) => l.trim())
            // Drop lines that are markdown bullets, code fences, or just punctuation
            .where((l) => l.isNotEmpty && !l.startsWith('```'))
            .take(maxLines)
            .toList();
        var result = lines.join(' ');
        // Remove characters that break Dart doc comments or string interpolation
        result = result
            .replaceAll('{', '(')
            .replaceAll('}', ')')
            .replaceAll('\$', '');
        return result;
      }

      final doc = StringBuffer();
      if (summary != null) {
        final safeSummary = sanitizeDoc(summary, maxLines: 1);
        doc.writeln('  /// ${httpMethod.toUpperCase()} $path — $safeSummary');
      }
      if (description != null) {
        final safeDesc = sanitizeDoc(description, maxLines: 4);
        if (safeDesc.isNotEmpty) {
          doc.writeln('  ///');
          // Wrap at ~90 chars per doc line
          const wrap = 88;
          var remaining = safeDesc;
          while (remaining.length > wrap) {
            final cut = remaining.lastIndexOf(' ', wrap);
            final pos = cut > 0 ? cut : wrap;
            doc.writeln('  /// ${remaining.substring(0, pos)}');
            remaining = remaining.substring(pos).trimLeft();
          }
          if (remaining.isNotEmpty) doc.writeln('  /// $remaining');
        }
      }
      for (final p in [...params, ...bodyParams].where((p) => p.description != null)) {
        final safeParamDesc = sanitizeDoc(p.description!, maxLines: 2);
        doc.writeln('  ///');
        doc.writeln('  /// [${p.dartName}] $safeParamDesc');
      }

      // ── Assemble method body ───────────────────────────────────────────────
      final methodBody = [
        if (queryMapCode.isNotEmpty) queryMapCode,
        if (bodyMapCode.isNotEmpty) bodyMapCode,
        '    $httpCall',
      ].join('\n');

      methods.add('''
${doc.toString().trimRight()}
  Future<Map<String, dynamic>> $methodName($namedParams) {
$methodBody
  }''');
    }
  }

  final methodsCode = methods.join('\n\n');

  return '''// GENERATED CODE — DO NOT EDIT BY HAND
// Generated by codegen/generate.dart from $schemaPath
// ignore_for_file: lines_longer_than_80_chars

import '../core/base_client.dart';

/// Lolzteam ${className.replaceAll('Client', '')} API client.
///
/// Auto-generated from OpenAPI schema.
class $className extends BaseClient {
  static const _baseUrl = '$baseUrl';

  $className({
    required super.token,
    super.proxy,
    super.maxRetries,
    super.retryDelay,
  });

  @override
  Uri buildUri(String path, Map<String, String>? params) =>
      Uri.parse('\$_baseUrl\$path').replace(queryParameters: params);

$methodsCode
}
''';
}

// ─── Entry point ──────────────────────────────────────────────────────────────

void main(List<String> args) {
  final opts = parseArgs(args);

  final schemaPath = opts['schema'];
  final outputPath = opts['output'];
  final className = opts['class-name'] ?? 'ApiClient';
  final baseUrl = opts['base-url'] ?? 'https://api.lzt.market';

  if (schemaPath == null || outputPath == null) {
    stderr.writeln('''
Usage:
  dart run codegen/generate.dart \\
    --schema schemas/forum.json \\
    --output lib/src/forum/forum_client.dart \\
    --class-name ForumClient \\
    --base-url https://api.lzt.market
''');
    exit(1);
  }

  final schemaFile = File(schemaPath);
  if (!schemaFile.existsSync()) {
    stderr.writeln('Error: schema file not found: $schemaPath');
    exit(1);
  }

  final schema = jsonDecode(schemaFile.readAsStringSync()) as Map<String, dynamic>;
  final code = generateClient(
    className: className,
    baseUrl: baseUrl,
    schemaPath: schemaPath,
    schema: schema,
  );

  final outFile = File(outputPath);
  outFile.parent.createSync(recursive: true);
  outFile.writeAsStringSync(code);

  final paths = (schema['paths'] as Map?)?.length ?? 0;
  stdout.writeln('✓ Generated $className with $paths paths → $outputPath');
}