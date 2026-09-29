import 'package:clicker/services/api/api_action.dart';
import 'package:clicker/services/api/api_schema.dart';
import 'package:flutter_test/flutter_test.dart';

ApiAction _action({
  String name = 'demo_run',
  String group = 'demo',
  String summary = '演示',
  String description = '演示能力',
  Map<String, dynamic>? inputSchema,
  bool readOnly = false,
  ApiHandler? handler,
}) =>
    ApiAction(
      name: name,
      group: group,
      summary: summary,
      description: description,
      readOnly: readOnly,
      inputSchema: inputSchema ??
          const {
            'type': 'object',
            'properties': <String, dynamic>{},
            'additionalProperties': false,
          },
      handler: handler ?? (args) async => {'ok': true},
    );

Future<ApiError> _captureAsync(Future<void> Function() body) async {
  try {
    await body();
  } on ApiError catch (e) {
    return e;
  }
  fail('期望抛出 ApiError，但没有抛出');
}

void main() {
  test('apiVersion 非空', () => expect(apiVersion, isNotEmpty));

  group('schema 构造助手', () {
    test('objSchema 基本形状', () {
      final s = objSchema({'x': intField('坐标')});
      expect(s['type'], 'object');
      expect(s['properties'], isA<Map<String, dynamic>>());
      expect(s['additionalProperties'], isFalse);
    });
    test('objSchema 无必填时省略 required', () {
      expect(objSchema({}).containsKey('required'), isFalse);
    });
    test('objSchema 有必填时写入 required', () {
      expect(objSchema({}, ['x'])['required'], ['x']);
    });
    test('objSchema allowExtra 生效', () {
      expect(objSchema({}, const [], true)['additionalProperties'], isTrue);
    });
    test('strField 默认省略 default/enum', () {
      final f = strField('说明');
      expect(f['type'], 'string');
      expect(f['description'], '说明');
      expect(f.containsKey('default'), isFalse);
      expect(f.containsKey('enum'), isFalse);
    });
    test('strField 带 default 与 enum', () {
      final f = strField('说明', def: 'a', enumValues: ['a', 'b']);
      expect(f['default'], 'a');
      expect(f['enum'], ['a', 'b']);
    });
    test('intField 带 min/max/default', () {
      final f = intField('数量', min: 1, max: 9, def: 3);
      expect(f['type'], 'integer');
      expect(f['minimum'], 1);
      expect(f['maximum'], 9);
      expect(f['default'], 3);
    });
    test('intField 省略可选键', () {
      final f = intField('数量');
      expect(f.containsKey('minimum'), isFalse);
      expect(f.containsKey('maximum'), isFalse);
      expect(f.containsKey('default'), isFalse);
    });
    test('numField 类型为 number', () {
      expect(numField('比例')['type'], 'number');
    });
    test('boolField 类型为 boolean', () {
      expect(boolField('开关')['type'], 'boolean');
    });
    test('arrField 无 items 时省略 items', () {
      expect(arrField('列表').containsKey('items'), isFalse);
    });
    test('arrField 带 items', () {
      final f = arrField('列表', items: objField('一项', {'a': intField('a')}));
      expect(f['type'], 'array');
      expect(f['items'], isA<Map<String, dynamic>>());
    });
    test('objField 带 description', () {
      final f = objField('说明', {'a': intField('a')}, ['a']);
      expect(f['type'], 'object');
      expect(f['description'], '说明');
      expect(f['required'], ['a']);
      expect(f['additionalProperties'], isFalse);
    });
    test('objSchema 无别名时不写 x-aliases', () {
      expect(objSchema({'x': intField('x')}).containsKey('x-aliases'), isFalse);
    });
    test('objSchema 把别名写进 properties 与 x-aliases', () {
      final s = objSchema({'regionWidth': intField('区域宽度')}, const [], false,
          const {'width': 'regionWidth'});
      final props = s['properties'] as Map<String, dynamic>;
      expect(props.keys, containsAll(['regionWidth', 'width']));
      expect((props['width'] as Map)['type'], 'integer');
      expect((props['width'] as Map)['description'], contains('别名'));
      expect(s['x-aliases'], {'width': 'regionWidth'});
    });
    test('objSchema 别名不覆盖已存在的同名参数', () {
      final s = objSchema(
          {'width': intField('本名'), 'regionWidth': intField('区域宽度')},
          const [],
          false,
          const {'width': 'regionWidth'});
      expect((s['properties'] as Map)['width']['description'], '本名');
    });
    test('objSchema 别名指向不存在的参数时既不入 properties 也不入 x-aliases', () {
      final s = objSchema({'x': intField('x')}, const [], false,
          const {'y': 'nope'});
      expect((s['properties'] as Map).containsKey('y'), isFalse);
      expect(s.containsKey('x-aliases'), isFalse);
    });
    test('objSchema 只登记目标参数存在的别名', () {
      final s = objSchema(
          {'x': intField('x'), 'y': intField('y')},
          const [],
          false,
          const {'regionX': 'x', 'regionY': 'y', 'regionWidth': 'width'});
      final props = (s['properties'] as Map).cast<String, dynamic>();
      expect(props.containsKey('regionX'), isTrue);
      expect(props.containsKey('regionWidth'), isFalse);
      expect(s['x-aliases'], {'regionX': 'x', 'regionY': 'y'});
    });
    test('regionAliases 把 x/y/width/height 指向 region*', () {
      expect(regionAliases['x'], 'regionX');
      expect(regionAliases['y'], 'regionY');
      expect(regionAliases['width'], 'regionWidth');
      expect(regionAliases['height'], 'regionHeight');
    });
    test('absoluteAliases 把 region* 指向 x/y/width/height', () {
      expect(absoluteAliases['regionX'], 'x');
      expect(absoluteAliases['regionY'], 'y');
      expect(absoluteAliases['regionWidth'], 'width');
      expect(absoluteAliases['regionHeight'], 'height');
    });
  });

  group('ApiAction', () {
    test('默认 inputSchema 为不接受额外参数的空对象', () {
      final a = _action();
      expect(a.inputSchema['type'], 'object');
      expect(a.inputSchema['additionalProperties'], isFalse);
    });
    test('readOnly 默认 false', () => expect(_action().readOnly, isFalse));
    test('toToolJson 形状', () {
      final t = _action(summary: '标题', description: '详情').toToolJson();
      expect(t['name'], 'demo_run');
      expect(t['title'], '标题');
      expect(t['description'], '详情');
      expect(t['inputSchema'], isA<Map<String, dynamic>>());
    });
    test('toToolJson 只读能力标注 readOnlyHint', () {
      final ann = _action(readOnly: true).toToolJson()['annotations'];
      expect(ann['readOnlyHint'], isTrue);
      expect(ann['destructiveHint'], isFalse);
    });
    test('toToolJson 非只读能力标注 destructiveHint', () {
      final ann = _action().toToolJson()['annotations'];
      expect(ann['readOnlyHint'], isFalse);
      expect(ann['destructiveHint'], isTrue);
    });
    test('toDescriptorJson 形状', () {
      final d = _action(group: 'g').toDescriptorJson();
      expect(d['name'], 'demo_run');
      expect(d['group'], 'g');
      expect(d['readOnly'], isFalse);
      expect(d['inputSchema'], isA<Map<String, dynamic>>());
    });
  });

  group('ApiActionRegistry 注册与查询', () {
    test('register 后可查询', () {
      final r = ApiActionRegistry()..register(_action());
      expect(r.length, 1);
      expect(r.contains('demo_run'), isTrue);
      expect(r.find('demo_run')?.name, 'demo_run');
    });
    test('未注册返回 null', () {
      expect(ApiActionRegistry().find('nope'), isNull);
      expect(ApiActionRegistry().contains('nope'), isFalse);
    });
    test('重名注册抛 StateError', () {
      final r = ApiActionRegistry()..register(_action());
      expect(() => r.register(_action()), throwsA(isA<StateError>()));
    });
    test('registerAll 批量注册', () {
      final r = ApiActionRegistry()
        ..registerAll([_action(name: 'a', group: 'g1'), _action(name: 'b', group: 'g2')]);
      expect(r.length, 2);
    });
    test('all 不可修改', () {
      final r = ApiActionRegistry()..register(_action());
      expect(() => r.all.add(_action(name: 'z')), throwsUnsupportedError);
    });
    test('groups 按注册顺序去重', () {
      final r = ApiActionRegistry()
        ..registerAll([
          _action(name: 'a', group: 'g1'),
          _action(name: 'b', group: 'g2'),
          _action(name: 'c', group: 'g1'),
        ]);
      expect(r.groups, ['g1', 'g2']);
    });
  });

  group('ApiActionRegistry.call', () {
    test('未知能力抛 not_found 且 hint 指向 system_capabilities', () async {
      final e = await _captureAsync(
          () => ApiActionRegistry().call('nope', const {}));
      expect(e.code, 'not_found');
      expect(e.hint, contains('system_capabilities'));
    });
    test('参数校验失败抛 invalid_argument', () async {
      final r = ApiActionRegistry()
        ..register(_action(inputSchema: objSchema({'x': intField('x')}, ['x'])));
      final e = await _captureAsync(() => r.call('demo_run', const {}));
      expect(e.code, 'invalid_argument');
      expect(e.message, contains('缺少必填参数'));
    });
    test('拒绝 schema 未声明的参数', () async {
      final r = ApiActionRegistry()..register(_action());
      final e = await _captureAsync(() => r.call('demo_run', const {'zzz': 1}));
      expect(e.code, 'invalid_argument');
      expect(e.message, contains('未知参数'));
    });
    test('校验通过时返回 handler 结果', () async {
      final r = ApiActionRegistry()
        ..register(_action(
            inputSchema: objSchema({'x': intField('x')}, ['x']),
            handler: (args) async => {'echo': args['x']}));
      expect(await r.call('demo_run', const {'x': 7}), {'echo': 7});
    });
    test('宽容转换后再交给 handler', () async {
      final r = ApiActionRegistry()
        ..register(_action(
            inputSchema: objSchema({'x': intField('x')}, ['x']),
            handler: (args) async => {'type': args['x'].runtimeType.toString()}));
      expect(await r.call('demo_run', const {'x': '7'}), {'type': 'String'});
    });
    test('校验失败时 hint 列出该能力接受的参数', () async {
      final r = ApiActionRegistry()
        ..register(_action(
            inputSchema: objSchema({'x': intField('x')}, ['x'])));
      final e = await _captureAsync(() => r.call('demo_run', const {}));
      expect(e.hint, contains('demo_run'));
      expect(e.hint, contains('x'));
    });
    test('别名参数被规范化后交给 handler', () async {
      final r = ApiActionRegistry()
        ..register(_action(
            inputSchema: objSchema(
                {'regionWidth': intField('宽')}, const [], false,
                const {'width': 'regionWidth'}),
            handler: (args) async => {
                  'w': args['regionWidth'],
                  'hasAlias': args.containsKey('width'),
                }));
      expect(await r.call('demo_run', const {'width': 42}),
          {'w': 42, 'hasAlias': false});
    });
    test('别名可满足 required 校验', () async {
      final r = ApiActionRegistry()
        ..register(_action(
            inputSchema: objSchema({'hex': strField('颜色')}, ['hex'], false,
                const {'color': 'hex'}),
            handler: (args) async => {'hex': args['hex']}));
      expect(await r.call('demo_run', const {'color': '#FF0000'}),
          {'hex': '#FF0000'});
    });
    test('同时传别名与规范名时规范名生效', () async {
      final r = ApiActionRegistry()
        ..register(_action(
            inputSchema: objSchema({'hex': strField('颜色')}, ['hex'], false,
                const {'color': 'hex'}),
            handler: (args) async => {'hex': args['hex']}));
      expect(await r.call('demo_run', const {'hex': '#111111', 'color': '#222222'}),
          {'hex': '#111111'});
    });
    test('handler 抛出的 ApiError 原样上抛', () async {
      final r = ApiActionRegistry()
        ..register(_action(
            handler: (args) async => throw ApiError.conflict('冲突')));
      final e = await _captureAsync(() => r.call('demo_run', const {}));
      expect(e.code, 'conflict');
    });
  });

  group('describeAll', () {
    test('汇总数量、分组与能力描述', () {
      final r = ApiActionRegistry()
        ..registerAll([_action(name: 'a', group: 'g1'), _action(name: 'b', group: 'g2')]);
      final d = r.describeAll();
      expect(d['count'], 2);
      expect(d['groups'], ['g1', 'g2']);
      expect((d['actions'] as List).length, 2);
    });
  });
}
