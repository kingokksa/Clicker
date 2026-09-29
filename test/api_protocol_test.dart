import 'dart:convert';

import 'package:clicker/services/api/api_action.dart';
import 'package:clicker/services/api/api_protocol.dart';
import 'package:clicker/services/api/api_schema.dart';
import 'package:flutter_test/flutter_test.dart';

ApiAction _action({
  String name = 'demo_run',
  String group = 'demo',
  Map<String, dynamic>? inputSchema,
  bool readOnly = false,
  ApiHandler? handler,
}) =>
    ApiAction(
      name: name,
      group: group,
      summary: '演示',
      description: '演示能力',
      readOnly: readOnly,
      inputSchema: inputSchema ??
          const {
            'type': 'object',
            'properties': <String, dynamic>{},
            'additionalProperties': false,
          },
      handler: handler ?? (args) async => {'ok': true},
    );

ApiActionRegistry _registry({ApiHandler? handler}) => ApiActionRegistry()
  ..register(_action(handler: handler));

Map<String, dynamic> _error(Map<String, dynamic>? r) =>
    (r!['error'] as Map).cast<String, dynamic>();

Map<String, dynamic> _result(Map<String, dynamic>? r) =>
    (r!['result'] as Map).cast<String, dynamic>();

Map<String, dynamic> _call(String method, [Map<String, dynamic>? extra]) => {
      'jsonrpc': '2.0',
      'id': 1,
      'method': method,
      ...?extra,
    };

