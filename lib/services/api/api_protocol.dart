import 'dart:convert';

import 'api_action.dart';
import 'api_schema.dart';

const String mcpProtocolVersion = '2025-06-18';

class HttpResult {
  final int status;
  final Object? body;
  const HttpResult(this.status, this.body);
}

Map<String, dynamic> rpcError(dynamic id, int code, String message,
        {Object? data}) =>
    {
      'jsonrpc': '2.0',
      'id': id,
      'error': {
        'code': code,
        'message': message,
        if (data != null) 'data': data,
      },
    };

Map<String, dynamic> rpcResult(dynamic id, Object? result) =>
    {'jsonrpc': '2.0', 'id': id, 'result': result};

Future<Map<String, dynamic>?> handleRpcMessage(
    ApiActionRegistry registry, dynamic message) async {
  if (message is! Map) {
    return rpcError(null, -32600, 'Invalid Request');
  }
  final msg = message.cast<String, dynamic>();
  final id = msg['id'];
  final method = asString(msg['method']);

  if (method == null || method.isEmpty) {
    return rpcError(id, -32600, 'Invalid Request：缺少 method');
  }

  if (method.startsWith('notifications/')) return null;
  if (method == 'notifications/initialized') return null;

  switch (method) {
    case 'initialize':
      return rpcResult(id, {
        'protocolVersion': mcpProtocolVersion,
        'capabilities': {
          'tools': {'listChanged': false},
        },
        'serverInfo': {'name': 'clicker', 'version': apiVersion},
        'instructions': '本服务器暴露 Clicker 连点器的全部能力：'
            '连点控制与参数配置、宏录制与回放、视觉识别（找图/OCR/取色/截屏）、'
            '定时任务、配置档案、脚本执行。'
            '先调用 tools/list 查看全部工具；'
            '坐标类工具的返回值可直接作为另一些工具的入参。',
      });

    case 'ping':
      return rpcResult(id, const <String, dynamic>{});

    case 'tools/list':
      return rpcResult(id, {
        'tools': [for (final a in registry.all) a.toToolJson()],
      });

    case 'tools/call':
      final params = asMap(msg['params']);
      if (params == null) {
        return rpcError(id, -32602, 'Invalid params：缺少 params');
      }
      final name = asString(params['name']);
      if (name == null || name.isEmpty) {
        return rpcError(id, -32602, 'Invalid params：缺少工具名 name');
      }
      if (!registry.contains(name)) {
        return rpcError(id, -32602, '未知工具 "$name"',
            data: {'hint': '调用 tools/list 获取全部工具名'});
      }
      final args = asMap(params['arguments']) ?? <String, dynamic>{};
      return rpcResult(id, await _callTool(registry, name, args));

    case 'resources/list':
      return rpcResult(id, const {'resources': <dynamic>[]});

    case 'prompts/list':
      return rpcResult(id, const {'prompts': <dynamic>[]});

    default:
      return rpcError(id, -32601, 'Method not found: $method',
          data: {
            'supported': const [
              'initialize',
              'ping',
              'tools/list',
              'tools/call',
              'resources/list',
              'prompts/list',
            ]
          });
  }
}

Future<Map<String, dynamic>> _callTool(
    ApiActionRegistry registry, String name, Map<String, dynamic> args) async {
  try {
    final result = await registry.call(name, args);
    return {
      'content': [
        {'type': 'text', 'text': jsonEncode(result)}
      ],
      'structuredContent': result,
      'isError': false,
    };
  } on ApiError catch (e) {
    return {
      'content': [
        {
          'type': 'text',
          'text': e.hint == null ? e.message : '${e.message}\n提示：${e.hint}',
        }
      ],
      'isError': true,
    };
  } catch (e) {
    return {
      'content': [
        {'type': 'text', 'text': '执行失败：$e'}
      ],
      'isError': true,
    };
  }
}

Future<HttpResult> handleMcpHttp(
    ApiActionRegistry registry, String body) async {
  dynamic decoded;
  try {
    decoded = jsonDecode(body);
  } catch (_) {
    return HttpResult(200, rpcError(null, -32700, 'Parse error'));
  }

  if (decoded is List) {
    final out = <Map<String, dynamic>>[];
    for (final item in decoded) {
      final r = await handleRpcMessage(registry, item);
      if (r != null) out.add(r);
    }
    if (out.isEmpty) return const HttpResult(202, null);
    return HttpResult(200, out);
  }

  final single = await handleRpcMessage(registry, decoded);
  if (single == null) return const HttpResult(202, null);
  return HttpResult(200, single);
}

Future<HttpResult> handleRestCall(ApiActionRegistry registry, String name,
    Map<String, dynamic> args) async {
  if (!registry.contains(name)) {
    return HttpResult(404, {
      'ok': false,
      'error': ApiError.notFound('未知能力 "$name"',
              hint: 'GET /api/v1/capabilities 可获取全部能力')
          .toJson(),
    });
  }
  try {
    final result = await registry.call(name, args);
    return HttpResult(200, {'ok': true, 'action': name, 'result': result});
  } on ApiError catch (e) {
    final status = switch (e.code) {
      'not_found' => 404,
      'conflict' => 409,
      'unsupported' => 501,
      _ => 400,
    };
    return HttpResult(status, {'ok': false, 'action': name, 'error': e.toJson()});
  } catch (e) {
    return HttpResult(500, {
      'ok': false,
      'action': name,
      'error': {'code': 'internal', 'message': e.toString()},
    });
  }
}
