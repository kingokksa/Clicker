import 'dart:convert';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../services/api/api_server.dart';
import '../../services/api/api_token.dart';
import '../../services/app_state.dart';

class ApiPage extends StatefulWidget {
  const ApiPage({super.key});

  @override
  State<ApiPage> createState() => _ApiPageState();
}

class _ApiPageState extends State<ApiPage> {
  late final TextEditingController _portController;
  String _token = ApiToken.current;
  List<String> _lan = const [];
  bool _showToken = false;
  String _notice = '';

  @override
  void initState() {
    super.initState();
    _portController = TextEditingController(
        text: '${context.read<AppState>().remoteControlPort}');
    ApiServer.lanAddresses().then((v) {
      if (mounted) setState(() => _lan = v);
    });
  }

  @override
  void dispose() {
    _portController.dispose();
    super.dispose();
  }

  void _copy(String label, String text) {
    Clipboard.setData(ClipboardData(text: text));
    setState(() => _notice = '$label 已复制');
  }

  void _applyPort() {
    final port = int.tryParse(_portController.text.trim());
    if (port == null || port < 1 || port > 65535) {
      setState(() => _notice = '端口必须是 1-65535 之间的整数');
      return;
    }
    context.read<AppState>().setRemoteControlPort(port);
    setState(() => _notice = '端口已改为 $port');
  }

  void _regenerate() {
    setState(() {
      _token = ApiToken.regenerate();
      _notice = '令牌已重新生成，旧令牌立即失效';
    });
  }

  String get _masked => _token.length <= 8
      ? _token
      : '${_token.substring(0, 8)}${List.filled(24, '•').join()}';

  String _mcpConfig(String base) =>
      const JsonEncoder.withIndent('  ').convert({
        'mcpServers': {
          'clicker': {
            'type': 'http',
            'url': '$base/mcp',
            'headers': {'Authorization': 'Bearer $_token'},
          }
        }
      });

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final enabled = state.clickerConfig.remoteControlEnabled;
    final running = state.isRemoteControlRunning;
    final port = state.remoteControlPort;
    final host = _lan.isEmpty ? '127.0.0.1' : _lan.first;
    final base = 'http://$host:$port';
    final mcp = _mcpConfig(base);

