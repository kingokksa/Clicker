/// Settings page — hotkeys, theme, profiles. Fluent UI design.
library;

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'package:window_manager/window_manager.dart';
import '../../services/app_state.dart';
import '../../services/update_service.dart';
import '../../models/hotkey_config.dart';
import '../../models/clicker_config.dart' show SoundConfig;

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  String _appVersion = '';

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    // Keep in sync with pubspec.yaml version
    const version = '1.1.0';
    if (mounted) setState(() => _appVersion = version);
    UpdateService.instance.setCurrentVersion(version);
  }

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
      const SizedBox(height: 12),
      _sectionCard(title: '拟人模式', icon: FluentIcons.accounts, child: _buildHumanLikeSection(context, state)),
      const SizedBox(height: 12),
      _sectionCard(title: '声音反馈', icon: FluentIcons.volume2, child: _buildSoundFeedbackSection(context, state)),
    ];

    final rightSections = <Widget>[
      _sectionCard(title: '窗口', icon: FluentIcons.stack, child: _buildWindowOptions(state)),
      const SizedBox(height: 12),
      _sectionCard(title: '开机自启', icon: FluentIcons.brightness, child: _buildAutoStartSection(state)),
      const SizedBox(height: 12),
      _sectionCard(title: '配置管理', icon: FluentIcons.save, child: _buildProfileSection(context, state)),
      const SizedBox(height: 12),
      _sectionCard(title: '关于', icon: FluentIcons.info, child: _buildAboutSection()),
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
        Icon(icon, size: 16, color: accent.withValues(alpha: 0.7)),
        const SizedBox(width: 10),
        Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
        GestureDetector(
          onTap: () => _pickHotkey(context, state, field, value),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: accent.withValues(alpha: 0.3)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(value.toUpperCase(), style: TextStyle(
                color: accent, fontWeight: FontWeight.w600, fontFamily: 'monospace', fontSize: 13,
              )),
              const SizedBox(width: 6),
              Icon(FluentIcons.edit, size: 14, color: accent.withValues(alpha: 0.6)),
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
        const Expanded(child: Text('关闭时最小化到托盘', style: TextStyle(fontSize: 13))),
        ToggleSwitch(checked: state.minimizeToTray, onChanged: (v) => state.setMinimizeToTray(v)),
      ]),
      const Divider(style: DividerThemeData(horizontalMargin: EdgeInsets.zero)),
      Row(children: [
        const Expanded(child: Text('悬浮窗置顶', style: TextStyle(fontSize: 13))),
        ToggleSwitch(checked: state.floatingAlwaysOnTop, onChanged: (v) {
          state.setFloatingAlwaysOnTop(v);
          windowManager.setAlwaysOnTop(v);
        }),
      ]),
      const Divider(style: DividerThemeData(horizontalMargin: EdgeInsets.zero)),
      Row(children: [
        const Expanded(child: Text('界面动效', style: TextStyle(fontSize: 13))),
        ToggleSwitch(checked: state.uiAnimations, onChanged: (v) => state.setUiAnimations(v)),
      ]),
    ]);
  }

  // ─── Auto Start ───────────────────────────────────────────

  Widget _buildAutoStartSection(AppState state) {
    final config = state.clickerConfig;
    return Column(children: [
      Row(children: [
        const Expanded(child: Text('开机自动启动', style: TextStyle(fontSize: 13))),
        ToggleSwitch(checked: config.autoStartEnabled, onChanged: (v) {
          state.setClickerConfig(config.copyWith(autoStartEnabled: v));
          _setAutoStart(v);
        }),
      ]),
      const Divider(style: DividerThemeData(horizontalMargin: EdgeInsets.zero)),
      Row(children: [
        const Expanded(child: Text('自启后静默运行', style: TextStyle(fontSize: 13))),
        ToggleSwitch(checked: config.autoStartSilent, onChanged: (v) {
          state.setClickerConfig(config.copyWith(autoStartSilent: v));
        }),
      ]),
    ]);
  }

  Future<void> _setAutoStart(bool enabled) async {
    if (!Platform.isWindows) return;
    try {
      final channel = MethodChannel('com.clicker.pro/platform');
      await channel.invokeMethod(enabled ? 'enableAutoStart' : 'disableAutoStart');
    } catch (_) {}
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
            Icon(FluentIcons.bookmarks, size: 16, color: FluentTheme.of(context).accentColor.withValues(alpha: 0.5)),
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
          style: ButtonStyle(backgroundColor: WidgetStatePropertyAll(accent.withValues(alpha: 0.15))),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(FluentIcons.upload, size: 14, color: accent),
            const SizedBox(width: 6),
            Text('导出配置', style: TextStyle(color: accent, fontSize: 13)),
          ]),
        )),
        const SizedBox(width: 8),
        Expanded(child: FilledButton(
          onPressed: () => _importConfig(context, state),
          style: ButtonStyle(backgroundColor: WidgetStatePropertyAll(accent.withValues(alpha: 0.15))),
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

  // ─── About Section ────────────────────────────────────────

  Widget _buildAboutSection() {
    final update = UpdateService.instance;
    final isDark = FluentTheme.of(context).brightness == Brightness.dark;
    final subtitleColor = isDark ? const Color(0xFF9090B0) : const Color(0xFF8A8A9A);

    return ListenableBuilder(
      listenable: update,
      builder: (context, _) {
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Version & Author
          Row(children: [
            const Text('版本:', style: TextStyle(fontSize: 13)),
            const SizedBox(width: 8),
            Text('v$_appVersion', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          ]),
          const SizedBox(height: 6),
          Row(children: [
            const Text('作者:', style: TextStyle(fontSize: 13)),
            const SizedBox(width: 8),
            const Text('kingokksa', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          ]),
          const SizedBox(height: 6),
          HyperlinkButton(
            onPressed: () => _launchUrl('https://github.com/kingokksa/Clicker'),
            child: const Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(FluentIcons.open_in_new_tab, size: 12),
              SizedBox(width: 4),
              Text('GitHub'),
            ]),
          ),
          const SizedBox(height: 12),
          const Divider(),
          const SizedBox(height: 12),

          // Check for updates
          if (update.checking) ...[
            const Row(children: [
              SizedBox(width: 16, height: 16, child: ProgressRing(strokeWidth: 2)),
              SizedBox(width: 8),
              Text('正在检查更新...', style: TextStyle(fontSize: 13)),
            ]),
          ] else if (update.updateError.isNotEmpty) ...[
            Text(update.updateError, style: TextStyle(fontSize: 12, color: Colors.red)),
            const SizedBox(height: 8),
            Button(onPressed: () => update.checkForUpdates(), child: const Text('重试')),
          ] else if (update.updateAvailable) ...[
            Row(children: [
              Icon(FluentIcons.download, size: 16, color: FluentTheme.of(context).accentColor),
              const SizedBox(width: 8),
              Text('发现新版本: v${update.latestVersion}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            ]),
            if (update.releaseNotes.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1A1A30) : const Color(0xFFF5F5FA),
                  borderRadius: BorderRadius.circular(6),
                ),
                constraints: const BoxConstraints(maxHeight: 120),
                child: SingleChildScrollView(child: Text(update.releaseNotes, style: TextStyle(fontSize: 11, color: subtitleColor))),
              ),
            ],
            const SizedBox(height: 12),
            if (update.downloading) ...[
              Row(children: [
                Expanded(child: ProgressBar(value: update.downloadProgress * 100)),
                const SizedBox(width: 8),
                Text('${(update.downloadProgress * 100).toStringAsFixed(0)}%', style: const TextStyle(fontSize: 12)),
              ]),
              const SizedBox(height: 4),
              const Text('下载中，完成后将自动重启...', style: TextStyle(fontSize: 12)),
            ] else ...[
              FilledButton(onPressed: () => update.downloadAndInstall(), child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(FluentIcons.download, size: 14),
                SizedBox(width: 6),
                Text('下载并更新'),
              ])),
            ],
          ] else if (update.latestVersion.isNotEmpty) ...[
            Row(children: [
              Icon(FluentIcons.completed, size: 16, color: const Color(0xFF00E676)),
              const SizedBox(width: 8),
              const Text('已是最新版本', style: TextStyle(fontSize: 13)),
            ]),
          ] else ...[
            Button(onPressed: () => update.checkForUpdates(), child: const Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(FluentIcons.refresh, size: 14),
              SizedBox(width: 6),
              Text('检查更新'),
            ])),
          ],
        ]);
      },
    );
  }

  // ──── Human-like Mode Section ────

  Widget _buildHumanLikeSection(BuildContext context, AppState state) {
    final config = state.clickerConfig;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Text('启用拟人模式', style: TextStyle(fontSize: 13)),
        const Spacer(),
        ToggleSwitch(
          checked: config.humanLikeEnabled,
          onChanged: (v) => state.setClickerConfig(config.copyWith(
            humanLikeEnabled: v,
            smartDelayEnabled: v || config.smartDelayEnabled,
            randomOffsetEnabled: v || config.randomOffsetEnabled,
          )),
        ),
      ]),
      if (config.humanLikeEnabled) ...[
        const SizedBox(height: 12),
        const Divider(),
        const SizedBox(height: 8),
        // Random offset — shared with main page
        Row(children: [
          const Text('随机偏移', style: TextStyle(fontSize: 12)),
          const Spacer(),
          ToggleSwitch(
            checked: config.randomOffsetEnabled,
            onChanged: (v) => state.setClickerConfig(config.copyWith(randomOffsetEnabled: v)),
          ),
        ]),
        if (config.randomOffsetEnabled) Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(children: [
            const SizedBox(width: 80, child: Text('偏移范围:', style: TextStyle(fontSize: 11))),
            SizedBox(width: 60, child: TextBox(
              controller: TextEditingController(text: config.randomOffsetMinPx.toString()),
              placeholder: '1',
              onChanged: (v) { final p = int.tryParse(v); if (p != null && p > 0) state.setClickerConfig(config.copyWith(randomOffsetMinPx: p)); },
            )),
            const SizedBox(width: 4),
            const Text('-', style: TextStyle(fontSize: 12)),
            const SizedBox(width: 4),
            SizedBox(width: 60, child: TextBox(
              controller: TextEditingController(text: config.randomOffsetMaxPx.toString()),
              placeholder: '5',
              onChanged: (v) { final p = int.tryParse(v); if (p != null && p > 0) state.setClickerConfig(config.copyWith(randomOffsetMaxPx: p)); },
            )),
            const SizedBox(width: 4),
            const Text('px', style: TextStyle(fontSize: 11)),
          ]),
        ),
        const SizedBox(height: 6),
        // Random delay — shared with main page
        Row(children: [
          const Text('随机延迟', style: TextStyle(fontSize: 12)),
          const Spacer(),
          ToggleSwitch(
            checked: config.smartDelayEnabled,
            onChanged: (v) => state.setClickerConfig(config.copyWith(smartDelayEnabled: v)),
          ),
        ]),
        if (config.smartDelayEnabled) Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(children: [
            const SizedBox(width: 80, child: Text('延迟范围:', style: TextStyle(fontSize: 11))),
            SizedBox(width: 60, child: TextBox(
              controller: TextEditingController(text: config.randomDelayMinMs.toString()),
              placeholder: '10',
              onChanged: (v) { final p = int.tryParse(v); if (p != null && p > 0) state.setClickerConfig(config.copyWith(randomDelayMinMs: p)); },
            )),
            const SizedBox(width: 4),
            const Text('-', style: TextStyle(fontSize: 12)),
            const SizedBox(width: 4),
            SizedBox(width: 60, child: TextBox(
              controller: TextEditingController(text: config.randomDelayMaxMs.toString()),
              placeholder: '50',
              onChanged: (v) { final p = int.tryParse(v); if (p != null && p > 0) state.setClickerConfig(config.copyWith(randomDelayMaxMs: p)); },
            )),
            const SizedBox(width: 4),
            const Text('ms', style: TextStyle(fontSize: 11)),
          ]),
        ),
        const SizedBox(height: 6),
        // Bezier curve
        Row(children: [
          const Text('贝塞尔轨迹', style: TextStyle(fontSize: 12)),
          const Spacer(),
          ToggleSwitch(
            checked: config.humanLikeBezierCurve,
            onChanged: (v) => state.setClickerConfig(config.copyWith(humanLikeBezierCurve: v)),
          ),
        ]),
        const SizedBox(height: 6),
        // Random pause
        Row(children: [
          const Text('随机暂停', style: TextStyle(fontSize: 12)),
          const Spacer(),
          ToggleSwitch(
            checked: config.humanLikeRandomPause,
            onChanged: (v) => state.setClickerConfig(config.copyWith(humanLikeRandomPause: v)),
          ),
        ]),
        if (config.humanLikeRandomPause) ...[
          const SizedBox(height: 6),
          Row(children: [
            const SizedBox(width: 80, child: Text('暂停概率:', style: TextStyle(fontSize: 11))),
            Expanded(child: Slider(
              value: config.humanLikePauseChance.toDouble(),
              min: 1, max: 20, divisions: 19,
              label: '${config.humanLikePauseChance}%',
              onChanged: (v) => state.setClickerConfig(config.copyWith(humanLikePauseChance: v.round())),
            )),
            const SizedBox(width: 8),
            Text('${config.humanLikePauseChance}%', style: const TextStyle(fontSize: 11)),
          ]),
          Row(children: [
            const SizedBox(width: 80, child: Text('暂停时长:', style: TextStyle(fontSize: 11))),
            SizedBox(width: 60, child: TextBox(
              controller: TextEditingController(text: config.humanLikePauseMinMs.toString()),
              placeholder: '200',
              onChanged: (v) { final p = int.tryParse(v); if (p != null && p > 0) state.setClickerConfig(config.copyWith(humanLikePauseMinMs: p)); },
            )),
            const SizedBox(width: 4),
            const Text('-', style: TextStyle(fontSize: 12)),
            const SizedBox(width: 4),
            SizedBox(width: 60, child: TextBox(
              controller: TextEditingController(text: config.humanLikePauseMaxMs.toString()),
              placeholder: '800',
              onChanged: (v) { final p = int.tryParse(v); if (p != null && p > 0) state.setClickerConfig(config.copyWith(humanLikePauseMaxMs: p)); },
            )),
            const SizedBox(width: 4),
            const Text('ms', style: TextStyle(fontSize: 11)),
          ]),
        ],
      ],
    ]);
  }

  // ──── Sound Feedback Section ────

  Widget _buildSoundFeedbackSection(BuildContext context, AppState state) {
    final config = state.clickerConfig;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Text('启用声音反馈', style: TextStyle(fontSize: 13)),
        const Spacer(),
        ToggleSwitch(
          checked: config.soundFeedbackEnabled,
          onChanged: (v) => state.setClickerConfig(config.copyWith(soundFeedbackEnabled: v)),
        ),
      ]),
      if (config.soundFeedbackEnabled) ...[
        const SizedBox(height: 12),
        const Divider(),
        const SizedBox(height: 8),
        _buildSoundModuleTile(
          context: context,
          state: state,
          label: '点击音效',
          icon: FluentIcons.touch,
          config: config.soundFeedbackClick,
          onChanged: (sc) => state.setClickerConfig(config.copyWith(soundFeedbackClick: sc)),
        ),
        const SizedBox(height: 6),
        _buildSoundModuleTile(
          context: context,
          state: state,
          label: '按键音效',
          icon: FluentIcons.keyboard_classic,
          config: config.soundFeedbackKey,
          onChanged: (sc) => state.setClickerConfig(config.copyWith(soundFeedbackKey: sc)),
        ),
        const SizedBox(height: 6),
        _buildSoundModuleTile(
          context: context,
          state: state,
          label: '宏音效',
          icon: FluentIcons.play,
          config: config.soundFeedbackMacro,
          onChanged: (sc) => state.setClickerConfig(config.copyWith(soundFeedbackMacro: sc)),
        ),
      ],
    ]);
  }

  Widget _buildSoundModuleTile({
    required BuildContext context,
    required AppState state,
    required String label,
    required IconData icon,
    required SoundConfig config,
    required ValueChanged<SoundConfig> onChanged,
  }) {
    final theme = FluentTheme.of(context);
    final accent = theme.accentColor;
    final isDark = theme.brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF1A1A2E) : const Color(0xFFF5F5FA);
    return Expander(
      initiallyExpanded: false,
      header: Row(children: [
        Icon(icon, size: 14, color: accent.withValues(alpha: 0.7)),
        const SizedBox(width: 8),
        Text(label, style: const TextStyle(fontSize: 13)),
        const Spacer(),
        // Quick toggle: enable/disable this module
        ToggleSwitch(
          checked: config.enabled,
          onChanged: (v) => onChanged(SoundConfig(
            startEnabled: v,
            endEnabled: v ? config.endEnabled : false,
            startPath: config.startPath,
            endPath: config.endPath,
          )),
        ),
      ]),
      content: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Start sound
        _buildSoundItemRow(
          context: context,
          label: '开始音效',
          enabled: config.startEnabled,
          path: config.startPath,
          onEnabledChanged: (v) => onChanged(config.copyWith(startEnabled: v)),
          onPathChanged: (p) => onChanged(config.copyWith(startPath: p)),
        ),
        const SizedBox(height: 8),
        const Divider(style: DividerThemeData(horizontalMargin: EdgeInsets.zero)),
        const SizedBox(height: 8),
        // End sound
        _buildSoundItemRow(
          context: context,
          label: '结束音效',
          enabled: config.endEnabled,
          path: config.endPath,
          onEnabledChanged: (v) => onChanged(config.copyWith(endEnabled: v)),
          onPathChanged: (p) => onChanged(config.copyWith(endPath: p)),
        ),
      ]),
    );
  }

  Widget _buildSoundItemRow({
    required BuildContext context,
    required String label,
    required bool enabled,
    required String path,
    required ValueChanged<bool> onEnabledChanged,
    required ValueChanged<String> onPathChanged,
  }) {
    final theme = FluentTheme.of(context);
    final accent = theme.accentColor;
    final isDark = theme.brightness == Brightness.dark;
    final subtitleColor = isDark ? const Color(0xFF9090B0) : const Color(0xFF8A8A9A);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Checkbox(checked: enabled, onChanged: (v) => onEnabledChanged(v ?? false)),
        const SizedBox(width: 8),
        Text(label, style: const TextStyle(fontSize: 12)),
        const Spacer(),
        if (enabled) ...[
          // File picker button
          HyperlinkButton(
            onPressed: () => _pickSoundFile(onPathChanged),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(FluentIcons.open_file, size: 12, color: accent),
              const SizedBox(width: 4),
              Text(path.isEmpty ? '默认系统音效' : '自定义', style: TextStyle(fontSize: 11, color: path.isEmpty ? subtitleColor : accent)),
            ]),
          ),
          if (path.isNotEmpty) ...[
            HyperlinkButton(
              onPressed: () => onPathChanged(''),
              child: Text('重置', style: TextStyle(fontSize: 11, color: Colors.red)),
            ),
          ],
        ],
      ]),
      if (enabled && path.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(left: 36, top: 2),
          child: Text(path, style: TextStyle(fontSize: 10, color: subtitleColor), overflow: TextOverflow.ellipsis),
        ),
    ]);
  }

  Future<void> _pickSoundFile(ValueChanged<String> onPicked) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.audio,
      allowMultiple: false,
      dialogTitle: '选择音效文件',
    );
    if (result != null && result.files.single.path != null) {
      onPicked(result.files.single.path!);
    }
  }

  void _launchUrl(String url) {
    if (Platform.isWindows) {
      Process.run('cmd', ['/c', 'start', url]);
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
            color: accent.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12),
            border: Border.all(color: accent.withValues(alpha: 0.4)),
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
            color: selected ? accent.withValues(alpha: 0.2) : unselectedBg,
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
