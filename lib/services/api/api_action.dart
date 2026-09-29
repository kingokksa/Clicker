import 'api_schema.dart';

const String apiVersion = '1.0.0';

typedef ApiHandler = Future<Map<String, dynamic>> Function(
    Map<String, dynamic> args);

Map<String, dynamic> objSchema(
  Map<String, dynamic> properties, [
  List<String> required = const [],
  bool allowExtra = false,
]) =>
    {
      'type': 'object',
      'properties': properties,
      if (required.isNotEmpty) 'required': required,
      'additionalProperties': allowExtra,
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
    final errors = validateAgainstSchema(action.inputSchema, args);
    if (errors.isNotEmpty) {
      throw ApiError.invalidArgument(errors.join('；'),
          hint: '参数名区分大小写；参考 system_capabilities 中 "${action.name}" 的 inputSchema');
    }
    return await action.handler(args);
  }

  Map<String, dynamic> describeAll() => {
        'count': _ordered.length,
        'groups': groups,
        'actions': [for (final a in _ordered) a.toDescriptorJson()],
      };
}
