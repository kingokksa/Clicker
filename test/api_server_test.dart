import 'dart:convert';
import 'dart:io';

import 'package:clicker/services/api/api_action.dart';
import 'package:clicker/services/api/api_server.dart';
import 'package:clicker/services/api/api_token.dart';
import 'package:flutter_test/flutter_test.dart';

const int _port = 19876;

ApiActionRegistry _registry() => ApiActionRegistry()
  ..register(
    ApiAction(
      name: 'demo_echo',
      group: 'demo',
      summary: '回显',
      description: '把 text 参数原样返回',
      inputSchema: const {
        'type': 'object',
        'properties': {
          'text': {'type': 'string'},
        },
        'required': ['text'],
        'additionalProperties': false,
      },
      handler: (args) async => {'echo': args['text']},
    ),
  );

class _Res {
  _Res(this.status, this.body, this.headers);

  final int status;
  final dynamic body;
  final HttpHeaders headers;
}

Future<_Res> _req(
  String method,
  String path, {
  String? auth,
  Map<String, String>? headers,
  Object? body,
  String? rawBody,
}) async {
  final client = HttpClient();
  try {
    final req = await client.openUrl(
      method,
      Uri.parse('http://127.0.0.1:$_port$path'),
    );
    if (auth != null) req.headers.set(HttpHeaders.authorizationHeader, auth);
    headers?.forEach(req.headers.set);
    if (rawBody != null) {
      req.headers.contentType = ContentType.json;
      req.write(rawBody);
    } else if (body != null) {
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode(body));
    }
    final res = await req.close();
    final text = await res.transform(utf8.decoder).join();
    return _Res(
      res.statusCode,
      text.isEmpty ? null : jsonDecode(text),
      res.headers,
    );
  } finally {
    client.close(force: true);
  }
}

