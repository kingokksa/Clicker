/// Settings page — hotkeys, theme, profiles. Fluent UI design.
library;

import 'package:fluent_ui/fluent_ui.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import '../../services/app_state.dart';
import '../../models/hotkey_config.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final theme = FluentTheme.of(context);
    final hotkeys = state.hotkeyConfig;
    final isWide = MediaQuery.of(context).size.width >= 700;

    final leftSections = <Widget>[
      _sectionCard(title: '快捷键', icon: FluentIcons.keyboard_classic, child: Column(children: [
        _buildHotkeyRow(context, state, theme, label: '开始 / 停止连点', value: hotkeys.startStopClicker, field: 'startStopClicker', icon: FluentIcons.touch),
        const Divider(style: DividerThemeData(horizontalMargin: EdgeInsets.zero)),
        _buildHotkeyRow(context, state, theme, label: '开始 / 停止录制', value: hotkeys.startStopRecording, field: 'startStopRecording', icon: FluentIcons.record2),
        const Divider(style: DividerThemeData(horizontalMargin: EdgeInsets.zero)),
        _buildHotkeyRow(context, state, theme, label: '紧急停止', value: hotkeys.emergencyStop, field: 'emergencyStop', icon: FluentIcons.warning),
        const Divider(style: DividerThemeData(horizontalMargin: EdgeInsets.zero)),
        _buildHotkeyRow(context, state, theme, label: '播放宏', value: hotkeys.playMacro, field: 'playMacro', icon: FluentIcons.play),
      ])),
    ];

    final rightSections = <Widget>[
      _sectionCard(title: '窗口', icon: FluentIcons.stack, child: _buildWindowOptions(state)),
      const SizedBox(height: 12),
      _sectionCard(title: '配置管理', icon: FluentIcons.save, child: _buildProfileSection(context, state)),
    ];

    return ScaffoldPage.scrollable(
      padding: const EdgeInsets.all(20),
      children: [
        if (isWide)
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: Column(children: leftSections)),
            const SizedBox(width: 12),
            Expanded(child: Column(children: rightSections)),
          ])
        else
          ...leftSections,
        if (!isWide) ...rightSections,
      ],
    );
  }

  Widget _sectionCard({required String title, required IconData icon, required Widget child, String? subtitle}) {
    return Builder(builder: (context) {
      final isDark = FluentTheme.of(context).brightness == Brightness.dark;
      final subtitleColor = isDark ? const Color(0xFF9090B0) : const Color(0xFF8A8A9A);
      return Card(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, size: 16),
            const SizedBox(width: 8),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
              if (subtitle != null) Text(subtitle, style: TextStyle(fontSize: 11, color: subtitleColor)),
            ])),
          ]),
          const SizedBox(height: 12),
          child,
        ]),
      );
    });
  }

  // ─── Hotkeys ──────────────────────────────────────────────

  Widget _buildHotkeyRow(BuildContext context, AppState state, FluentThemeData theme, {
    required String label, required String value, required String field, required IconData icon,
  }) {
    final accent = theme.accentColor;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(children: [
        Icon(icon, size: 16, color: accent.withOpacity(0.7)),
        const SizedBox(width: 10),
        Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
        GestureDetector(
          onTap: () => _pickHotkey(context, state, field, value),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: accent.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: accent.withOpacity(0.3)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(value.toUpperCase(), style: TextStyle(
                color: accent, fontWeight: FontWeight.w600, fontFamily: 'monospace', fontSize: 13,
              )),
              const SizedBox(width: 6),
              Icon(FluentIcons.edit, size: 14, color: accent.withOpacity(0.6)),
            ]),
          ),
        ),
      ]),
    );
  }

  void _pickHotkey(BuildContext context, AppState state, String field, String currentValue) {
    showDialog(context: context, builder: (ctx) => _HotkeyPickerDialog(
      currentValue: currentValue,
      onConfirm: (hotkeyStr) {
        final hk = state.hotkeyConfig;
        HotkeyConfig updated;
        switch (field) {
          case 'startStopClicker': updated = hk.copyWith(startStopClicker: hotkeyStr); break;
          case 'startStopRecording': updated = hk.copyWith(startStopRecording: hotkeyStr); break;
          case 'emergencyStop': updated = hk.copyWith(emergencyStop: hotkeyStr); break;
          case 'playMacro': updated = hk.copyWith(playMacro: hotkeyStr); break;
          default: return;
        }
        state.setHotkeyConfig(updated);
        Navigator.pop(ctx);
      },
    ));
  }

  // ─── Window ───────────────────────────────────────────────

  Widget _buildWindowOptions(AppState state) {
    return Column(children: [
      Row(children: [
        const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('关闭时最小化到托盘', style: TextStyle(fontSize: 13)),
          Text('关闭按钮将隐藏到系统托盘', style: TextStyle(fontSize: 11)),
        ])),
        ToggleSwitch(checked: state.minimizeToTray, onChanged: (v) => state.setMinimizeToTray(v)),
      ]),
      const Divider(style: DividerThemeData(horizontalMargin: EdgeInsets.zero)),
      Row(children: [
        const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('悬浮窗置顶', style: TextStyle(fontSize: 13)),
          Text('悬浮窗模式始终置顶显示', style: TextStyle(fontSize: 11)),
        ])),
        ToggleSwitch(checked: state.floatingAlwaysOnTop, onChanged: (v) {
          state.setFloatingAlwaysOnTop(v);
          windowManager.setAlwaysOnTop(v);
        }),
      ]),
    ]);
  }

  // ─── Profiles ─────────────────────────────────────────────

  Widget _buildProfileSection(BuildContext context, AppState state) {
    final profiles = state.profiles;
    final accent = FluentTheme.of(context).accentColor;
    return Column(children: [
      SizedBox(width: double.infinity, child: Button(
        onPressed: () => _saveNewProfile(context, state),
        child: const Text('+ 保存当前配置'),
      )),
      if (profiles.isNotEmpty) ...[
        const SizedBox(height: 12),
        ...profiles.map((name) => Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(children: [
            Icon(FluentIcons.bookmarks, size: 16, color: FluentTheme.of(context).accentColor.withOpacity(0.5)),
            const SizedBox(width: 8),
            Expanded(child: Text(name, style: const TextStyle(fontSize: 13))),
            HyperlinkButton(onPressed: () => state.loadProfile(name), child: const Text('加载')),
            HyperlinkButton(onPressed: () => state.deleteProfile(name), child: Text('删除', style: TextStyle(color: Colors.red))),
          ]),
        )),
      ],
      const SizedBox(height: 16),
      const Divider(),
      const SizedBox(height: 12),
      // Import / Export
      Row(children: [
        Expanded(child: FilledButton(
          onPressed: () => _exportConfig(context, state),
          style: ButtonStyle(backgroundColor: WidgetStatePropertyAll(accent.withOpacity(0.15))),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(FluentIcons.upload, size: 14, color: accent),
            const SizedBox(width: 6),
            Text('导出配置', style: TextStyle(color: accent, fontSize: 13)),
          ]),
        )),
        const SizedBox(width: 8),
        Expanded(child: FilledButton(
          onPressed: () => _importConfig(context, state),
          style: ButtonStyle(backgroundColor: WidgetStatePropertyAll(accent.withOpacity(0.15))),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(FluentIcons.download, size: 14, color: accent),
            const SizedBox(width: 6),
            Text('导入配置', style: TextStyle(color: accent, fontSize: 13)),
          ]),
        )),
      ]),
    ]);
  }

  Future<void> _exportConfig(BuildContext context, AppState state) async {
    final success = await state.exportConfig();
    if (context.mounted) {
      showDialog(context: context, builder: (_) => ContentDialog(
        title: Text(success ? '导出成功' : '导出失败'),
        content: Text(success ? '配置已导出到文件' : '导出失败，请重试'),
        actions: [FilledButton(onPressed: () => Navigator.pop(_), child: const Text('确定'))],
      ));
    }
  }

  Future<void> _importConfig(BuildContext context, AppState state) async {
    final result = await state.importConfig();
    if (context.mounted) {
      showDialog(context: context, builder: (_) => ContentDialog(
        title: Text(result.success ? '导入成功' : '导入失败'),
        content: Text(result.success ? '配置已导入，部分设置重启后生效' : '导入失败：${result.error}'),
        actions: [FilledButton(onPressed: () => Navigator.pop(_), child: const Text('确定'))],
      ));
    }
  }

  Future<void> _saveNewProfile(BuildContext context, AppState state) async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => ContentDialog(
        title: const Text('保存配置'),
        content: TextBox(controller: ctrl, autofocus: true, placeholder: '配置名称'),
        actions: [
          Button(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('保存')),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) await state.saveProfile(name);
  }
}

