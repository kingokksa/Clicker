/// Feature toggles page — enable/disable various app features.
/// Toggles are wired to AppState to actually control features.
library;

import 'package:fluent_ui/fluent_ui.dart';
import '../../services/app_state.dart';

class FeaturesPage extends StatefulWidget {
  const FeaturesPage({super.key});

  @override
  State<FeaturesPage> createState() => _FeaturesPageState();
}

class _FeaturesPageState extends State<FeaturesPage> {
  // Feature groups — no premium flags, all features are available
  final Map<String, List<_FeatureToggle>> _featureGroups = {
    '核心功能': [
      _FeatureToggle(id: 'auto_click', name: '自动连点', desc: '鼠标/键盘自动重复点击', icon: FluentIcons.touch, enabled: true),
      _FeatureToggle(id: 'macro', name: '宏录制与回放', desc: '录制操作序列并自动回放', icon: FluentIcons.record2, enabled: true),
      _FeatureToggle(id: 'hotkey', name: '全局快捷键', desc: '系统级快捷键注册', icon: FluentIcons.keyboard_classic, enabled: true),
    ],
    '智能功能': [
      _FeatureToggle(id: 'image_recognition', name: '图像识别', desc: '模板匹配与OCR文字识别', icon: FluentIcons.image_pixel, enabled: false),
      _FeatureToggle(id: 'smart_delay', name: '智能延迟', desc: '随机延迟模拟人工操作', icon: FluentIcons.lightbulb, enabled: false),
      _FeatureToggle(id: 'auto_detect', name: '窗口自动检测', desc: '自动识别活动窗口切换配置', icon: FluentIcons.search_and_apps, enabled: false),
    ],
    '安全与防护': [
      _FeatureToggle(id: 'anti_detect', name: '防检测模式', desc: '模拟人工操作模式，避免被检测', icon: FluentIcons.shield, enabled: false),
      _FeatureToggle(id: 'random_offset', name: '随机偏移', desc: '每次点击添加随机位置偏移', icon: FluentIcons.open_in_new_tab, enabled: true),
      _FeatureToggle(id: 'human_like', name: '拟人化操作', desc: '模拟真实用户的操作节奏', icon: FluentIcons.accounts, enabled: false),
    ],
    '高级功能': [
      _FeatureToggle(id: 'script_engine', name: '脚本引擎', desc: 'Lua/JS脚本支持', icon: FluentIcons.code, enabled: false),
      _FeatureToggle(id: 'remote_control', name: '远程控制', desc: '通过网络远程操控', icon: FluentIcons.remote, enabled: false),
      _FeatureToggle(id: 'stats', name: '统计面板', desc: '详细的操作统计数据', icon: FluentIcons.chart, enabled: true),
      _FeatureToggle(id: 'scheduler', name: '定时任务', desc: '按计划自动执行操作', icon: FluentIcons.timer, enabled: false),
      _FeatureToggle(id: 'multi_instance', name: '多实例', desc: '同时运行多个连点器实例', icon: FluentIcons.stack, enabled: false),
    ],
    '界面功能': [
      _FeatureToggle(id: 'mini_mode', name: '迷你模式', desc: '缩小到悬浮窗显示', icon: FluentIcons.chrome_minimize, enabled: false),
      _FeatureToggle(id: 'tray_icon', name: '系统托盘', desc: '最小化到系统托盘', icon: FluentIcons.status_circle_ring, enabled: true),
      _FeatureToggle(id: 'overlay', name: '悬浮提示', desc: '在屏幕上显示操作状态', icon: FluentIcons.chat, enabled: false),
      _FeatureToggle(id: 'sound_feedback', name: '声音反馈', desc: '操作完成时播放提示音', icon: FluentIcons.volume2, enabled: false),
    ],
  };

