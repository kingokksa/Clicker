import 'dart:convert';

class ApiError implements Exception {
  final String code;
  final String message;
  final String? hint;

  const ApiError(this.code, this.message, {this.hint});

  factory ApiError.invalidArgument(String message, {String? hint}) =>
      ApiError('invalid_argument', message, hint: hint);

  factory ApiError.notFound(String message, {String? hint}) =>
      ApiError('not_found', message, hint: hint);

  factory ApiError.unsupported(String message, {String? hint}) =>
      ApiError('unsupported', message, hint: hint);

  factory ApiError.conflict(String message, {String? hint}) =>
      ApiError('conflict', message, hint: hint);

  Map<String, dynamic> toJson() => {
        'code': code,
        'message': message,
        if (hint != null) 'hint': hint,
      };

  @override
  String toString() => 'ApiError($code): $message';
}

int? asInt(dynamic v) {
  if (v is int) return v;
  if (v is num) return v.round();
  if (v is String) return int.tryParse(v.trim());
  return null;
}

double? asDouble(dynamic v) {
  if (v is double) return v;
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v.trim());
  return null;
}

bool? asBool(dynamic v) {
  if (v is bool) return v;
  if (v is num) return v != 0;
  if (v is String) {
    final s = v.trim().toLowerCase();
    if (s == 'true' || s == '1' || s == 'yes' || s == 'on') return true;
    if (s == 'false' || s == '0' || s == 'no' || s == 'off') return false;
  }
  return null;
}

String? asString(dynamic v) {
  if (v == null) return null;
  if (v is String) return v;
  return v.toString();
}

Map<String, dynamic>? asMap(dynamic v) {
  if (v is Map<String, dynamic>) return v;
  if (v is Map) return v.cast<String, dynamic>();
  return null;
}

List<dynamic>? asList(dynamic v) {
  if (v is List) return v;
  return null;
}

int requireInt(Map<String, dynamic> args, String key) {
  final v = asInt(args[key]);
  if (v == null) {
    throw ApiError.invalidArgument('参数 "$key" 缺失或不是整数',
        hint: '示例："$key": 100。收到：${describeValue(args[key])}');
  }
  return v;
}

int optionalInt(Map<String, dynamic> args, String key, int def) =>
    asInt(args[key]) ?? def;

double optionalDouble(Map<String, dynamic> args, String key, double def) =>
    asDouble(args[key]) ?? def;

bool optionalBool(Map<String, dynamic> args, String key, bool def) =>
    asBool(args[key]) ?? def;

String requireString(Map<String, dynamic> args, String key) {
  final v = asString(args[key]);
  if (v == null || v.isEmpty) {
    throw ApiError.invalidArgument('参数 "$key" 缺失或不是非空字符串',
        hint: '示例："$key": "xxx"。收到：${describeValue(args[key])}');
  }
  return v;
}

String optionalString(Map<String, dynamic> args, String key, String def) =>
    asString(args[key]) ?? def;

Map<String, dynamic> requireMap(Map<String, dynamic> args, String key) {
  final v = asMap(args[key]);
  if (v == null) {
    throw ApiError.invalidArgument('参数 "$key" 缺失或不是对象',
        hint: '示例："$key": {...}。收到：${describeValue(args[key])}');
  }
  return v;
}

List<dynamic> requireList(Map<String, dynamic> args, String key) {
  final v = asList(args[key]);
  if (v == null) {
    throw ApiError.invalidArgument('参数 "$key" 缺失或不是数组',
        hint: '示例："$key": [...]。收到：${describeValue(args[key])}');
  }
  return v;
}

T optionalEnum<T extends Enum>(
    Map<String, dynamic> args, String key, List<T> values, T def) {
  final raw = args[key];
  if (raw == null) return def;
  final name = asString(raw);
  for (final v in values) {
    if (v.name == name) return v;
  }
  throw ApiError.invalidArgument('参数 "$key" 的取值 "$name" 不是合法枚举',
      hint: '可选值：${values.map((e) => e.name).join(' | ')}');
}

