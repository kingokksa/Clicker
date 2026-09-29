import 'package:clicker/services/api/api_action.dart';
import 'package:clicker/services/api/api_openapi.dart';
import 'package:flutter_test/flutter_test.dart';

ApiAction _action({String name = 'demo_run', String group = 'demo'}) =>
    ApiAction(
      name: name,
      group: group,
      summary: '演示',
      description: '演示能力',
      handler: (args) async => {'ok': true},
    );

Map<String, dynamic> _doc({
  List<ApiAction>? actions,
  String base = 'http://127.0.0.1:9876',
}) {
  final registry = ApiActionRegistry();
  for (final a in actions ?? [_action()]) {
    registry.register(a);
  }
  return buildOpenApiDocument(registry, baseUrl: base);
}

Map<String, dynamic> _op(Map<String, dynamic> doc, String path, String method) =>
    ((doc['paths'] as Map)[path] as Map)[method] as Map<String, dynamic>;

void main() {
  group('顶层结构', () {
    test('openapi 版本为 3.1.0', () => expect(_doc()['openapi'], '3.1.0'));
    test('info 含标题、版本与说明', () {
      final info = _doc()['info'] as Map;
      expect(info['title'], isNotEmpty);
      expect(info['version'], apiVersion);
      expect(info['description'], isNotEmpty);
    });
    test('servers 使用传入的 baseUrl', () {
      final doc = _doc(base: 'http://10.0.0.2:8080');
      expect((doc['servers'] as List).first['url'], 'http://10.0.0.2:8080');
    });
    test('tags 来自能力分组且保序', () {
      final doc = _doc(actions: [
        _action(name: 'a', group: 'g1'),
        _action(name: 'b', group: 'g2'),
      ]);
      expect(
        (doc['tags'] as List).map((t) => t['name']).toList(),
        ['g1', 'g2'],
      );
    });
    test('声明 bearer 鉴权方案', () {
      final schemes = (_doc()['components'] as Map)['securitySchemes'] as Map;
      expect(schemes['bearerAuth']['type'], 'http');
      expect(schemes['bearerAuth']['scheme'], 'bearer');
      expect(schemes['bearerAuth']['description'], isNotEmpty);
    });
    test('全局 security 要求 bearerAuth', () {
      expect((_doc()['security'] as List).first, contains('bearerAuth'));
    });
  });

  group('能力路径', () {
    test('每个能力产出一条 POST 路径', () {
      final doc = _doc(actions: [
        _action(name: 'a'),
        _action(name: 'b'),
      ]);
      final paths = doc['paths'] as Map;
      expect(paths.containsKey('/api/v1/a'), isTrue);
      expect(paths.containsKey('/api/v1/b'), isTrue);
    });
    test('操作含 tags/operationId/summary/description', () {
      final op = _op(_doc(), '/api/v1/demo_run', 'post');
      expect(op['operationId'], 'demo_run');
      expect(op['tags'], ['demo']);
      expect(op['summary'], isNotEmpty);
      expect(op['description'], isNotEmpty);
    });
    test('requestBody 复用能力的 inputSchema', () {
      final op = _op(_doc(), '/api/v1/demo_run', 'post');
      final body = op['requestBody'] as Map;
      expect(body['required'], isTrue);
      expect(body['content']['application/json']['schema']['type'], 'object');
    });
    test('响应声明 200/400/404/409', () {
      final op = _op(_doc(), '/api/v1/demo_run', 'post');
      expect((op['responses'] as Map).keys, containsAll(['200', '400', '404', '409']));
    });
    test('200 响应声明 ok/action/result', () {
      final op = _op(_doc(), '/api/v1/demo_run', 'post');
      final props = op['responses']['200']['content']['application/json']
          ['schema']['properties'] as Map;
      expect(props.keys, containsAll(['ok', 'action', 'result']));
    });
  });

  group('固定路径', () {
    test('包含 capabilities 与 mcp', () {
      final doc = _doc();
      expect((doc['paths'] as Map).containsKey('/api/v1/capabilities'), isTrue);
      expect((doc['paths'] as Map).containsKey('/mcp'), isTrue);
      expect(_op(doc, '/api/v1/capabilities', 'get')['operationId'], isNotEmpty);
      expect(_op(doc, '/mcp', 'post')['operationId'], isNotEmpty);
    });
    test('空注册表仍产出两条固定路径且无 tags', () {
      final doc = buildOpenApiDocument(ApiActionRegistry(), baseUrl: 'http://x');
      expect((doc['paths'] as Map).length, 2);
      expect(doc['tags'] as List, isEmpty);
    });
  });
}