void main() {
  test('协议版本固定', () => expect(mcpProtocolVersion, '2025-06-18'));

  group('rpcError / rpcResult', () {
    test('rpcError 基本形状', () {
      final e = rpcError(1, -32601, 'nope');
      expect(e['jsonrpc'], '2.0');
      expect(e['id'], 1);
      expect(_error(e)['code'], -32601);
      expect(_error(e)['message'], 'nope');
      expect(_error(e).containsKey('data'), isFalse);
    });
    test('rpcError 带 data', () {
      expect(_error(rpcError(1, -1, 'm', data: {'hint': 'h'}))['data'], {'hint': 'h'});
    });
    test('rpcResult 基本形状', () {
      final r = rpcResult(2, {'a': 1});
      expect(r['jsonrpc'], '2.0');
      expect(r['id'], 2);
      expect(r['result'], {'a': 1});
    });
  });

  group('handleRpcMessage 请求校验', () {
    test('非对象消息返回 Invalid Request', () async {
      final r = await handleRpcMessage(_registry(), 'nope');
      expect(_error(r)['code'], -32600);
    });
    test('缺少 method 返回 Invalid Request', () async {
      final r = await handleRpcMessage(_registry(), {'jsonrpc': '2.0', 'id': 1});
      expect(_error(r)['code'], -32600);
    });
    test('通知不产生响应', () async {
      expect(
        await handleRpcMessage(
            _registry(), _call('notifications/initialized')),
        isNull,
      );
    });
  });

  group('handleRpcMessage 方法', () {
    test('initialize 返回协议版本与服务器信息', () async {
      final r = _result(await handleRpcMessage(_registry(), _call('initialize')));
      expect(r['protocolVersion'], mcpProtocolVersion);
      expect(r['serverInfo']['name'], 'clicker');
      expect(r['serverInfo']['version'], apiVersion);
      expect(r['capabilities']['tools']['listChanged'], isFalse);
      expect(r['instructions'], isNotEmpty);
    });
    test('ping 返回空对象', () async {
      expect(_result(await handleRpcMessage(_registry(), _call('ping'))), isEmpty);
    });
    test('tools/list 暴露全部工具', () async {
      final r = _result(await handleRpcMessage(_registry(), _call('tools/list')));
      final tools = r['tools'] as List;
      expect(tools.length, 1);
      expect(tools.first['name'], 'demo_run');
      expect(tools.first['inputSchema'], isA<Map>());
    });
    test('resources/list 返回空列表', () async {
      final r = _result(
          await handleRpcMessage(_registry(), _call('resources/list')));
      expect(r['resources'], isEmpty);
    });
    test('prompts/list 返回空列表', () async {
      final r =
          _result(await handleRpcMessage(_registry(), _call('prompts/list')));
      expect(r['prompts'], isEmpty);
    });
    test('未知方法返回 -32601 并列出支持的方法', () async {
      final r = await handleRpcMessage(_registry(), _call('nope/xyz'));
      expect(_error(r)['code'], -32601);
      expect(_error(r)['data']['supported'], contains('tools/call'));
    });
  });

  group('handleRpcMessage tools/call', () {
    test('缺少 params', () async {
      final r = await handleRpcMessage(_registry(), _call('tools/call'));
      expect(_error(r)['code'], -32602);
    });
    test('缺少工具名', () async {
      final r = await handleRpcMessage(
          _registry(), _call('tools/call', {'params': <String, dynamic>{}}));
      expect(_error(r)['code'], -32602);
    });
    test('未知工具提示调用 tools/list', () async {
      final r = await handleRpcMessage(_registry(),
          _call('tools/call', {'params': {'name': 'nope'}}));
      expect(_error(r)['code'], -32602);
      expect(_error(r)['data']['hint'], contains('tools/list'));
    });
    test('成功时返回文本内容与结构化内容', () async {
      final r = _result(await handleRpcMessage(_registry(),
          _call('tools/call', {'params': {'name': 'demo_run'}})));
      expect(r['isError'], isFalse);
      expect(r['structuredContent'], {'ok': true});
      expect(r['content'][0]['type'], 'text');
      expect(r['content'][0]['text'], jsonEncode({'ok': true}));
    });
    test('arguments 省略时按空参数调用', () async {
      final r = _result(await handleRpcMessage(_registry(),
          _call('tools/call', {'params': {'name': 'demo_run'}})));
      expect(r['isError'], isFalse);
    });
    test('业务错误以 isError 返回并附带提示', () async {
      final r = _result(await handleRpcMessage(_registry(),
          _call('tools/call', {'params': {'name': 'demo_run'}})));
      expect(r['isError'], isFalse);
      final bad = _result(await handleRpcMessage(
          _registry(handler: (args) async => throw ApiError.notFound('没找到', hint: '看看清单')),
          _call('tools/call', {'params': {'name': 'demo_run'}})));
      expect(bad['isError'], isTrue);
      expect(bad['content'][0]['text'], contains('没找到'));
      expect(bad['content'][0]['text'], contains('看看清单'));
    });
    test('未知异常以 isError 返回', () async {
      final r = _result(await handleRpcMessage(
          _registry(handler: (args) async => throw StateError('boom')),
          _call('tools/call', {'params': {'name': 'demo_run'}})));
      expect(r['isError'], isTrue);
      expect(r['content'][0]['text'], contains('执行失败'));
    });
  });

  group('handleMcpHttp', () {
    test('非法 JSON 返回 -32700', () async {
      final r = await handleMcpHttp(_registry(), '{oops');
      expect(r.status, 200);
      expect(_error((r.body as Map).cast<String, dynamic>())['code'], -32700);
    });
    test('单个请求返回 200', () async {
      final r = await handleMcpHttp(_registry(), jsonEncode(_call('ping')));
      expect(r.status, 200);
    });
    test('单个通知返回 202 且无 body', () async {
      final r = await handleMcpHttp(
          _registry(), jsonEncode(_call('notifications/initialized')));
      expect(r.status, 202);
      expect(r.body, isNull);
    });
    test('批量请求逐条响应', () async {
      final r = await handleMcpHttp(
        _registry(),
        jsonEncode([
          _call('ping'),
          {'jsonrpc': '2.0', 'method': 'notifications/initialized'},
        ]),
      );
      expect(r.status, 200);
      expect((r.body as List).length, 1);
    });
    test('批量全为通知返回 202', () async {
      final r = await handleMcpHttp(
        _registry(),
        jsonEncode([
          {'jsonrpc': '2.0', 'method': 'notifications/initialized'},
        ]),
      );
      expect(r.status, 202);
      expect(r.body, isNull);
    });
  });

  group('handleRestCall', () {
    test('未知能力返回 404', () async {
      final r = await handleRestCall(_registry(), 'nope', const {});
      expect(r.status, 404);
      expect((r.body as Map)['ok'], isFalse);
      expect((r.body as Map)['error']['code'], 'not_found');
    });
    test('成功返回 200 与结果', () async {
      final r = await handleRestCall(_registry(), 'demo_run', const {});
      expect(r.status, 200);
      expect((r.body as Map)['ok'], isTrue);
      expect((r.body as Map)['action'], 'demo_run');
      expect((r.body as Map)['result'], {'ok': true});
    });
    test('not_found 映射 404', () async {
      final r = await handleRestCall(
          _registry(handler: (args) async => throw ApiError.notFound('x')),
          'demo_run',
          const {});
      expect(r.status, 404);
    });
    test('conflict 映射 409', () async {
      final r = await handleRestCall(
          _registry(handler: (args) async => throw ApiError.conflict('x')),
          'demo_run',
          const {});
      expect(r.status, 409);
    });
    test('unsupported 映射 501', () async {
      final r = await handleRestCall(
          _registry(handler: (args) async => throw ApiError.unsupported('x')),
          'demo_run',
          const {});
      expect(r.status, 501);
    });
    test('invalid_argument 映射 400', () async {
      final r = await handleRestCall(
          _registry(handler: (args) async => throw ApiError.invalidArgument('x')),
          'demo_run',
          const {});
      expect(r.status, 400);
    });
    test('未知异常映射 500', () async {
      final r = await handleRestCall(
          _registry(handler: (args) async => throw StateError('boom')),
          'demo_run',
          const {});
      expect(r.status, 500);
      expect((r.body as Map)['error']['code'], 'internal');
    });
  });
}