    return ScaffoldPage.scrollable(
      padding: const EdgeInsets.all(20),
      children: [
        Row(children: [
          Icon(FluentIcons.developer_tools, size: 20, color: state.accentColor),
          const SizedBox(width: 10),
          const Text('外部接口',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 6),
        _subtitle(context,
            '把连点、宏、视觉识别、定时任务、配置档案、脚本六类能力暴露给外部程序与 AI。AI 走 MCP，普通脚本走 REST。'),
        const SizedBox(height: 16),
        _card('服务', FluentIcons.play, _buildServer(state, enabled, running, port)),
        const SizedBox(height: 12),
        _card('访问令牌', FluentIcons.keyboard_classic, _buildToken()),
        const SizedBox(height: 12),
        _card('接入地址', FluentIcons.send, _buildEndpoints(base, port)),
        const SizedBox(height: 12),
        _card('MCP 客户端配置', FluentIcons.chat_bot, _buildMcp(mcp, base)),
        const SizedBox(height: 12),
        _card('能力清单', FluentIcons.stack, _buildCapabilities(state, base)),
        if (_notice.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text(_notice,
              style: TextStyle(fontSize: 12, color: state.accentColor)),
        ],
      ],
    );
  }

  Widget _buildServer(AppState state, bool enabled, bool running, int port) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        ToggleSwitch(
          checked: enabled,
          onChanged: (v) => state.setRemoteControlEnabled(v),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            enabled ? '已启用，软件启动时会自动拉起服务' : '已关闭，外部程序与 AI 无法访问',
            style: const TextStyle(fontSize: 13),
          ),
        ),
      ]),
      const SizedBox(height: 12),
      Row(children: [
        SizedBox(
          width: 110,
          child: TextBox(controller: _portController, placeholder: '9876'),
        ),
        const SizedBox(width: 10),
        Button(onPressed: _applyPort, child: const Text('应用端口')),
        const SizedBox(width: 12),
        Text(running ? '运行中 · 0.0.0.0:$port' : '未运行',
            style: TextStyle(
                fontSize: 12,
                color: running ? state.accentColor : const Color(0xFF9090B0))),
      ]),
      const SizedBox(height: 10),
      _subtitle(context,
          '局域网地址：${_lan.isEmpty ? '未检测到' : _lan.map((a) => 'http://$a:$port').join('   ')}'),
      _subtitle(context,
          '服务绑定 0.0.0.0，同一局域网内任何设备都能访问，请务必保管好令牌。'),
    ]);
  }

  Widget _buildToken() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(
          child: SelectableText(
            _showToken ? _token : _masked,
            style: const TextStyle(fontSize: 12, fontFamily: 'Consolas'),
          ),
        ),
        IconButton(
          icon: Icon(
              _showToken ? FluentIcons.hide : FluentIcons.view,
              size: 14),
          onPressed: () => setState(() => _showToken = !_showToken),
        ),
        IconButton(
          icon: const Icon(FluentIcons.copy, size: 14),
          onPressed: () => _copy('令牌', _token),
        ),
        const SizedBox(width: 6),
        Button(onPressed: _regenerate, child: const Text('重新生成')),
      ]),
      const SizedBox(height: 6),
      _subtitle(context,
          '所有请求都要带 Authorization: Bearer <令牌>；重新生成后旧令牌立即失效，需同步更新客户端。'),
    ]);
  }

  Widget _buildEndpoints(String base, int port) {
    final rows = <List<String>>[
      ['MCP 端点', '$base/mcp'],
      ['REST 基址', '$base/api/v1'],
      ['能力清单', '$base/api/v1/capabilities'],
      ['OpenAPI', '$base/openapi.json'],
      ['健康检查', '$base/health'],
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (final r in rows) ...[
        Row(children: [
          SizedBox(
            width: 84,
            child: Text(r[0], style: const TextStyle(fontSize: 12)),
          ),
          Expanded(
            child: SelectableText(r[1],
                style: const TextStyle(fontSize: 12, fontFamily: 'Consolas')),
          ),
          IconButton(
            icon: const Icon(FluentIcons.copy, size: 14),
            onPressed: () => _copy(r[0], r[1]),
          ),
        ]),
      ],
      const SizedBox(height: 4),
      _subtitle(context, 'REST 调用方式：POST $base/api/v1/<能力名>，请求体是 JSON 参数对象。'),
    ]);
  }

  Widget _buildMcp(String mcp, String base) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _subtitle(context, '把下面这段贴进支持 Streamable HTTP 的 MCP 客户端配置里即可接入。'),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0x14000000),
          borderRadius: BorderRadius.circular(6),
        ),
        child: SelectableText(mcp,
            style: const TextStyle(fontSize: 12, fontFamily: 'Consolas')),
      ),
      const SizedBox(height: 8),
      Row(children: [
        Button(
            onPressed: () => _copy('MCP 配置', mcp), child: const Text('复制配置')),
        const SizedBox(width: 8),
        Button(
            onPressed: () => _copy('端点', '$base/mcp'),
            child: const Text('只复制端点')),
      ]),
    ]);
  }

  Widget _buildCapabilities(AppState state, String base) {
    final registry = state.apiRegistry;
    final groups = registry.groups;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('共 ${registry.length} 个能力，分 ${groups.length} 组',
          style: const TextStyle(fontSize: 13)),
      const SizedBox(height: 10),
      for (final g in groups) ...[
        Text(g,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final a in registry.all.where((a) => a.group == g))
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0x14000000),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(a.name, style: const TextStyle(fontSize: 11)),
              ),
          ],
        ),
        const SizedBox(height: 10),
      ],
      _subtitle(context,
          '完整参数说明可调用 system_capabilities，或访问 $base/api/v1/capabilities。'),
    ]);
  }

  Widget _card(String title, IconData icon, Widget child) {
    return Card(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 16),
          const SizedBox(width: 8),
          Text(title,
              style:
                  const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        ]),
        const SizedBox(height: 12),
        child,
      ]),
    );
  }

  Widget _subtitle(BuildContext context, String text) {
    final isDark = FluentTheme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text,
          style: TextStyle(
              fontSize: 11,
              color: isDark ? const Color(0xFF9090B0) : const Color(0xFF8A8A9A))),
    );
  }
}
