import 'api_action.dart';

Map<String, dynamic> buildOpenApiDocument(
  ApiActionRegistry registry, {
  required String baseUrl,
}) {
  final paths = <String, dynamic>{};

  for (final a in registry.all) {
    paths['/api/v1/${a.name}'] = {
      'post': {
        'tags': [a.group],
        'operationId': a.name,
        'summary': a.summary,
        'description': a.description,
        'requestBody': {
          'required': true,
          'content': {
            'application/json': {'schema': a.inputSchema},
          },
        },
        'responses': {
          '200': {
            'description': '成功',
            'content': {
              'application/json': {
                'schema': {
                  'type': 'object',
                  'properties': {
                    'ok': {'type': 'boolean'},
                    'action': {'type': 'string'},
                    'result': {'type': 'object'},
                  },
                  'required': ['ok'],
                },
              },
            },
          },
          '400': {'description': '参数错误'},
          '404': {'description': '未知能力'},
          '409': {'description': '当前状态不允许此操作'},
        },
      },
    };
  }

  paths['/api/v1/capabilities'] = {
    'get': {
      'tags': ['system'],
      'operationId': 'listCapabilities',
      'summary': '列出全部能力及其参数 schema',
      'responses': {
        '200': {'description': '成功'},
      },
    },
  };

  paths['/mcp'] = {
    'post': {
      'tags': ['system'],
      'operationId': 'mcp',
      'summary': 'MCP (Model Context Protocol) JSON-RPC 2.0 端点',
      'description': '供 AI 客户端直接接入，支持 initialize、ping、'
          'tools/list、tools/call 等方法。',
      'responses': {
        '200': {'description': '成功'},
        '202': {'description': '通知已接收，无响应体'},
      },
    },
  };

  return {
    'openapi': '3.1.0',
    'info': {
      'title': 'Clicker 外部接口',
      'version': apiVersion,
      'description': '把 Clicker 连点器的能力暴露给外部程序与 AI。'
          'AI 客户端优先使用 /mcp（MCP 协议）；普通脚本使用 '
          'POST /api/v1/<能力名>。所有请求都需要 '
          'Authorization: Bearer <token>。',
    },
    'servers': [
      {'url': baseUrl},
    ],
    'tags': [
      for (final g in registry.groups) {'name': g},
    ],
    'components': {
      'securitySchemes': {
        'bearerAuth': {
          'type': 'http',
          'scheme': 'bearer',
          'description': '令牌可在软件「外部接口」设置页查看或重新生成',
        },
      },
    },
    'security': [
      {'bearerAuth': <String>[]},
    ],
    'paths': paths,
  };
}