void main() {
  late ApiServer server;
  late String token;

  setUpAll(() async {
    token = ApiToken.current;
    server = ApiServer(registry: _registry(), port: _port);
    final ok = await server.start();
    expect(ok, isTrue, reason: '端口 $_port 被占用，无法启动测试服务');
  });

  tearDownAll(() async => server.stop());

  group('健康检查', () {
    test('/health 免鉴权', () async {
      final r = await _req('GET', '/health');
      expect(r.status, 200);
      expect(r.body['ok'], isTrue);
      expect(r.body['name'], 'clicker');
      expect(r.body['authRequired'], isTrue);
      expect(r.body['capabilities'], 1);
    });
    test('/ 同样免鉴权', () async {
      expect((await _req('GET', '/')).status, 200);
    });
  });

  group('鉴权', () {
    test('缺少令牌返回 401', () async {
      final r = await _req('GET', '/api/v1/capabilities');
      expect(r.status, 401);
      expect(r.body['error']['code'], 'unauthorized');
    });
    test('错误令牌返回 401', () async {
      final r = await _req('GET', '/api/v1/capabilities', auth: 'Bearer wrong');
      expect(r.status, 401);
    });
    test('Bearer 令牌通过', () async {
      final r = await _req('GET', '/api/v1/capabilities', auth: 'Bearer $token');
      expect(r.status, 200);
    });
    test('裸 Authorization 令牌通过', () async {
      final r = await _req('GET', '/api/v1/capabilities', auth: token);
      expect(r.status, 200);
    });
    test('X-Api-Token 通过', () async {
      final r = await _req('GET', '/api/v1/capabilities',
          headers: {'X-Api-Token': token});
      expect(r.status, 200);
    });
    test('token 查询参数通过', () async {
      final r = await _req('GET', '/api/v1/capabilities?token=$token');
      expect(r.status, 200);
    });
  });

  group('REST', () {
    test('capabilities 列出能力与分组', () async {
      final r = await _req('GET', '/api/v1/capabilities', auth: 'Bearer $token');
      expect(r.body['count'], 1);
      expect(r.body['groups'], ['demo']);
      expect(r.body['actions'][0]['name'], 'demo_echo');
    });
    test('POST 调用成功', () async {
      final r = await _req('POST', '/api/v1/demo_echo',
          auth: 'Bearer $token', body: {'text': 'hi'});
      expect(r.status, 200);
      expect(r.body['ok'], isTrue);
      expect(r.body['action'], 'demo_echo');
      expect(r.body['result']['echo'], 'hi');
    });
    test('GET 用查询参数调用', () async {
      final r = await _req('GET', '/api/v1/demo_echo?text=q',
          auth: 'Bearer $token');
      expect(r.status, 200);
      expect(r.body['result']['echo'], 'q');
    });
    test('缺少必填参数返回 400', () async {
      final r = await _req('POST', '/api/v1/demo_echo',
          auth: 'Bearer $token', body: <String, dynamic>{});
      expect(r.status, 400);
      expect(r.body['error']['code'], 'invalid_argument');
    });
    test('未知能力返回 404', () async {
      final r = await _req('POST', '/api/v1/nope', auth: 'Bearer $token');
      expect(r.status, 404);
      expect(r.body['error']['code'], 'not_found');
    });
    test('请求体不是 JSON 对象返回 400', () async {
      final r = await _req('POST', '/api/v1/demo_echo',
          auth: 'Bearer $token', rawBody: '[1,2]');
      expect(r.status, 400);
    });
  });

  group('OpenAPI 与 MCP', () {
    test('openapi.json 可获取', () async {
      final r = await _req('GET', '/openapi.json', auth: 'Bearer $token');
      expect(r.status, 200);
      expect(r.body['openapi'], '3.1.0');
      expect((r.body['paths'] as Map).containsKey('/api/v1/demo_echo'), isTrue);
    });
    test('MCP initialize', () async {
      final r = await _req('POST', '/mcp',
          auth: 'Bearer $token',
          body: {'jsonrpc': '2.0', 'id': 1, 'method': 'initialize'});
      expect(r.status, 200);
      expect(r.body['result']['serverInfo']['name'], 'clicker');
    });
    test('MCP tools/call', () async {
      final r = await _req('POST', '/mcp',
          auth: 'Bearer $token',
          body: {
            'jsonrpc': '2.0',
            'id': 1,
            'method': 'tools/call',
            'params': {
              'name': 'demo_echo',
              'arguments': {'text': 'yo'},
            },
          });
      expect(r.status, 200);
      expect(r.body['result']['structuredContent']['echo'], 'yo');
      expect(r.body['result']['isError'], isFalse);
    });
    test('MCP 端点拒绝 GET', () async {
      final r = await _req('GET', '/mcp', auth: 'Bearer $token');
      expect(r.status, 405);
      expect(r.body['error']['code'], 'method_not_allowed');
    });
    test('MCP 通知返回 202 且无响应体', () async {
      final r = await _req('POST', '/mcp',
          auth: 'Bearer $token',
          body: {'jsonrpc': '2.0', 'method': 'notifications/initialized'});
      expect(r.status, 202);
      expect(r.body, isNull);
    });
  });

  group('其它', () {
    test('未知路径返回 404', () async {
      final r = await _req('GET', '/nope', auth: 'Bearer $token');
      expect(r.status, 404);
      expect(r.body['error']['code'], 'not_found');
    });
    test('OPTIONS 预检返回 204 且带 CORS 头', () async {
      final r = await _req('OPTIONS', '/api/v1/demo_echo');
      expect(r.status, 204);
      expect(r.headers.value('access-control-allow-origin'), '*');
      expect(r.headers.value('access-control-allow-methods'), contains('POST'));
    });
    test('普通响应带 CORS 头', () async {
      final r = await _req('GET', '/health');
      expect(r.headers.value('access-control-allow-origin'), '*');
    });
    test('stop 后 isRunning 为 false，可重新启动', () async {
      final s = ApiServer(registry: _registry(), port: _port + 1);
      expect(await s.start(), isTrue);
      expect(s.isRunning, isTrue);
      await s.stop();
      expect(s.isRunning, isFalse);
    });
  });
}
