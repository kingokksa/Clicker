/// Mobile settings page — Material Design theme, sound, profiles, import/export.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../../services/mobile_app_state.dart';
import '../../models/clicker_config.dart' show SoundConfig;

class MobileSettingsPage extends StatefulWidget {
  const MobileSettingsPage({super.key});

  @override
  State<MobileSettingsPage> createState() => _MobileSettingsPageState();
}

class _MobileSettingsPageState extends State<MobileSettingsPage> {
  String _appVersion = '';

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    final info = await PackageInfo.fromPlatform();
    if (mounted) setState(() => _appVersion = info.version);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<MobileAppState>();
    final isDark = state.themeMode == 'dark';
    final accent = state.accentColor;
    final config = state.clickerConfig;

    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
        centerTitle: true,
        backgroundColor: isDark ? const Color(0xFF1A1A2E) : accent.withValues(alpha: 0.1),
        foregroundColor: isDark ? Colors.white : accent,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          // ─── Appearance ────────────────────────────────────
          _sectionTitle('外观', isDark),
          Card(
            color: isDark ? const Color(0xFF22223A) : Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Column(children: [
              SwitchListTile(
                title: Text('深色模式', style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
                value: isDark,
                activeThumbColor: accent,
                onChanged: (v) => state.setThemeMode(v ? 'dark' : 'light'),
              ),
              const Divider(height: 1),
              ListTile(
                title: Text('主题色', style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  _colorDot(accent),
                  const SizedBox(width: 4),
                  const Icon(Icons.chevron_right, size: 18),
                ]),
                onTap: () => _showColorPicker(state, isDark, accent),
              ),
              const Divider(height: 1),
              SwitchListTile(
                title: Text('动画效果', style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
                value: state.uiAnimations,
                activeThumbColor: accent,
                onChanged: (v) => state.setUiAnimations(v),
              ),
            ]),
          ),
          const SizedBox(height: 16),

          // ─── Sound ─────────────────────────────────────────
          _sectionTitle('音效', isDark),
          Card(
            color: isDark ? const Color(0xFF22223A) : Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Column(children: [
              SwitchListTile(
                title: Text('音效反馈', style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
                value: config.soundFeedbackEnabled,
                activeThumbColor: accent,
                onChanged: (v) => state.setClickerConfig(config.copyWith(soundFeedbackEnabled: v)),
              ),
              if (config.soundFeedbackEnabled) ...[
                const Divider(height: 1),
                _soundTile('点击音效', config.soundFeedbackClick, isDark, (s) =>
                    state.setClickerConfig(config.copyWith(soundFeedbackClick: s))),
                const Divider(height: 1),
                _soundTile('按键音效', config.soundFeedbackKey, isDark, (s) =>
                    state.setClickerConfig(config.copyWith(soundFeedbackKey: s))),
                const Divider(height: 1),
                _soundTile('宏音效', config.soundFeedbackMacro, isDark, (s) =>
                    state.setClickerConfig(config.copyWith(soundFeedbackMacro: s))),
              ],
            ]),
          ),
          const SizedBox(height: 16),

          // ─── Profiles ──────────────────────────────────────
          _sectionTitle('配置方案', isDark),
          Card(
            color: isDark ? const Color(0xFF22223A) : Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Column(children: [
              ListTile(
                title: Text('保存当前配置', style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
                leading: Icon(Icons.save, color: accent, size: 20),
                onTap: () => _saveProfile(state, isDark),
              ),
              if (state.profiles.isNotEmpty) const Divider(height: 1),
              ...state.profiles.map((p) => ListTile(
                title: Text(p, style: TextStyle(color: isDark ? Colors.white70 : Colors.black87)),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(icon: Icon(Icons.play_arrow, size: 18, color: accent),
                      onPressed: () => state.loadProfile(p)),
                  IconButton(icon: const Icon(Icons.delete, size: 18, color: Colors.red),
                      onPressed: () => state.deleteProfile(p)),
                ]),
              )),
            ]),
          ),
          const SizedBox(height: 16),

          // ─── Data ──────────────────────────────────────────
          _sectionTitle('数据', isDark),
          Card(
            color: isDark ? const Color(0xFF22223A) : Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Column(children: [
              ListTile(
                title: Text('导出配置', style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
                leading: Icon(Icons.upload_file, color: accent, size: 20),
                onTap: () async {
                  final ok = await state.exportConfig();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(ok ? '导出成功' : '导出失败')),
                    );
                  }
                },
              ),
              const Divider(height: 1),
              ListTile(
                title: Text('导入配置', style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
                leading: Icon(Icons.download, color: accent, size: 20),
                onTap: () async {
                  final result = await state.importConfig();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(result.success ? '导入成功' : '导入失败')),
                    );
                  }
                },
              ),
            ]),
          ),
          const SizedBox(height: 16),

          // ─── About ─────────────────────────────────────────
          _sectionTitle('关于', isDark),
          Card(
            color: isDark ? const Color(0xFF22223A) : Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: ListTile(
              title: Text('版本', style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
              trailing: Text(_appVersion, style: TextStyle(color: isDark ? Colors.grey : Colors.black54)),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(title,
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
              color: isDark ? const Color(0xFF9090B0) : const Color(0xFF6A6A80))),
    );
  }

  Widget _colorDot(Color color) {
    return Container(width: 18, height: 18, decoration: BoxDecoration(
      color: color, shape: BoxShape.circle,
      border: Border.all(color: Colors.white, width: 2),
    ));
  }

  void _showColorPicker(MobileAppState state, bool isDark, Color current) {
    final colors = [
      const Color(0xFF7C4DFF), const Color(0xFF536DFE),
      const Color(0xFF448AFF), const Color(0xFF40C4FF),
      const Color(0xFF18FFFF), const Color(0xFF64FFDA),
      const Color(0xFF69F0AE), const Color(0xFFB2FF59),
      const Color(0xFFFFD740), const Color(0xFFFFAB40),
      const Color(0xFFFF6E40), const Color(0xFFFF5252),
      const Color(0xFFFF4081), const Color(0xFFE040FB),
    ];

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('选择主题色'),
        content: Wrap(spacing: 8, runSpacing: 8, children: colors.map((c) =>
          GestureDetector(
            onTap: () {
              state.setAccentColor(c);
              Navigator.pop(ctx);
            },
            child: Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: c, shape: BoxShape.circle,
                border: c == current ? Border.all(color: Colors.white, width: 3) : null,
              ),
            ),
          ),
        ).toList()),
      ),
    );
  }

  Widget _soundTile(String label, SoundConfig sound, bool isDark,
      ValueChanged<SoundConfig> onChanged) {
    return ExpansionTile(
      title: Text(label, style: TextStyle(fontSize: 14, color: isDark ? Colors.white : Colors.black87)),
      children: [
        SwitchListTile(
          title: const Text('开始音效', style: TextStyle(fontSize: 13)),
          value: sound.startEnabled,
          onChanged: (v) => onChanged(sound.copyWith(startEnabled: v)),
        ),
        SwitchListTile(
          title: const Text('结束音效', style: TextStyle(fontSize: 13)),
          value: sound.endEnabled,
          onChanged: (v) => onChanged(sound.copyWith(endEnabled: v)),
        ),
      ],
    );
  }

  void _saveProfile(MobileAppState state, bool isDark) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('保存配置方案'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: '方案名称'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
            onPressed: () {
              if (ctrl.text.isNotEmpty) {
                state.saveProfile(ctrl.text);
              }
              Navigator.pop(ctx);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }
}