String describeValue(dynamic v) {
  if (v == null) return 'null';
  if (v is String) return '"$v"';
  if (v is Map || v is List) {
    try {
      final s = jsonEncode(v);
      return s.length <= 200 ? s : '${s.substring(0, 200)}...';
    } catch (_) {
      return v.toString();
    }
  }
  return v.toString();
}

Map<String, dynamic> normalizeArgs(
    Map<String, dynamic> schema, Map<String, dynamic> args) {
  final aliases = asMap(schema['x-aliases']);
  if (aliases == null || aliases.isEmpty) return args;
  var hit = false;
  final out = Map<String, dynamic>.from(args);
  for (final e in aliases.entries) {
    if (!out.containsKey(e.key)) continue;
    final to = e.value.toString();
    if (!out.containsKey(to)) out[to] = out[e.key];
    out.remove(e.key);
    hit = true;
  }
  return hit ? out : args;
}

List<String> aliasesFor(Map<String, dynamic> schema, String canonical) {
  final aliases = asMap(schema['x-aliases']);
  if (aliases == null) return const [];
  return [
    for (final e in aliases.entries)
      if (e.value.toString() == canonical) e.key,
  ];
}

String describeSchemaParams(Map<String, dynamic> schema) {
  final props = asMap(schema['properties']) ?? const <String, dynamic>{};
  if (props.isEmpty) return '（无参数）';
  return props.keys.join(', ');
}

List<String> validateAgainstSchema(
    Map<String, dynamic> schema, Map<String, dynamic> instance) {
  final errors = <String>[];

  final reqRaw = schema['required'];
  if (reqRaw is List) {
    for (final e in reqRaw) {
      final key = e.toString();
      if (!instance.containsKey(key)) {
        final alias = aliasesFor(schema, key);
        errors.add(alias.isEmpty
            ? '缺少必填参数 "$key"'
            : '缺少必填参数 "$key"（别名：${alias.join(' / ')}）');
      }
    }
  }

  final props = asMap(schema['properties']) ?? const <String, dynamic>{};
  for (final entry in props.entries) {
    if (!instance.containsKey(entry.key)) continue;
    final sub = asMap(entry.value);
    if (sub == null) continue;
    final err = _validateValue(entry.key, sub, instance[entry.key]);
    if (err != null) errors.add(err);
  }

  if (schema['additionalProperties'] == false) {
    for (final key in instance.keys) {
      if (!props.containsKey(key)) {
        errors.add('未知参数 "$key"（该能力不接受此参数）');
      }
    }
  }

  return errors;
}

String? _validateValue(String key, Map<String, dynamic> schema, dynamic value) {
  switch (schema['type']) {
    case 'integer':
      if (asInt(value) == null) {
        return '参数 "$key" 需要整数，收到 ${describeValue(value)}';
      }
    case 'number':
      if (asDouble(value) == null) {
        return '参数 "$key" 需要数字，收到 ${describeValue(value)}';
      }
    case 'string':
      if (value is! String) {
        return '参数 "$key" 需要字符串，收到 ${describeValue(value)}';
      }
    case 'boolean':
      if (asBool(value) == null) {
        return '参数 "$key" 需要布尔值，收到 ${describeValue(value)}';
      }
    case 'array':
      if (value is! List) {
        return '参数 "$key" 需要数组，收到 ${describeValue(value)}';
      }
    case 'object':
      if (asMap(value) == null) {
        return '参数 "$key" 需要对象，收到 ${describeValue(value)}';
      }
  }

  final enumRaw = schema['enum'];
  if (enumRaw is List && enumRaw.isNotEmpty) {
    if (!enumRaw.any((e) => e == value)) {
      return '参数 "$key" 的取值 ${describeValue(value)} 不在允许范围内：'
          '${enumRaw.join(' | ')}';
    }
  }

  final numValue = asDouble(value);
  if (numValue != null) {
    final min = asDouble(schema['minimum']);
    if (min != null && numValue < min) {
      return '参数 "$key" 不能小于 $min，收到 $numValue';
    }
    final max = asDouble(schema['maximum']);
    if (max != null && numValue > max) {
      return '参数 "$key" 不能大于 $max，收到 $numValue';
    }
  }

  return null;
}
