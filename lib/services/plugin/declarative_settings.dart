/// 声明式设置页 — 将 manifest 的 settings 声明渲染为 Fluent 设置界面。
/// 原生插件无需编写任何 UI 代码，只要在 manifest.json 里声明设置项，
/// 宿主自动渲染并持久化到插件存储。
library;

import 'package:fluent_ui/fluent_ui.dart';

import 'plugin_manifest.dart';
import 'plugin_storage.dart';
import 'plugin_manager.dart';

/// 构建原生插件的声明式页面
Widget buildDeclarativePluginPage(
    PluginDescriptor desc, CachedPluginStorage storage) {
  return _DeclarativePluginPage(desc: desc, storage: storage);
}

class _DeclarativePluginPage extends StatefulWidget {
  final PluginDescriptor desc;
  final CachedPluginStorage storage;
  const _DeclarativePluginPage({required this.desc, required this.storage});

  @override
  State<_DeclarativePluginPage> createState() => _DeclarativePluginPageState();
}

class _DeclarativePluginPageState extends State<_DeclarativePluginPage> {
  // 命令执行反馈（顶部 InfoBar，数秒后自动消失）
  String? _noticeMessage;
  bool _noticeIsError = false;

  void _showNotice(String message, {bool error = false}) {
    setState(() {
      _noticeMessage = message;
      _noticeIsError = error;
    });
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted && _noticeMessage == message) {
        setState(() => _noticeMessage = null);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final manifest = widget.desc.manifest;
    final isDark = FluentTheme.of(context).brightness == Brightness.dark;
    final settings = manifest.contributions.settings;
    final commands = manifest.contributions.commands;

    return ScaffoldPage.scrollable(
      padding: const EdgeInsets.all(20),
      children: [
        // 命令执行反馈
        if (_noticeMessage != null)
          InfoBar(
            title: Text(_noticeIsError ? '执行失败' : '命令已执行'),
            content: _noticeIsError ? Text(_noticeMessage!) : null,
            severity: _noticeIsError ? InfoBarSeverity.error : InfoBarSeverity.success,
            onClose: () => setState(() => _noticeMessage = null),
          ),
        if (_noticeMessage != null) const SizedBox(height: 12),

        // 标题
        Row(children: [
          Icon(FluentIcons.puzzle, size: 22, color: FluentTheme.of(context).accentColor),
          const SizedBox(width: 10),
          Text(manifest.name,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          const SizedBox(width: 12),
          Text('v${manifest.version}',
              style: TextStyle(
                  fontSize: 12,
                  color: isDark ? const Color(0xFF9090B0) : const Color(0xFF8A8A9A))),
        ]),
        if (manifest.description.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(manifest.description,
              style: TextStyle(
                  fontSize: 13,
                  color: isDark ? const Color(0xFF9090B0) : const Color(0xFF8A8A9A))),
        ],
        const SizedBox(height: 20),

        // 设置项
        if (settings.isNotEmpty) ...[
          _sectionTitle('设置', isDark),
          const SizedBox(height: 8),
          ...settings.map((def) => _buildSettingRow(def, isDark)),
          const SizedBox(height: 20),
        ],

        // 命令面板（触发声明的命令）
        if (commands.isNotEmpty) ...[
          _sectionTitle('可用命令', isDark),
          const SizedBox(height: 8),
          ...commands.map((cmd) {
            final commandId =
                cmd.id.contains('.') ? cmd.id : '${manifest.id}.${cmd.id}';
            return Card(
              padding: const EdgeInsets.all(12),
              child: Row(children: [
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(cmd.title, style: const TextStyle(fontSize: 13)),
                    Text(commandId,
                        style: TextStyle(
                            fontSize: 11,
                            color: isDark ? const Color(0xFF9090B0) : const Color(0xFF8A8A9A))),
                  ],
                )),
                FilledButton(
                  onPressed: () => _runCommand(commandId),
                  child: const Text('执行'),
                ),
              ]),
            );
          }),
          const SizedBox(height: 20),
        ],

        // 插件信息
        _sectionTitle('信息', isDark),
        const SizedBox(height: 8),
        Card(
          padding: const EdgeInsets.all(12),
          child: Column(children: [
            _infoRow('运行时', manifest.runtime == PluginRuntime.native ? '原生 (C/C++)' : 'Dart', isDark),
            _infoRow('作者', manifest.author, isDark),
            _infoRow('平台', manifest.platforms.join(', '), isDark),
            _infoRow('权限', manifest.permissions.isEmpty ? '无' : manifest.permissions.join(', '), isDark),
            _infoRow('激活方式', manifest.activationEvents.join(' / '), isDark),
          ]),
        ),
      ],
    );
  }

  Widget _sectionTitle(String text, bool isDark) => Row(children: [
        Text(text,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
      ]);

  Widget _infoRow(String label, String value, bool isDark) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(width: 80, child: Text(label,
          style: TextStyle(
              fontSize: 12,
              color: isDark ? const Color(0xFF9090B0) : const Color(0xFF8A8A9A)))),
      Expanded(child: Text(value, style: const TextStyle(fontSize: 12))),
    ]),
  );

  Widget _buildSettingRow(SettingDefinition def, bool isDark) {
    final value = widget.storage.getSync(def.key) ?? def.defaultValue;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Card(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(child: Text(def.title, style: const TextStyle(fontSize: 13))),
              _buildSettingControl(def, value, isDark),
            ]),
            if (def.description != null && def.description!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(def.description!,
                  style: TextStyle(
                      fontSize: 11,
                      color: isDark ? const Color(0xFF9090B0) : const Color(0xFF8A8A9A))),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSettingControl(SettingDefinition def, dynamic value, bool isDark) {
    switch (def.type) {
      case SettingType.toggle:
        return ToggleSwitch(
          checked: value == true,
          onChanged: (v) => _update(def, v),
        );
      case SettingType.number:
        return SizedBox(
          width: 120,
          child: TextBox(
            controller: TextEditingController(text: '$value'),
            placeholder: '${def.min ?? ''}~${def.max ?? ''}',
            onChanged: (text) {
              final n = double.tryParse(text);
              if (n != null) {
                var v = n;
                if (def.min != null) v = v.clamp(def.min!, def.max ?? v);
                if (def.max != null) v = v.clamp(def.min ?? v, def.max!);
                _update(def, def.precision == 0 ? v.round() : v);
              }
            },
          ),
        );
      case SettingType.slider:
        return SizedBox(
          width: 200,
          child: Slider(
            value: ((value as num?)?.toDouble() ?? def.min ?? 0)
                .clamp(def.min ?? 0, def.max ?? 100),
            min: def.min ?? 0,
            max: def.max ?? 100,
            divisions: def.max != null && def.min != null ? (def.max! - def.min!).round() : null,
            label: '$value${def.unit ?? ''}',
            onChanged: (v) => _update(def, def.precision == 0 ? v.round() : v),
          ),
        );
      case SettingType.text:
        return SizedBox(
          width: 220,
          child: TextBox(
            controller: TextEditingController(text: value?.toString() ?? ''),
            onChanged: (text) => _update(def, text),
          ),
        );
      case SettingType.dropdown:
        final current = value?.toString() ?? '';
        return ComboBox<String>(
          value: def.options.any((o) => '${o['value']}' == current)
              ? current
              : '${def.options.firstOrNull?['value'] ?? ''}',
          items: def.options
              .map((o) => ComboBoxItem(
                    value: '${o['value']}',
                    child: Text('${o['label'] ?? o['value']}'),
                  ))
              .toList(),
          onChanged: (v) {
            if (v != null) _update(def, v);
          },
        );
      case SettingType.hotkey:
        return SizedBox(
          width: 160,
          child: TextBox(
            controller: TextEditingController(text: value?.toString() ?? ''),
            placeholder: '点击后按键录制…',
            readOnly: true,
          ),
        );
      case SettingType.color:
        return SizedBox(
          width: 120,
          child: TextBox(
            controller: TextEditingController(text: value?.toString() ?? '#000000'),
            onChanged: (text) => _update(def, text),
          ),
        );
    }
  }

  void _update(SettingDefinition def, Object? value) {
    widget.storage.setSync(def.key, value);
    setState(() {});
  }

  Future<void> _runCommand(String commandId) async {
    final instance = widget.desc.nativeInstance;
    if (instance == null) return;
    final r = instance.executeCommand(commandId, {});
    if (!mounted) return;
    if (r.ok) {
      _showNotice('命令已执行');
    } else {
      _showNotice(r.error ?? '未知错误', error: true);
    }
  }
}
