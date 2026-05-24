/// Plugin & feature management page — toggle all features.
/// Only toggles here. Feature configuration lives in their own pages.
library;

import 'package:fluent_ui/fluent_ui.dart';
import 'package:provider/provider.dart';
import '../../services/app_state.dart';

class PluginPage extends StatelessWidget {
  const PluginPage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final config = state.clickerConfig;
    final isDark = FluentTheme.of(context).brightness == Brightness.dark;

    return ScaffoldPage.scrollable(
      padding: const EdgeInsets.all(20),
      children: [
        Row(children: [
          Icon(FluentIcons.puzzle, size: 20, color: state.accentColor),
          const SizedBox(width: 10),
          const Text('功能管理', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 20),

        _buildGroup('核心功能', isDark, [
          _toggle(context, icon: FluentIcons.touch, name: '自动连点',
            enabled: config.autoClickEnabled,
            onChanged: (v) {
              if (!v && state.isClickerRunning) state.stopClicker();
              state.setClickerConfig(config.copyWith(autoClickEnabled: v));
            }),
          _toggle(context, icon: FluentIcons.record2, name: '宏录制与回放', enabled: true, onChanged: null),
          _toggle(context, icon: FluentIcons.keyboard_classic, name: '全局快捷键', enabled: true, onChanged: null),
        ]),

        _buildGroup('智能功能', isDark, [
          _toggle(context, icon: FluentIcons.accounts, name: '拟人模式',
            enabled: config.humanLikeEnabled,
            onChanged: (v) => state.setClickerConfig(config.copyWith(
              humanLikeEnabled: v, smartDelayEnabled: v, randomOffsetEnabled: v))),
        ]),

        _buildGroup('点击增强', isDark, [
          _toggle(context, icon: FluentIcons.volume2, name: '声音反馈',
            enabled: config.soundFeedbackEnabled,
            onChanged: (v) => state.setClickerConfig(config.copyWith(soundFeedbackEnabled: v))),
          _toggle(context, icon: FluentIcons.chart, name: '统计追踪',
            enabled: config.statsEnabled,
            onChanged: (v) => state.setClickerConfig(config.copyWith(statsEnabled: v))),
        ]),

        _buildGroup('扩展功能', isDark, [
          _toggle(context, icon: FluentIcons.search_and_apps, name: '窗口自动检测',
            enabled: config.windowAutoDetectEnabled,
            onChanged: (v) => state.setWindowAutoDetectEnabled(v)),
          _toggle(context, icon: FluentIcons.image_pixel, name: '图像识别',
            enabled: config.imageRecognitionEnabled,
            onChanged: (v) => state.setImageRecognitionEnabled(v)),
          _toggle(context, icon: FluentIcons.code, name: '脚本引擎',
            enabled: config.scriptEngineEnabled,
            onChanged: (v) => state.setScriptEngineEnabled(v)),
          _toggle(context, icon: FluentIcons.remote, name: '远程控制',
            enabled: config.remoteControlEnabled,
            onChanged: (v) => state.setRemoteControlEnabled(v)),
        ]),
      ],
    );
  }

  Widget _buildGroup(String title, bool isDark, List<Widget> children) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700,
        color: isDark ? const Color(0xFFC0C0E8) : const Color(0xFF5A5A80))),
      const SizedBox(height: 8),
      ...children,
      const SizedBox(height: 16),
    ]);
  }

  Widget _toggle(BuildContext context, {
    required IconData icon,
    required String name,
    required bool enabled,
    required ValueChanged<bool>? onChanged,
  }) {
    final isDark = FluentTheme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF252540).withOpacity(0.5) : const Color(0xFFF0F0FA).withOpacity(0.5);
    final accent = FluentTheme.of(context).accentColor;
    final disabledColor = isDark ? const Color(0xFF606080) : const Color(0xFFB0B0C0);

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: isDark ? const Color(0xFF303050) : const Color(0xFFD0D0E0)),
        ),
        child: Row(children: [
          Container(
            width: 32, height: 32,
            decoration: BoxDecoration(
              color: (enabled ? accent : disabledColor).withOpacity(0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(icon, size: 14, color: enabled ? accent : disabledColor),
          ),
          const SizedBox(width: 10),
          Text(name, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13,
            color: enabled || onChanged != null ? null : disabledColor)),
          const Spacer(),
          if (onChanged != null)
            ToggleSwitch(checked: enabled, onChanged: onChanged)
          else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFF00E676).withOpacity(0.12),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text('常开', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Color(0xFF00E676))),
            ),
        ]),
      ),
    );
  }
}
