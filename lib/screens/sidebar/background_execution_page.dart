/// Background execution module — send clicks to a background window
/// without affecting the foreground window the user is using.
library;

import 'dart:io';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../services/app_state.dart';

class WindowInfo {
  final int hwnd;
  final String title;
  final String className;

  const WindowInfo({required this.hwnd, required this.title, required this.className});
}

class BackgroundExecutionPage extends StatefulWidget {
  const BackgroundExecutionPage({super.key});

  @override
  State<BackgroundExecutionPage> createState() => _BackgroundExecutionPageState();
}

class _BackgroundExecutionPageState extends State<BackgroundExecutionPage> {
  List<WindowInfo> _windows = [];
  bool _loading = false;

  Future<void> _refreshWindows() async {
    if (!Platform.isWindows) return;
    setState(() => _loading = true);
    try {
      final channel = MethodChannel('com.clicker.pro/platform');
      final result = await channel.invokeMethod('enumerateWindows');
      final list = <WindowInfo>[];
      if (result is List) {
        for (final item in result) {
          if (item is Map) {
            list.add(WindowInfo(
              hwnd: item['hwnd'] as int,
              title: (item['title'] as String?) ?? '',
              className: (item['className'] as String?) ?? '',
            ));
          }
        }
      }
      setState(() { _windows = list; _loading = false; });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final config = state.clickerConfig;
    final isDark = FluentTheme.of(context).brightness == Brightness.dark;
    final accent = FluentTheme.of(context).accentColor;

    return ScaffoldPage.scrollable(
      padding: const EdgeInsets.all(20),
      children: [
        // Header
        Row(children: [
          Icon(FluentIcons.settings, size: 20, color: accent),
          const SizedBox(width: 10),
          const Text('后台执行', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 6),
        Text('向后台窗口发送点击，不影响前台操作', style: TextStyle(fontSize: 13,
          color: isDark ? const Color(0xFF9090B0) : const Color(0xFF8A8A9A))),
        const SizedBox(height: 20),

        // ─── Background Click Mode ────────────────────────────
        _sectionTitle('后台点击', isDark),
        const SizedBox(height: 8),

        _card(isDark, children: [
          _toggleRow(
            icon: FluentIcons.hide3,
            name: '后台点击模式',
            desc: '开启后点击发送到目标窗口，不影响当前操作',
            enabled: config.backgroundExecutionEnabled,
            onChanged: (v) => state.setClickerConfig(config.copyWith(backgroundExecutionEnabled: v)),
            isDark: isDark,
            accent: accent,
          ),
          const Divider(style: DividerThemeData(horizontalMargin: EdgeInsets.zero)),

          // Target window selection
          _labelRow('目标窗口', isDark),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(
              child: InfoLabel(
                label: config.targetWindowTitle.isEmpty ? '未选择' : config.targetWindowTitle,
                child: ComboBox<int>(
                  isExpanded: true,
                  placeholder: const Text('选择目标窗口'),
                  items: _windows.map((w) => ComboBoxItem<int>(
                    value: w.hwnd,
                    child: Text(w.title.length > 40 ? '${w.title.substring(0, 40)}...' : w.title,
                      style: const TextStyle(fontSize: 12)),
                  )).toList(),
                  value: _windows.any((w) => w.hwnd == config.targetHwnd) ? config.targetHwnd : null,
                  onChanged: (hwnd) {
                    if (hwnd != null) {
                      final win = _windows.firstWhere((w) => w.hwnd == hwnd);
                      state.setClickerConfig(config.copyWith(
                        targetHwnd: hwnd,
                        targetWindowTitle: win.title,
                      ));
                    }
                  },
                ),
              ),
            ),
            const SizedBox(width: 8),
            Button(
              onPressed: _loading ? null : _refreshWindows,
              child: _loading
                ? const SizedBox(width: 14, height: 14, child: ProgressRing(strokeWidth: 2))
                : const Icon(FluentIcons.refresh, size: 14),
            ),
          ]),
          const SizedBox(height: 8),

          // Click coordinates
          _labelRow('点击坐标（相对目标窗口客户区）', isDark),
          const SizedBox(height: 6),
          Row(children: [
            SizedBox(
              width: 120,
              child: TextBox(
                placeholder: 'X',
                controller: TextEditingController(text: config.targetClientX.toString()),
                onChanged: (v) {
                  final val = int.tryParse(v);
                  if (val != null) state.setClickerConfig(config.copyWith(targetClientX: val));
                },
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 120,
              child: TextBox(
                placeholder: 'Y',
                controller: TextEditingController(text: config.targetClientY.toString()),
                onChanged: (v) {
                  final val = int.tryParse(v);
                  if (val != null) state.setClickerConfig(config.copyWith(targetClientY: val));
                },
              ),
            ),
          ]),
        ]),

        const SizedBox(height: 20),

        // ─── Auto Start ───────────────────────────────────────
        _sectionTitle('开机自启', isDark),
        const SizedBox(height: 8),

        _card(isDark, children: [
          _toggleRow(
            icon: FluentIcons.brightness,
            name: '开机自动启动',
            desc: '系统启动时自动运行 Clicker',
            enabled: config.autoStartEnabled,
            onChanged: (v) {
              state.setClickerConfig(config.copyWith(autoStartEnabled: v));
              _setAutoStart(v);
            },
            isDark: isDark,
            accent: accent,
          ),
          const Divider(style: DividerThemeData(horizontalMargin: EdgeInsets.zero)),
          _toggleRow(
            icon: FluentIcons.play_resume,
            name: '自启后静默运行',
            desc: '开机自启时直接最小化到托盘',
            enabled: config.autoStartSilent,
            onChanged: (v) => state.setClickerConfig(config.copyWith(autoStartSilent: v)),
            isDark: isDark,
            accent: accent,
          ),
        ]),

        const SizedBox(height: 20),

        // ─── Status ───────────────────────────────────────────
        _sectionTitle('当前状态', isDark),
        const SizedBox(height: 8),

        _card(isDark, children: [
          _statusRow('连点器', state.isClickerRunning ? '运行中' : '空闲',
            state.isClickerRunning, isDark, accent),
          const Divider(style: DividerThemeData(horizontalMargin: EdgeInsets.zero)),
          _statusRow('点击模式', config.backgroundExecutionEnabled ? '后台点击' : '前台点击',
            config.backgroundExecutionEnabled, isDark, accent),
          const Divider(style: DividerThemeData(horizontalMargin: EdgeInsets.zero)),
          _statusRow('目标窗口', config.backgroundExecutionEnabled
            ? (config.targetWindowTitle.isEmpty ? '未选择' : config.targetWindowTitle)
            : '不适用',
            config.backgroundExecutionEnabled && config.targetHwnd != 0, isDark, accent),
        ]),
      ],
    );
  }

  Future<void> _setAutoStart(bool enabled) async {
    if (!Platform.isWindows) return;
    try {
      final channel = MethodChannel('com.clicker.pro/platform');
      await channel.invokeMethod(enabled ? 'enableAutoStart' : 'disableAutoStart');
    } catch (_) {}
  }

  Widget _sectionTitle(String title, bool isDark) {
    return Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700,
      color: isDark ? const Color(0xFFC0C0E8) : const Color(0xFF5A5A80)));
  }