  void _applyFeatureState(String id, bool enabled) {
    if (!mounted) return;
    final state = context.read<AppState>();

    switch (id) {
      // Core features — control actual service behavior
      case 'auto_click':
        // Disabling auto_click stops the clicker if running
        if (!enabled && state.isClickerRunning) {
          state.stopClicker();
        }
        state.clickerConfig.autoClickEnabled = enabled;
        state.setClickerConfig(state.clickerConfig);
        break;
      case 'macro':
        // Disabling macro cancels any active recording/playback
        if (!enabled) {
          if (state.isRecording) state.cancelRecording();
          if (state.isPlaying) state.stopMacro();
        }
        break;
      case 'hotkey':
        // Disabling hotkeys stops the hotkey service
        if (!enabled) {
          state.platformInput.stopListening();
        } else {
          state.platformInput.startListening();
        }
        break;
      case 'random_offset':
        state.clickerConfig.randomOffsetEnabled = enabled;
        state.setClickerConfig(state.clickerConfig);
        break;
      case 'smart_delay':
        state.clickerConfig.smartDelayEnabled = enabled;
        state.setClickerConfig(state.clickerConfig);
        break;
      case 'anti_detect':
      case 'human_like':
        // Anti-detect and human-like both affect click behavior
        state.clickerConfig.humanLikeEnabled = enabled;
        state.setClickerConfig(state.clickerConfig);
        break;
      case 'sound_feedback':
        state.clickerConfig.soundFeedbackEnabled = enabled;
        state.setClickerConfig(state.clickerConfig);
        break;
      case 'stats':
        state.clickerConfig.statsEnabled = enabled;
        state.setClickerConfig(state.clickerConfig);
        break;
      case 'image_recognition':
        state.setImageRecognitionEnabled(enabled);
        break;
      case 'auto_detect':
        state.setWindowAutoDetectEnabled(enabled);
        break;
      case 'script_engine':
        state.setScriptEngineEnabled(enabled);
        break;
      case 'remote_control':
        state.setRemoteControlEnabled(enabled);
        break;
      // Other features: store state for future implementation
      default:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = FluentTheme.of(context).brightness == Brightness.dark;
    final state = context.watch<AppState>();

    return ScaffoldPage.scrollable(
      padding: const EdgeInsets.all(20),
      children: [
        // Header
        Row(children: [
          Icon(FluentIcons.toggle_left, size: 20, color: state.accentColor),
          const SizedBox(width: 10),
          const Text('功能开关', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          const Spacer(),
          Button(onPressed: () {
            setState(() {
              for (final group in _featureGroups.values) {
                for (final f in group) {
                  f.enabled = true;
                  _applyFeatureState(f.id, true);
                }
              }
            });
          }, child: const Text('全部启用')),
          const SizedBox(width: 8),
          Button(onPressed: () {
            setState(() {
              for (final group in _featureGroups.values) {
                for (final f in group) {
                  f.enabled = false;
                  _applyFeatureState(f.id, false);
                }
              }
            });
          }, child: const Text('全部禁用')),
        ]),
        const SizedBox(height: 6),
        Text('按需启用或禁用应用功能，精简你的使用体验', style: TextStyle(fontSize: 13, color: isDark ? const Color(0xFF9090B0) : const Color(0xFF8A8A9A))),
        const SizedBox(height: 16),

        // Feature groups
        ..._featureGroups.entries.expand((entry) => [
          _buildGroupHeader(entry.key, isDark),
          const SizedBox(height: 8),
          ...entry.value.map((f) => _buildFeatureCard(f, isDark)),
          const SizedBox(height: 16),
        ]),
      ],
    );
  }

  Widget _buildGroupHeader(String title, bool isDark) {
    return Row(children: [
      Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700,
        color: isDark ? const Color(0xFFC0C0E8) : const Color(0xFF5A5A80))),
    ]);
  }

  Widget _buildFeatureCard(_FeatureToggle feature, bool isDark) {
    final cardBg = isDark ? const Color(0xFF252540).withOpacity(0.5) : const Color(0xFFF0F0FA).withOpacity(0.5);
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
          Icon(feature.icon, size: 16, color: feature.enabled ? FluentTheme.of(context).accentColor : (isDark ? const Color(0xFF606080) : const Color(0xFFB0B0C0))),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(feature.name, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13,
              color: feature.enabled ? null : (isDark ? const Color(0xFF606080) : const Color(0xFFB0B0C0)))),
            const SizedBox(height: 2),
            Text(feature.desc, style: TextStyle(fontSize: 11, color: isDark ? const Color(0xFF707090) : const Color(0xFF9A9AAA))),
          ])),
          ToggleSwitch(checked: feature.enabled, onChanged: (v) {
            setState(() => feature.enabled = v);
            _applyFeatureState(feature.id, v);
          }),
        ]),
      ),
    );
  }
}

class _FeatureToggle {
  final String id;
  final String name;
  final String desc;
  final IconData icon;
  bool enabled;

  _FeatureToggle({required this.id, required this.name, required this.desc, required this.icon, required this.enabled});
}
