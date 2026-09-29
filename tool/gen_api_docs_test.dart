import 'dart:convert';
import 'dart:io';

import 'package:clicker/services/api/api_capabilities.dart';
import 'package:clicker/services/app_state.dart';
import 'package:flutter_test/flutter_test.dart';

String _typeLabel(Map<String, dynamic> schema) {
  final type = schema['type'];
  if (type == 'array') {
    final items = schema['items'];
    if (items is Map && items['type'] != null) {
      return 'array<${items['type']}>';
    }
    return 'array';
  }
  return (type ?? 'any').toString();
}

String _constraints(Map<String, dynamic> schema) {
  final parts = <String>[];
  final enumValues = schema['enum'];
  if (enumValues is List && enumValues.isNotEmpty) {
    parts.add('可选值：${enumValues.map((e) => '`$e`').join(' / ')}');
  }
  if (schema.containsKey('default')) {
    parts.add('默认 `${jsonEncode(schema['default'])}`');
  }
  if (schema['minimum'] != null) parts.add('最小 ${schema['minimum']}');
  if (schema['maximum'] != null) parts.add('最大 ${schema['maximum']}');
  return parts.join('；');
}

String _cell(String raw) => raw.replaceAll('|', r'\|').replaceAll('\n', ' ');

void main() {
  test('生成外部接口文档', () {
    final registry = buildApiRegistry(AppState());
    final out = StringBuffer();

    out.writeln('# 外部接口（MCP + REST）');
    out.writeln();
    out.writeln('Clicker 连点器对外暴露的能力接口。所有能力共用一份注册表，'
        '同时以 **MCP**（给 AI 客户端）、**REST** 与 **OpenAPI 3.1** 三种形式提供。');
    out.writeln();
    out.writeln('共 **${registry.length}** 个能力，分为 ${registry.groups.length} 组：'
        '${registry.groups.map((g) => '`$g`').join('、')}。');
    out.writeln();
    out.writeln('## 快速开始');
    out.writeln();
    out.writeln('1. 打开软件 → 侧边栏 **外部接口** → 打开「启用服务」。');
    out.writeln('2. 复制页面上的**访问令牌**；如需换新令牌点「重新生成」。');
    out.writeln('3. 在页面「接入地址」里拿到局域网地址，例如 `http://192.168.1.10:9876`。');
    out.writeln();
    out.writeln('> 服务绑定 `0.0.0.0`，同一局域网的任何设备都能访问，**令牌是唯一防线**，'
        '请勿泄露，也不要把端口暴露到公网。');
    out.writeln();
    out.writeln('### 端点一览');
    out.writeln();
    out.writeln('| 端点 | 方法 | 鉴权 | 说明 |');
    out.writeln('|---|---|---|---|');
    out.writeln('| `/health` | GET | 否 | 存活检查，返回能力数量与版本 |');
    out.writeln('| `/api/v1/capabilities` | GET | 是 | 全部能力及其参数 schema |');
    out.writeln('| `/api/v1/<能力名>` | GET / POST | 是 | 调用某个能力 |');
    out.writeln('| `/openapi.json` | GET | 是 | OpenAPI 3.1 文档 |');
    out.writeln('| `/mcp` | POST | 是 | MCP JSON-RPC 2.0 端点 |');
    out.writeln();
    out.writeln('令牌可放在三处任意一处：`Authorization: Bearer <令牌>`、'
        '`Authorization: <令牌>`、`X-Api-Token: <令牌>`，或查询参数 `?token=<令牌>`。');
    out.writeln();
    out.writeln('## MCP 接入');
    out.writeln();
    out.writeln('把下面这段加进 AI 客户端的 MCP 配置（`url` 与令牌换成你自己的）：');
    out.writeln();
    out.writeln('```json');
    out.writeln(const JsonEncoder.withIndent('  ').convert({
      'mcpServers': {
        'clicker': {
          'type': 'http',
          'url': 'http://192.168.1.10:9876/mcp',
          'headers': {'Authorization': 'Bearer <令牌>'},
        },
      },
    }));
    out.writeln('```');
    out.writeln();
    out.writeln('支持的 MCP 方法：`initialize`、`ping`、`tools/list`、`tools/call`、'
        '`resources/list`、`prompts/list`。协议版本 `2025-06-18`。');
    out.writeln();
    out.writeln('调用某个能力（`tools/call`）：');
    out.writeln();
    out.writeln('```json');
    out.writeln(const JsonEncoder.withIndent('  ').convert({
      'jsonrpc': '2.0',
      'id': 1,
      'method': 'tools/call',
      'params': {
        'name': 'clicker_get_config',
        'arguments': <String, dynamic>{},
      },
    }));
    out.writeln('```');
    out.writeln();
    out.writeln('响应里 `result.structuredContent` 是能力的原始返回值，'
        '`result.content[0].text` 是它的 JSON 文本；失败时 `result.isError` 为 `true`，'
        '错误信息（含修复提示）在 `result.content[0].text` 里。');
    out.writeln();
    out.writeln('## REST 接入');
    out.writeln();
    out.writeln('```bash');
    out.writeln('# 查看全部能力');
    out.writeln('curl -H "Authorization: Bearer <令牌>" \\');
    out.writeln('  http://192.168.1.10:9876/api/v1/capabilities');
    out.writeln();
    out.writeln('# 调用能力（POST + JSON 对象）');
    out.writeln('curl -X POST -H "Authorization: Bearer <令牌>" \\');
    out.writeln('  -H "Content-Type: application/json" \\');
    out.writeln('  -d \'{"x": 100, "y": 200}\' \\');
    out.writeln('  http://192.168.1.10:9876/api/v1/clicker_click_at');
    out.writeln('```');
    out.writeln();
    out.writeln('GET 调用时参数直接写在查询串上（`/api/v1/vision_get_pixel?x=10&y=20`），'
        '字符串形式的数字与布尔会自动转换。');
    out.writeln();
    out.writeln('成功响应：`{"ok": true, "action": "<能力名>", "result": {...}}`。');
    out.writeln('失败响应：`{"ok": false, "action": "<能力名>", "error": {"code", "message", "hint"}}`。');
    out.writeln();
    out.writeln('| HTTP | error.code | 含义 |');
    out.writeln('|---|---|---|');
    out.writeln('| 400 | `invalid_argument` | 参数缺失或类型不对（`hint` 里有示例） |');
    out.writeln('| 401 | `unauthorized` | 缺少或无效的令牌 |');
    out.writeln('| 404 | `not_found` | 能力或路径不存在 |');
    out.writeln('| 405 | `method_not_allowed` | `/mcp` 只接受 POST |');
    out.writeln('| 409 | `conflict` | 当前状态不允许该操作 |');
    out.writeln('| 500 | `internal` | 内部错误 |');
    out.writeln('| 501 | `unsupported` | 当前平台不支持 |');
    out.writeln();
    out.writeln('## 能力清单');
    out.writeln();

    for (final group in registry.groups) {
      final actions = registry.all.where((a) => a.group == group).toList();
      out.writeln('### $group（${actions.length} 个）');
      out.writeln();
      for (final a in actions) {
        out.writeln('#### `${a.name}`');
        out.writeln();
        out.writeln(a.summary);
        out.writeln();
        if (a.description.isNotEmpty && a.description != a.summary) {
          out.writeln(a.description);
          out.writeln();
        }
        if (a.readOnly) {
          out.writeln('> 只读能力，不改变任何状态。');
          out.writeln();
        }
        final properties =
            (a.inputSchema['properties'] as Map?)?.cast<String, dynamic>() ??
                const <String, dynamic>{};
        final required =
            (a.inputSchema['required'] as List?)?.cast<String>() ?? const [];
        if (properties.isEmpty) {
          out.writeln('无参数。');
          out.writeln();
          continue;
        }
        out.writeln('| 参数 | 类型 | 必填 | 说明 |');
        out.writeln('|---|---|---|---|');
        for (final entry in properties.entries) {
          final schema = (entry.value as Map).cast<String, dynamic>();
          final notes = <String>[
            if (schema['description'] != null) '${schema['description']}',
            _constraints(schema),
          ].where((s) => s.isNotEmpty).join('；');
          out.writeln('| `${entry.key}` | ${_typeLabel(schema)} | '
              '${required.contains(entry.key) ? '是' : '否'} | ${_cell(notes)} |');
        }
        out.writeln();
      }
    }

    File('docs/外部接口.md').writeAsStringSync(out.toString());
    // ignore: avoid_print
    print('已生成 docs/外部接口.md：${registry.length} 个能力');
  });
}
