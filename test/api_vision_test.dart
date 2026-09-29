import 'package:clicker/services/api/api_action.dart';
import 'package:clicker/services/api/api_capabilities.dart';
import 'package:clicker/services/api/api_schema.dart';
import 'package:clicker/services/app_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late ApiActionRegistry registry;

  setUpAll(() {
    registry = buildApiRegistry(AppState());
  });

  Map<String, dynamic> props(String name) =>
      (registry.find(name)!.inputSchema['properties'] as Map)
          .cast<String, dynamic>();

  List<String> requiredOf(String name) =>
      ((registry.find(name)!.inputSchema['required'] as List?) ?? const [])
          .cast<String>();

  group('视觉能力已注册', () {
    test('查找 / 等待 / 取色能力都在 vision 组且有说明', () {
      for (final n in const [
        'vision_find_image',
        'vision_find_image_all',
        'vision_wait_image',
        'vision_find_color',
      ]) {
        final a = registry.find(n);
        expect(a, isNotNull, reason: '$n 未注册');
        expect(a!.group, 'vision');
        expect(a.summary.isNotEmpty, isTrue);
        expect(a.description.isNotEmpty, isTrue);
      }
    });

    test('vision_ocr 仍注册在 vision 组', () {
      expect(registry.find('vision_ocr')!.group, 'vision');
    });
  });

  group('多目标与多尺度参数', () {
    test('vision_find_image_all 暴露 maxResults 与 scales', () {
      final p = props('vision_find_image_all');
      expect(p.containsKey('maxResults'), isTrue);
      expect(p['maxResults']['type'], 'integer');
      expect(p['maxResults']['default'], 10);
      expect(p['maxResults']['minimum'], 1);
      expect(p['maxResults']['maximum'], 200);
      expect(p['scales']['type'], 'array');
      expect(p['scales']['items']['type'], 'number');
    });

    test('vision_find_image 也支持 scales', () {
      expect(props('vision_find_image')['scales']['type'], 'array');
    });

    test('vision_wait_image 暴露 timeoutMs 与 intervalMs', () {
      final p = props('vision_wait_image');
      expect(p['timeoutMs']['default'], 10000);
      expect(p['timeoutMs']['minimum'], 100);
      expect(p['timeoutMs']['maximum'], 600000);
      expect(p['intervalMs']['default'], 200);
      expect(p['intervalMs']['minimum'], 20);
      expect(p['scales']['type'], 'array');
    });

    test('三个查找能力的区域参数默认整屏', () {
      for (final n in const [
        'vision_find_image',
        'vision_find_image_all',
        'vision_wait_image',
      ]) {
        final p = props(n);
        expect(p['regionX']['type'], 'integer');
        expect(p['regionY']['type'], 'integer');
        expect(p['regionWidth']['type'], 'integer');
        expect(p['regionHeight']['type'], 'integer');
      }
    });
  });

  group('vision_find_color 参数校验', () {
    test('hex 是必填项', () {
      expect(requiredOf('vision_find_color'), contains('hex'));
    });

    test('tolerance 默认 10 且范围 0~255', () {
      final t = props('vision_find_color')['tolerance'];
      expect(t['type'], 'integer');
      expect(t['default'], 10);
      expect(t['minimum'], 0);
      expect(t['maximum'], 255);
    });

    test('非法 hex 抛 invalid_argument（不会触碰屏幕）', () async {
      await expectLater(
        registry.call('vision_find_color', {'hex': 'zzz'}),
        throwsA(isA<ApiError>()),
      );
    });

    test('长度不对的 hex 也抛 invalid_argument', () async {
      await expectLater(
        registry.call('vision_find_color', {'hex': '#12345'}),
        throwsA(isA<ApiError>()),
      );
    });

    test('缺少 hex 抛参数校验错误', () async {
      await expectLater(
        registry.call('vision_find_color', const {}),
        throwsA(isA<ApiError>()),
      );
    });

    test('非法 hex 的错误信息提示了正确格式', () async {
      try {
        await registry.call('vision_find_color', {'hex': 'nope'});
        fail('应当抛出 ApiError');
      } on ApiError catch (e) {
        expect(e.message.contains('hex'), isTrue);
      }
    });
  });

  group('控件（UI Automation）能力', () {
    const names = [
      'vision_dump_elements',
      'vision_find_element',
      'vision_wait_element',
      'vision_screenshot_png',
      'vision_set_of_mark',
    ];

    test('五个新能力都在 vision 组、有说明、且是只读', () {
      for (final n in names) {
        final a = registry.find(n);
        expect(a, isNotNull, reason: '$n 未注册');
        expect(a!.group, 'vision');
        expect(a.summary.isNotEmpty, isTrue);
        expect(a.description.isNotEmpty, isTrue);
        expect(a.readOnly, isTrue, reason: '$n 应当是只读');
      }
    });

    test('vision_dump_elements 暴露 maxDepth / maxElements / hwnd', () {
      final p = props('vision_dump_elements');
      expect(p['maxDepth']['type'], 'integer');
      expect(p['maxDepth']['default'], 6);
      expect(p['maxDepth']['minimum'], 1);
      expect(p['maxDepth']['maximum'], 20);
      expect(p['maxElements']['type'], 'integer');
      expect(p['maxElements']['default'], 400);
      expect(p['maxElements']['maximum'], 4000);
      expect(p['hwnd']['type'], 'integer');
      expect(p['hwnd']['default'], 0);
    });

    test('vision_find_element 暴露四个查找条件', () {
      final p = props('vision_find_element');
      for (final k in const [
        'name',
        'automationId',
        'className',
        'controlType',
      ]) {
        expect(p[k]['type'], 'string', reason: '$k 应当是字符串');
      }
      expect(requiredOf('vision_find_element'), isEmpty);
    });

    test('vision_wait_element 暴露 timeoutMs / intervalMs', () {
      final p = props('vision_wait_element');
      expect(p['timeoutMs']['default'], 10000);
      expect(p['timeoutMs']['minimum'], 100);
      expect(p['timeoutMs']['maximum'], 600000);
      expect(p['intervalMs']['default'], 200);
      expect(p['intervalMs']['minimum'], 20);
      expect(p['intervalMs']['maximum'], 60000);
    });

    test('vision_screenshot_png 暴露区域与 maxWidth', () {
      final p = props('vision_screenshot_png');
      for (final k in const ['x', 'y', 'width', 'height']) {
        expect(p[k]['type'], 'integer', reason: '$k 应当是整数');
      }
      expect(p['maxWidth']['type'], 'integer');
      expect(p['maxWidth']['default'], 0);
      expect(p['maxWidth']['minimum'], 0);
      expect(p['maxWidth']['maximum'], 8192);
    });

    test('vision_set_of_mark 暴露编号上限与缩放', () {
      final p = props('vision_set_of_mark');
      expect(p['maxDepth']['default'], 6);
      expect(p['maxElements']['default'], 60);
      expect(p['maxElements']['maximum'], 200);
      expect(p['maxWidth']['maximum'], 8192);
      expect(p['hwnd']['default'], 0);
    });

    test('条件全空时 vision_find_element 直接返回 found=false', () async {
      final r = await registry.call('vision_find_element', const {});
      expect(r['found'], isFalse);
    });

    test('条件全空时 vision_wait_element 不等待 timeout', () async {
      final sw = Stopwatch()..start();
      final r = await registry.call(
          'vision_wait_element', const {'timeoutMs': 10000});
      sw.stop();
      expect(r['found'], isFalse);
      expect(sw.elapsedMilliseconds < 3000, isTrue,
          reason: '空条件应当立即返回，实际耗时 ${sw.elapsedMilliseconds}ms');
    });
  });

  group('OCR 引擎切换', () {
    test('vision_ocr_engines 在 vision 组、有说明、只读', () {
      final a = registry.find('vision_ocr_engines');
      expect(a, isNotNull, reason: 'vision_ocr_engines 未注册');
      expect(a!.group, 'vision');
      expect(a.readOnly, isTrue);
      expect(a.summary.isNotEmpty, isTrue);
      expect(a.description.isNotEmpty, isTrue);
    });

    test('vision_set_ocr_engine 在 vision 组、可写、id 可选', () {
      final a = registry.find('vision_set_ocr_engine');
      expect(a, isNotNull, reason: 'vision_set_ocr_engine 未注册');
      expect(a!.group, 'vision');
      expect(a.readOnly, isFalse);
      expect(a.summary.isNotEmpty, isTrue);
      expect(requiredOf('vision_set_ocr_engine'), isEmpty);
      expect(props('vision_set_ocr_engine')['id']['type'], 'string');
    });

    test('vision_ocr_engines 返回 engines / selected / preferred', () async {
      final r = await registry.call('vision_ocr_engines', const {});
      expect(r['engines'], isA<List>());
      expect(r.containsKey('selected'), isTrue);
      expect(r.containsKey('preferred'), isTrue);
    });

    test('vision_set_ocr_engine 未知 id 抛 ApiError', () async {
      await expectLater(
        registry.call('vision_set_ocr_engine', const {'id': '__nope__'}),
        throwsA(isA<ApiError>()),
      );
    });

    test('vision_set_ocr_engine 传 auto 不抛错并返回状态', () async {
      final r = await registry.call(
          'vision_set_ocr_engine', const {'id': 'auto'});
      expect(r.containsKey('selected'), isTrue);
      expect(r.containsKey('available'), isTrue);
    });

    test('未知 id 的错误信息提示了可用的查看方式', () async {
      try {
        await registry.call('vision_set_ocr_engine', const {'id': 'nope'});
        fail('应当抛出 ApiError');
      } on ApiError catch (e) {
        expect(e.message.contains('nope'), isTrue);
      }
    });
  });

  group('参数别名', () {
    const regionAliasActions = [
      'vision_find_image',
      'vision_find_image_all',
      'vision_wait_image',
      'vision_find_color',
    ];
    const absoluteAliasActions = [
      'vision_capture_template',
      'vision_ocr',
      'vision_get_pixel',
      'vision_screenshot',
      'vision_screenshot_png',
      'vision_set_of_mark',
    ];

    Map<String, dynamic> schemaOf(String n) => registry.find(n)!.inputSchema;

    Map<String, String> aliasesOf(String n) =>
        ((schemaOf(n)['x-aliases'] as Map?) ?? const {}).cast<String, String>();

    Map<String, dynamic> propsOf(String n) =>
        (schemaOf(n)['properties'] as Map).cast<String, dynamic>();

    List<String> requiredOf(String n) =>
        ((schemaOf(n)['required'] as List?) ?? const []).cast<String>();

    Map<String, dynamic> extrasFor(String n, Set<String> covered) {
      final props = propsOf(n);
      final out = <String, dynamic>{};
      for (final r in requiredOf(n)) {
        if (covered.contains(r)) continue;
        final type = (props[r] as Map?)?['type'];
        out[r] = type == 'integer'
            ? 1
            : type == 'number'
                ? 1.0
                : type == 'boolean'
                    ? true
                    : 'x';
      }
      return out;
    }

    List<String> validateAliases(String n, Map<String, dynamic> args) {
      final normalized = normalizeArgs(schemaOf(n), args);
      return validateAgainstSchema(schemaOf(n),
          {...normalized, ...extrasFor(n, normalized.keys.toSet())});
    }

    void checkAliases(String n, Map<String, String> expected) {
      final aliases = aliasesOf(n);
      for (final e in expected.entries) {
        expect(aliases[e.key], e.value, reason: '$n 未声明别名 ${e.key} → ${e.value}');
      }
      final normalized = normalizeArgs(
          schemaOf(n), {for (final k in expected.keys) k: 7});
      for (final e in expected.entries) {
        expect(normalized[e.value], 7,
            reason: '$n: ${e.key} 未规范化为 ${e.value}');
        expect(normalized.containsKey(e.key), isFalse,
            reason: '$n: 别名 ${e.key} 未被消费');
      }
    }

    test('区域类能力把 x/y/width/height 声明为 region* 的别名', () {
      for (final n in regionAliasActions) {
        checkAliases(n, regionAliases);
      }
    });

    test('绝对坐标类能力把 region* 声明为 x/y/width/height 的别名', () {
      for (final n in absoluteAliasActions) {
        final props = propsOf(n);
        final expected = {
          for (final e in absoluteAliases.entries)
            if (props.containsKey(e.value)) e.key: e.value,
        };
        expect(expected, isNotEmpty, reason: '$n 一个 region* 别名都没声明');
        checkAliases(n, expected);
      }
    });

    test('vision_find_color 把 color / colour 声明为 hex 的别名', () {
      final schema = schemaOf('vision_find_color');
      expect(aliasesOf('vision_find_color')['color'], 'hex');
      expect(aliasesOf('vision_find_color')['colour'], 'hex');
      for (final a in const ['color', 'colour']) {
        final normalized = normalizeArgs(schema, {a: '#FF0000'});
        expect(normalized['hex'], '#FF0000', reason: '$a 未规范化为 hex');
        expect(validateAgainstSchema(schema, normalized), isEmpty,
            reason: '$a 规范化后未通过校验');
      }
    });

    test('别名参数能通过真实 schema 的校验', () {
      for (final n in regionAliasActions) {
        expect(
            validateAliases(
                n, const {'x': 1, 'y': 2, 'width': 3, 'height': 4}),
            isEmpty,
            reason: '$n 的 x/y/width/height 别名未通过校验');
      }
      expect(validateAliases('vision_get_pixel', const {'regionX': 1, 'regionY': 2}),
          isEmpty,
          reason: 'vision_get_pixel 的 regionX/regionY 别名未通过校验');
      expect(
          validateAliases('vision_ocr', const {
            'regionX': 1,
            'regionY': 2,
            'regionWidth': 3,
            'regionHeight': 4,
          }),
          isEmpty,
          reason: 'vision_ocr 的 region* 别名未通过校验');
      expect(
          validateAliases('vision_capture_template', const {
            'regionX': 1,
            'regionY': 2,
            'regionWidth': 3,
            'regionHeight': 4,
          }),
          isEmpty,
          reason: 'vision_capture_template 的 region* 别名未通过校验');
    });

    test('原始参数名仍然有效且不被改写', () {
      for (final n in regionAliasActions) {
        const args = {'regionX': 5, 'regionWidth': 6};
        expect(normalizeArgs(schemaOf(n), args), args);
        expect(validateAliases(n, args), isEmpty,
            reason: '$n 的原始 region* 参数名失效了');
      }
    });

    test('vision_get_pixel 不把 regionWidth 改写成未声明的 width', () {
      final schema = schemaOf('vision_get_pixel');
      expect(propsOf('vision_get_pixel').containsKey('width'), isFalse);
      expect(aliasesOf('vision_get_pixel').containsKey('regionWidth'), isFalse);
      expect(
          normalizeArgs(schema, const {'regionX': 1})['width'], isNull);
    });

    test('校验失败时 hint 列出可接受参数（含别名）', () async {
      try {
        await registry.call('vision_find_image', const {'zzz': 1});
        fail('应当抛出 ApiError');
      } on ApiError catch (e) {
        expect(e.code, 'invalid_argument');
        expect(e.message.contains('未知参数'), isTrue);
        expect(e.hint, contains('regionWidth'));
        expect(e.hint, contains('width'));
      }
    });

    test('用别名调用能力不会被参数校验拦下', () async {
      try {
        await registry.call('vision_find_color', const {'color': 'zzz'});
        fail('应当抛出 ApiError');
      } on ApiError catch (e) {
        expect(e.code, 'invalid_argument');
        expect(e.message.contains('hex'), isTrue,
            reason: '应当报颜色非法，而不是报缺少 hex');
        expect(e.message.contains('缺少必填参数'), isFalse);
      }
    });
  });
}
