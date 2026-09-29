import 'api_schema.dart';

const String apiVersion = '1.0.0';

typedef ApiHandler = Future<Map<String, dynamic>> Function(
    Map<String, dynamic> args);

Map<String, dynamic> objSchema(
  Map<String, dynamic> properties, [
  List<String> required = const [],
  bool allowExtra = false,
  Map<String, String> aliases = const {},
]) {
  final props = Map<String, dynamic>.from(properties);
  final effective = <String, String>{};
  for (final e in aliases.entries) {
    if (props.containsKey(e.key)) continue;
    final target = props[e.value];
    if (target is! Map) continue;
    props[e.key] = {
      ...target.cast<String, dynamic>(),
      'description': '${e.value} 的别名',
    };
    effective[e.key] = e.value;
  }
  return {
    'type': 'object',
    'properties': props,
    if (required.isNotEmpty) 'required': required,
    'additionalProperties': allowExtra,
    if (effective.isNotEmpty) 'x-aliases': effective,
  };
}

const Map<String, String> regionAliases = {
  'x': 'regionX',
  'y': 'regionY',
  'width': 'regionWidth',
  'height': 'regionHeight',
};

const Map<String, String> absoluteAliases = {
  'regionX': 'x',
  'regionY': 'y',
  'regionWidth': 'width',
  'regionHeight': 'height',
};

Map<String, dynamic> strField(String description,
        {String? def, List<String>? enumValues}) =>
    {
      'type': 'string',
      'description': description,
      if (def != null) 'default': def,
      if (enumValues != null) 'enum': enumValues,
    };

Map<String, dynamic> intField(String description,
        {int? min, int? max, int? def}) =>
    {
      'type': 'integer',
      'description': description,
      if (min != null) 'minimum': min,
      if (max != null) 'maximum': max,
      if (def != null) 'default': def,
    };

Map<String, dynamic> numField(String description,
        {num? min, num? max, num? def}) =>
    {
      'type': 'number',
      'description': description,
      if (min != null) 'minimum': min,
      if (max != null) 'maximum': max,
      if (def != null) 'default': def,
    };

Map<String, dynamic> boolField(String description, {bool? def}) => {
      'type': 'boolean',
      'description': description,
      if (def != null) 'default': def,
    };

Map<String, dynamic> arrField(String description,
        {Map<String, dynamic>? items}) =>
    {
      'type': 'array',
      'description': description,
      if (items != null) 'items': items,
    };

Map<String, dynamic> objField(
  String description,
  Map<String, dynamic> properties, [
  List<String> required = const [],
  bool allowExtra = false,
]) =>
    {
      'type': 'object',
      'description': description,
      'properties': properties,
      if (required.isNotEmpty) 'required': required,
      'additionalProperties': allowExtra,
    };

class ApiAction {
  final String name;
  final String group;
  final String summary;
  final String description;
  final Map<String, dynamic> inputSchema;
  final bool readOnly;
  final ApiHandler handler;

  const ApiAction({
    required this.name,
    required this.group,
    required this.summary,
    required this.description,
    required this.handler,
    this.inputSchema = const {
      'type': 'object',
      'properties': <String, dynamic>{},
      'additionalProperties': false,
    },
    this.readOnly = false,
  });

  Map<String, dynamic> toToolJson() => {
        'name': name,
        'title': summary,
        'description': description,
        'inputSchema': inputSchema,
        'annotations': {
          'title': summary,
          'readOnlyHint': readOnly,
          'destructiveHint': !readOnly,
        },
      };

  Map<String, dynamic> toDescriptorJson() => {
        'name': name,
        'group': group,
        'summary': summary,
        'description': description,
        'readOnly': readOnly,
        'inputSchema': inputSchema,
      };
}

class ApiActionRegistry {
  final Map<String, ApiAction> _byName = {};
  final List<ApiAction> _ordered = [];

  void register(ApiAction action) {
    if (_byName.containsKey(action.name)) {
      throw StateError('重复注册接口能力: ${action.name}');
    }
    _byName[action.name] = action;
    _ordered.add(action);
  }

  void registerAll(Iterable<ApiAction> actions) {
    for (final a in actions) {
      register(a);
    }
  }

  ApiAction? find(String name) => _byName[name];

  bool contains(String name) => _byName.containsKey(name);

  int get length => _ordered.length;

  List<ApiAction> get all => List.unmodifiable(_ordered);

  List<String> get groups {
    final out = <String>[];
    for (final a in _ordered) {
      if (!out.contains(a.group)) out.add(a.group);
    }
    return out;
  }

  Future<Map<String, dynamic>> call(
      String name, Map<String, dynamic> args) async {
    final action = _byName[name];
    if (action == null) {
      throw ApiError.notFound('未知能力 "$name"',
          hint: '调用 system_capabilities 可获取全部能力清单');
    }
    final normalized = normalizeArgs(action.inputSchema, args);
    final errors = validateAgainstSchema(action.inputSchema, normalized);
    if (errors.isNotEmpty) {
      throw ApiError.invalidArgument(errors.join('；'),
          hint: '${action.name} 接受的参数：${describeSchemaParams(action.inputSchema)}');
    }
    return await action.handler(normalized);
  }

  Map<String, dynamic> describeAll() => {
        'count': _ordered.length,
        'groups': groups,
        'actions': [for (final a in _ordered) a.toDescriptorJson()],
      };
}