// ─── Hotkey Picker Dialog ────────────────────────────────────

class _HotkeyPickerDialog extends StatefulWidget {
  final String currentValue;
  final ValueChanged<String> onConfirm;
  const _HotkeyPickerDialog({required this.currentValue, required this.onConfirm});
  @override
  State<_HotkeyPickerDialog> createState() => _HotkeyPickerDialogState();
}

class _HotkeyPickerDialogState extends State<_HotkeyPickerDialog> {
  late List<String> _selectedModifiers;
  late String _selectedKey;

  @override
  void initState() {
    super.initState();
    final parsed = HotkeyConfig.splitHotkey(widget.currentValue);
    _selectedModifiers = parsed.mods;
    _selectedKey = parsed.key;
  }

  @override
  Widget build(BuildContext context) {
    final accent = FluentTheme.of(context).accentColor;
    final preview = HotkeyConfig.buildHotkey(_selectedModifiers, _selectedKey);
    return ContentDialog(
      title: const Text('选择快捷键'),
      content: SizedBox(width: 420, child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('选择修饰键和功能键', style: TextStyle(fontSize: 12, color: FluentTheme.of(context).brightness == Brightness.dark ? const Color(0xFF9090B0) : const Color(0xFF8A8A9A))),
        const SizedBox(height: 16),
        // Preview
        Center(child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          decoration: BoxDecoration(
            color: accent.withOpacity(0.1), borderRadius: BorderRadius.circular(12),
            border: Border.all(color: accent.withOpacity(0.4)),
          ),
          child: Text(preview.toUpperCase(), style: TextStyle(
            color: accent, fontWeight: FontWeight.w700, fontFamily: 'monospace', fontSize: 20, letterSpacing: 2,
          )),
        )),
        const SizedBox(height: 16),
        // Modifiers
        const Text('修饰键', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
        const SizedBox(height: 6),
        Wrap(spacing: 6, children: HotkeyConfig.modifiers.map((mod) {
          final isSelected = _selectedModifiers.contains(mod);
          return _buildChip(mod, isSelected, () {
            setState(() {
              if (isSelected) {
                _selectedModifiers.remove(mod);
              } else {
                _selectedModifiers.add(mod);
              }
            });
          });
        }).toList()),
        const SizedBox(height: 12),
        // Keys
        const Text('功能键', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
        const SizedBox(height: 6),
        Wrap(spacing: 4, runSpacing: 4, children: HotkeyConfig.keys.map((key) {
          final isSelected = _selectedKey == key;
          return _buildChip(key, isSelected, () => setState(() => _selectedKey = key));
        }).toList()),
      ])),
      actions: [FilledButton(onPressed: () => widget.onConfirm(preview), child: const Text('确认'))],
    );
  }

  Widget _buildChip(String label, bool selected, VoidCallback onTap) {
    return Builder(builder: (context) {
      final isDark = FluentTheme.of(context).brightness == Brightness.dark;
      final accent = FluentTheme.of(context).accentColor;
      final unselectedBg = isDark ? const Color(0xFF303050) : const Color(0xFFE8E8F0);
      final unselectedBorder = isDark ? const Color(0xFF404060) : const Color(0xFFD0D0D8);
      final unselectedText = isDark ? const Color(0xFFC0C0D8) : const Color(0xFF5A5A70);
      return MouseRegion(cursor: SystemMouseCursors.click, child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? accent.withOpacity(0.2) : unselectedBg,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: selected ? accent : unselectedBorder),
          ),
          child: Text(label, style: TextStyle(
            fontSize: 12, fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
            color: selected ? accent : unselectedText,
          )),
        ),
      ));
    });
  }
}
