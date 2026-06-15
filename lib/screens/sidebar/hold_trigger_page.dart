/// Hold trigger page — configure keys that auto-repeat when held down.
/// Each trigger key has its own action, interval, and settings.
library;

import 'dart:io';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../models/hold_trigger_key.dart';
import '../../models/clicker_config.dart';
import '../../services/app_state.dart';
import '../../services/screen_overlay_service.dart';
import '../../widgets/app_slider.dart';

class HoldTriggerPage extends StatefulWidget {
  const HoldTriggerPage({super.key});

  @override
  State<HoldTriggerPage> createState() => _HoldTriggerPageState();
}

class _HoldTriggerPageState extends State<HoldTriggerPage> {
  static const _platformChannel = MethodChannel('com.clicker.pro/platform');

  @override
  Widget build(BuildContext context) {
    final isDark = FluentTheme.of(context).brightness == Brightness.dark;
    final state = context.watch<AppState>();
    final keys = state.holdTriggerKeys;

    return ScaffoldPage.scrollable(
      padding: const EdgeInsets.all(20),
      children: [
        // Header
        Row(children: [
          Icon(FluentIcons.keyboard_classic, size: 20, color: state.accentColor),
          const SizedBox(width: 10),
          const Text('按住触发', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          const Spacer(),
          Button(onPressed: _addNewKey, child: const Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(FluentIcons.add, size: 12),
            SizedBox(width: 6),
            Text('添加按键'),
          ])),
        ]),
        const SizedBox(height: 16),

        // Empty state
        if (keys.isEmpty)
          _buildEmptyState(isDark),

        // Key list
        ...keys.map((k) => _buildKeyCard(k, isDark, state)),
      ],
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF252540).withValues(alpha: 0.3) : const Color(0xFFF0F0FA).withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isDark ? const Color(0xFF303050) : const Color(0xFFD0D0E0), style: BorderStyle.solid),
      ),
      child: Column(children: [
        Icon(FluentIcons.keyboard_classic, size: 40, color: isDark ? const Color(0xFF505070) : const Color(0xFFB0B0C0)),
        const SizedBox(height: 12),
        Text('暂无按住触发按键', style: TextStyle(fontSize: 14, color: isDark ? const Color(0xFF707090) : const Color(0xFF9A9AAA))),
      ]),
    );
  }

  Widget _buildKeyCard(HoldTriggerKey key, bool isDark, AppState state) {
    final accentColor = state.accentColor;
    final cardBg = isDark ? const Color(0xFF252540).withValues(alpha: 0.5) : const Color(0xFFF0F0FA).withValues(alpha: 0.5);

    String actionDesc;
    switch (key.action) {
      case HoldTriggerAction.mouseClick:
        final btn = key.mouseButton == 'right' ? '右键' : (key.mouseButton == 'middle' ? '中键' : '左键');
        actionDesc = '鼠标$btn点击';
        break;
      case HoldTriggerAction.keyRepeat:
        actionDesc = '按键 ${_displayName(key.keyToRepeat)}';
        break;
      case HoldTriggerAction.keyCombo:
        actionDesc = '组合键 ${key.comboKeys.map(_displayName).join("+")}';
        break;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: isDark ? const Color(0xFF303050) : const Color(0xFFD0D0E0)),
        ),
        child: Row(children: [
          // Trigger key badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: key.enabled ? accentColor.withValues(alpha: 0.15) : (isDark ? const Color(0xFF303050) : const Color(0xFFE0E0F0)),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: key.enabled ? accentColor.withValues(alpha: 0.4) : (isDark ? const Color(0xFF404060) : const Color(0xFFD0D0E0))),
            ),
            child: Text(
              key.triggerType == HoldTriggerType.mouse
                ? _mouseButtonName(key.triggerMouseButton)
                : _displayName(key.triggerKey),
              style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w700,
                color: key.enabled ? accentColor : (isDark ? const Color(0xFF606080) : const Color(0xFFB0B0C0)),
              ),
            ),
          ),
          const SizedBox(width: 14),
          // Action description
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(actionDesc, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13,
              color: key.enabled ? null : (isDark ? const Color(0xFF606080) : const Color(0xFFB0B0C0)))),
            const SizedBox(height: 2),
            Text('间隔 ${key.intervalMs.toInt()}ms${key.backgroundMode ? " · 后台(${key.targetX},${key.targetY})" : ""}',
              style: TextStyle(fontSize: 11, color: isDark ? const Color(0xFF707090) : const Color(0xFF9A9AAA))),
          ])),
          // Enable toggle
          ToggleSwitch(
            checked: key.enabled,
            onChanged: (v) => _toggleKey(key, v),
          ),
          const SizedBox(width: 8),
          // Edit button
          IconButton(
            icon: Icon(FluentIcons.edit, size: 14, color: isDark ? const Color(0xFF9090B0) : const Color(0xFF6A6A80)),
            onPressed: () => _editKey(key),
          ),
          // Delete button
          IconButton(
            icon: Icon(FluentIcons.delete, size: 14, color: isDark ? const Color(0xFF9090B0) : const Color(0xFF6A6A80)),
            onPressed: () => _deleteKey(key),
          ),
        ]),
      ),
    );
  }

  String _displayName(String key) {
    const nameMap = {
      'space': 'Space', 'enter': 'Enter', 'tab': 'Tab', 'escape': 'Esc',
      'backspace': 'Back', 'delete': 'Del', 'insert': 'Ins',
      'home': 'Home', 'end': 'End', 'pageup': 'PgUp', 'pagedown': 'PgDn',
      'left': 'Left', 'right': 'Right', 'up': 'Up', 'down': 'Down',
      'shift': 'Shift', 'ctrl': 'Ctrl', 'alt': 'Alt', 'win': 'Win',
    };
    if (nameMap.containsKey(key.toLowerCase())) return nameMap[key.toLowerCase()]!;
    if (key.length == 1) return key.toUpperCase();
    return key;
  }

  String _mouseButtonName(String btn) {
    switch (btn) {
      case 'right': return '右键';
      case 'middle': return '中键';
      case 'x1': return '侧键1';
      case 'x2': return '侧键2';
      default: return '左键';
    }
  }

  void _addNewKey() {
    final newKey = HoldTriggerKey();
    _showEditDialog(newKey, isNew: true);
  }

  void _editKey(HoldTriggerKey key) {
    _showEditDialog(key, isNew: false);
  }

  void _toggleKey(HoldTriggerKey key, bool enabled) {
    final state = context.read<AppState>();
    state.updateHoldTriggerKey(key.id, key.copyWith(enabled: enabled));
  }

  void _deleteKey(HoldTriggerKey key) {
    final state = context.read<AppState>();
    state.removeHoldTriggerKey(key.id);
  }

  Future<List<WindowInfo>> _refreshWindows() async {
    if (!Platform.isWindows) return [];
    try {
      final result = await _platformChannel.invokeMethod('enumerateWindows');
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
      return list;
    } catch (_) {
      return [];
    }
  }

  Future<(int, int)?> _pickCoordinates(int hwnd) async {
    if (hwnd == 0) return null;
    final wasOnTop = context.read<AppState>().alwaysOnTop;
    // Must cancel alwaysOnTop first, otherwise the TOPMOST Flutter window
    // still covers the overlay even when minimized.
    if (Platform.isWindows) {
      try {
        if (wasOnTop) await _platformChannel.invokeMethod('setAlwaysOnTop', [false]);
        await _platformChannel.invokeMethod('minimizeWindow');
      } catch (_) {}
    }
    try { await _platformChannel.invokeMethod('setForegroundWindow', [hwnd]); } catch (_) {}

    try {
      final result = await ScreenOverlayService.instance.startWindowPick(hwnd);
      // Restore clicker window
      if (Platform.isWindows) {
        try {
          if (wasOnTop) await _platformChannel.invokeMethod('setAlwaysOnTop', [true]);
          await _platformChannel.invokeMethod('bringToFront');
        } catch (_) {}
      }
      return result;
    } catch (_) {
      // Restore clicker window on error too
      if (Platform.isWindows) {
        try {
          if (wasOnTop) await _platformChannel.invokeMethod('setAlwaysOnTop', [true]);
          await _platformChannel.invokeMethod('bringToFront');
        } catch (_) {}
      }
      return null;
    }
  }

  void _showEditDialog(HoldTriggerKey key, {required bool isNew}) {
    final isDark = FluentTheme.of(context).brightness == Brightness.dark;

    // Local editing state
    var triggerKey = key.triggerKey;
    var triggerType = key.triggerType;
    var triggerMouseButton = key.triggerMouseButton;
    var action = key.action;
    var mouseButton = key.mouseButton;
    var keyToRepeat = key.keyToRepeat;
    var comboKeys = List<String>.from(key.comboKeys);
    var intervalMs = key.intervalMs;
    var enabled = key.enabled;
    var backgroundMode = key.backgroundMode;
    var targetHwnd = key.targetHwnd;
    var targetX = key.targetX;
    var targetY = key.targetY;
    var targetWindowTitle = key.targetWindowTitle;
    var listeningTrigger = false;
    var listeningRepeat = false;
    var listeningCombo = false;
    var windows = <WindowInfo>[];
    var loadingWindows = false;
    var pickingCoords = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => ContentDialog(
          title: Text(isNew ? '添加按住触发按键' : '编辑按住触发按键'),
          constraints: const BoxConstraints(maxWidth: 480),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Trigger type
            Text('触发方式', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: isDark ? const Color(0xFF9090B0) : const Color(0xFF6A6A80))),
            const SizedBox(height: 6),
            ComboBox<HoldTriggerType>(
              value: triggerType,
              items: HoldTriggerType.values.map((t) => ComboBoxItem<HoldTriggerType>(
                value: t,
                child: Text(t == HoldTriggerType.keyboard ? '键盘按键' : '鼠标按键'),
              )).toList(),
              onChanged: (v) {
                if (v != null) setDialogState(() => triggerType = v);
              },
            ),

            const SizedBox(height: 14),

            // Trigger key (keyboard mode)
            if (triggerType == HoldTriggerType.keyboard) ...[
              Text('触发按键', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: isDark ? const Color(0xFF9090B0) : const Color(0xFF6A6A80))),
              const SizedBox(height: 6),
              Row(children: [
                Expanded(child: Button(
                  onPressed: () {
                    setDialogState(() => listeningTrigger = true);
                    context.read<AppState>().captureKey().then((captured) {
                      if (captured != null && captured.isNotEmpty) {
                        setDialogState(() {
                          triggerKey = captured;
                          listeningTrigger = false;
                        });
                      } else {
                        setDialogState(() => listeningTrigger = false);
                      }
                    });
                  },
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(listeningTrigger ? '按下任意键...' : _displayName(triggerKey), style: const TextStyle(fontWeight: FontWeight.w600)),
                    if (!listeningTrigger) ...[
                      const SizedBox(width: 6),
                      const Icon(FluentIcons.edit, size: 10),
                    ],
                  ]),
                )),
              ]),
            ],

            // Trigger mouse button (mouse mode)
            if (triggerType == HoldTriggerType.mouse) ...[
              Text('触发鼠标按键', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: isDark ? const Color(0xFF9090B0) : const Color(0xFF6A6A80))),
              const SizedBox(height: 6),
              ComboBox<String>(
                value: ['left', 'right', 'middle', 'x1', 'x2'].contains(triggerMouseButton) ? triggerMouseButton : 'left',
                items: const [
                  ComboBoxItem(value: 'left', child: Text('左键')),
                  ComboBoxItem(value: 'right', child: Text('右键')),
                  ComboBoxItem(value: 'middle', child: Text('中键')),
                  ComboBoxItem(value: 'x1', child: Text('侧键1')),
                  ComboBoxItem(value: 'x2', child: Text('侧键2')),
                ],
                onChanged: (v) {
                  if (v != null) setDialogState(() => triggerMouseButton = v);
                },
              ),
            ],

            const SizedBox(height: 14),

            // Action type
            Text('动作类型', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: isDark ? const Color(0xFF9090B0) : const Color(0xFF6A6A80))),
            const SizedBox(height: 6),
            ComboBox<HoldTriggerAction>(
              value: action,
              items: HoldTriggerAction.values.map((a) => ComboBoxItem<HoldTriggerAction>(
                value: a,
                child: Text(_actionLabel(a)),
              )).toList(),
              onChanged: (v) {
                if (v != null) setDialogState(() => action = v);
              },
            ),

            const SizedBox(height: 14),

            // Action-specific settings
            if (action == HoldTriggerAction.mouseClick) ...[
              Text('鼠标按键', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: isDark ? const Color(0xFF9090B0) : const Color(0xFF6A6A80))),
              const SizedBox(height: 6),
              ComboBox<String>(
                value: ['left', 'right', 'middle', 'x1', 'x2'].contains(mouseButton) ? mouseButton : 'left',
                items: const [
                  ComboBoxItem(value: 'left', child: Text('左键')),
                  ComboBoxItem(value: 'right', child: Text('右键')),
                  ComboBoxItem(value: 'middle', child: Text('中键')),
                  ComboBoxItem(value: 'x1', child: Text('侧键1')),
                  ComboBoxItem(value: 'x2', child: Text('侧键2')),
                ],
                onChanged: (v) {
                  if (v != null) setDialogState(() => mouseButton = v);
                },
              ),
            ],

            if (action == HoldTriggerAction.keyRepeat) ...[
              Text('重复按键', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: isDark ? const Color(0xFF9090B0) : const Color(0xFF6A6A80))),
              const SizedBox(height: 6),
              Row(children: [
                Expanded(child: Button(
                  onPressed: () {
                    setDialogState(() => listeningRepeat = true);
                    context.read<AppState>().captureKey().then((captured) {
                      if (captured != null && captured.isNotEmpty) {
                        setDialogState(() {
                          keyToRepeat = captured;
                          listeningRepeat = false;
                        });
                      } else {
                        setDialogState(() => listeningRepeat = false);
                      }
                    });
                  },
                  child: Text(listeningRepeat ? '按下任意键...' : _displayName(keyToRepeat)),
                )),
              ]),
            ],

            if (action == HoldTriggerAction.keyCombo) ...[
              Text('组合键 (依次点击添加)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: isDark ? const Color(0xFF9090B0) : const Color(0xFF6A6A80))),
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 4, children: [
                ...comboKeys.map((k) => Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: FluentTheme.of(context).accentColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: FluentTheme.of(context).accentColor.withValues(alpha: 0.3)),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(_displayName(k), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                    const SizedBox(width: 4),
                    GestureDetector(
                      onTap: () => setDialogState(() => comboKeys.remove(k)),
                      child: const Icon(FluentIcons.chrome_close, size: 8),
                    ),
                  ]),
                )),
                Button(
                  onPressed: () {
                    setDialogState(() => listeningCombo = true);
                    context.read<AppState>().captureKey().then((captured) {
                      if (captured != null && captured.isNotEmpty) {
                        setDialogState(() {
                          comboKeys.add(captured);
                          listeningCombo = false;
                        });
                      } else {
                        setDialogState(() => listeningCombo = false);
                      }
                    });
                  },
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(FluentIcons.add, size: 10),
                    const SizedBox(width: 4),
                    Text(listeningCombo ? '...' : '添加'),
                  ]),
                ),
              ]),
            ],

            const SizedBox(height: 14),

            // Interval
            Text('间隔 ${intervalMs.toInt()}ms', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: isDark ? const Color(0xFF9090B0) : const Color(0xFF6A6A80))),
            AppSlider(
              value: intervalMs,
              min: 10,
              max: 5000,
              divisions: 499,
              label: '${intervalMs.toInt()}ms',
              onChanged: (v) => setDialogState(() => intervalMs = v),
            ),

            const SizedBox(height: 6),

            // Background mode
            Row(children: [
              Checkbox(
                checked: backgroundMode,
                onChanged: (v) => setDialogState(() => backgroundMode = v ?? false),
              ),
              const SizedBox(width: 8),
              const Text('后台模式', style: TextStyle(fontSize: 13)),
            ]),

            // Background mode settings: window selection + coordinate picking
            if (backgroundMode) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E1E38).withValues(alpha: 0.6) : const Color(0xFFE8E8F4).withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: isDark ? const Color(0xFF303050) : const Color(0xFFD0D0E0)),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  // Window selection
                  Text('目标窗口', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: isDark ? const Color(0xFF9090B0) : const Color(0xFF6A6A80))),
                  const SizedBox(height: 6),
                  Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Expanded(
                      child: ComboBox<int>(
                        isExpanded: true,
                        placeholder: Text(targetWindowTitle.isEmpty ? '选择目标窗口' : targetWindowTitle, style: const TextStyle(fontSize: 12)),
                        items: windows.map((w) => ComboBoxItem<int>(
                          value: w.hwnd,
                          child: Text(w.title.length > 40 ? '${w.title.substring(0, 40)}...' : w.title,
                            style: const TextStyle(fontSize: 12)),
                        )).toList(),
                        value: windows.any((w) => w.hwnd == targetHwnd) ? targetHwnd : null,
                        onChanged: (hwnd) {
                          if (hwnd != null) {
                            final win = windows.firstWhere((w) => w.hwnd == hwnd);
                            setDialogState(() {
                              targetHwnd = hwnd;
                              targetWindowTitle = win.title;
                            });
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Button(
                      onPressed: loadingWindows ? null : () async {
                        setDialogState(() => loadingWindows = true);
                        final list = await _refreshWindows();
                        setDialogState(() {
                          windows = list;
                          loadingWindows = false;
                        });
                      },
                      child: loadingWindows
                        ? const SizedBox(width: 14, height: 14, child: ProgressRing(strokeWidth: 2))
                        : const Icon(FluentIcons.refresh, size: 14),
                    ),
                  ]),
                  const SizedBox(height: 10),

                  // Click coordinates
                  Text('点击坐标（相对目标窗口客户区）', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: isDark ? const Color(0xFF9090B0) : const Color(0xFF6A6A80))),
                  const SizedBox(height: 6),
                  Row(children: [
                    SizedBox(
                      width: 80,
                      child: TextBox(
                        placeholder: 'X',
                        controller: TextEditingController(text: targetX.toString()),
                        onChanged: (v) {
                          final val = int.tryParse(v);
                          if (val != null) setDialogState(() => targetX = val);
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 80,
                      child: TextBox(
                        placeholder: 'Y',
                        controller: TextEditingController(text: targetY.toString()),
                        onChanged: (v) {
                          final val = int.tryParse(v);
                          if (val != null) setDialogState(() => targetY = val);
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Button(
                      onPressed: (targetHwnd != 0 && !pickingCoords) ? () async {
                        setDialogState(() => pickingCoords = true);
                        final result = await _pickCoordinates(targetHwnd);
                        if (result != null) {
                          setDialogState(() {
                            targetX = result.$1;
                            targetY = result.$2;
                            pickingCoords = false;
                          });
                        } else {
                          setDialogState(() => pickingCoords = false);
                        }
                      } : null,
                      child: pickingCoords
                        ? const SizedBox(width: 14, height: 14, child: ProgressRing(strokeWidth: 2))
                        : Row(mainAxisSize: MainAxisSize.min, children: [
                            const Icon(FluentIcons.map_pin, size: 14),
                            const SizedBox(width: 4),
                            Text('选取', style: TextStyle(fontSize: 12, color: targetHwnd != 0 ? null : (isDark ? const Color(0xFF606080) : const Color(0xFFB0B0C0)))),
                          ]),
                    ),
                  ]),
                ]),
              ),
            ],

            const SizedBox(height: 4),

            // Enabled
            Row(children: [
              Checkbox(
                checked: enabled,
                onChanged: (v) => setDialogState(() => enabled = v ?? true),
              ),
              const SizedBox(width: 8),
              const Text('启用', style: TextStyle(fontSize: 13)),
            ]),
          ]),
          ),
          actions: [
            Button(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                final updated = HoldTriggerKey(
                  id: key.id,
                  triggerKey: triggerKey,
                  triggerType: triggerType,
                  triggerMouseButton: triggerMouseButton,
                  enabled: enabled,
                  action: action,
                  mouseButton: mouseButton,
                  keyToRepeat: keyToRepeat,
                  comboKeys: comboKeys,
                  intervalMs: intervalMs,
                  backgroundMode: backgroundMode,
                  targetHwnd: targetHwnd,
                  targetX: targetX,
                  targetY: targetY,
                  targetWindowTitle: targetWindowTitle,
                );
                final state = context.read<AppState>();
                if (isNew) {
                  state.addHoldTriggerKey(updated);
                } else {
                  state.updateHoldTriggerKey(key.id, updated);
                }
                Navigator.pop(ctx);
              },
              child: Text(isNew ? '添加' : '保存'),
            ),
          ],
        ),
      ),
    );
  }

  String _actionLabel(HoldTriggerAction action) {
    switch (action) {
      case HoldTriggerAction.mouseClick:
        return '鼠标点击';
      case HoldTriggerAction.keyRepeat:
        return '按键重复';
      case HoldTriggerAction.keyCombo:
        return '组合键';
    }
  }
}