  Widget _labelRow(String label, bool isDark) {
    return Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
      color: isDark ? const Color(0xFF9090B0) : const Color(0xFF6A6A8A)));
  }

  Widget _card(bool isDark, {required List<Widget> children}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF252540).withOpacity(0.5) : const Color(0xFFF0F0FA).withOpacity(0.5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: isDark ? const Color(0xFF303050) : const Color(0xFFD0D0E0)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
    );
  }

  Widget _toggleRow({
    required IconData icon,
    required String name,
    required String desc,
    required bool enabled,
    required ValueChanged<bool> onChanged,
    required bool isDark,
    required Color accent,
  }) {
    final disabledColor = isDark ? const Color(0xFF606080) : const Color(0xFFB0B0C0);
    return Row(children: [
      Container(
        width: 32, height: 32,
        decoration: BoxDecoration(
          color: (enabled ? accent : disabledColor).withOpacity(0.1),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(icon, size: 14, color: enabled ? accent : disabledColor),
      ),
      const SizedBox(width: 10),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        const SizedBox(height: 2),
        Text(desc, style: TextStyle(fontSize: 11, color: isDark ? const Color(0xFF707090) : const Color(0xFF9A9AAA))),
      ])),
      ToggleSwitch(checked: enabled, onChanged: onChanged),
    ]);
  }

  Widget _statusRow(String label, String value, bool active, bool isDark, Color accent) {
    return Row(children: [
      Container(
        width: 8, height: 8,
        decoration: BoxDecoration(
          color: active ? const Color(0xFF00E676) : (isDark ? const Color(0xFF606080) : const Color(0xFFB0B0C0)),
          shape: BoxShape.circle,
        ),
      ),
      const SizedBox(width: 10),
      Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
      const Spacer(),
      Flexible(child: Text(value, overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 13,
          color: active ? accent : (isDark ? const Color(0xFF9090B0) : const Color(0xFF8A8A9A))))),
    ]);
  }
}
