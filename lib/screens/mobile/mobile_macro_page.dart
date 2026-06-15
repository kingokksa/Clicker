/// Mobile macro page — Material Design macro recording, playback, and editing.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/mobile_app_state.dart';
import '../../models/macro_model.dart';

class MobileMacroPage extends StatelessWidget {
  const MobileMacroPage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<MobileAppState>();
    final isDark = state.themeMode == 'dark';
    final accent = state.accentColor;
    final isRecording = state.isRecording;
    final isPlaying = state.isPlaying;

    return Scaffold(
      appBar: AppBar(
        title: const Text('宏'),
        centerTitle: true,
        backgroundColor: isDark ? const Color(0xFF1A1A2E) : accent.withValues(alpha: 0.1),
        foregroundColor: isDark ? Colors.white : accent,
        elevation: 0,
        actions: [
          if (!isRecording && !isPlaying)
            IconButton(
              icon: const Icon(Icons.fiber_manual_record),
              tooltip: '录制',
              onPressed: () async {
                await state.startRecording();
              },
            ),
          if (isRecording)
            IconButton(
              icon: const Icon(Icons.stop),
              tooltip: '停止录制',
              onPressed: () async {
                await state.stopRecording();
              },
            ),
          if (isRecording)
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: '取消录制',
              onPressed: () => state.cancelRecording(),
            ),
          if (isPlaying)
            IconButton(
              icon: const Icon(Icons.stop_circle),
              tooltip: '停止播放',
              onPressed: () => state.stopMacro(),
            ),
        ],
      ),
      body: Column(children: [
        // Recording indicator
        if (isRecording)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: Colors.red.withValues(alpha: 0.15),
            child: Row(children: [
              const Icon(Icons.fiber_manual_record, color: Colors.red, size: 16),
              const SizedBox(width: 8),
              Text('录制中... ${state.recordingEventCount} 个事件',
                  style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w600)),
            ]),
          ),

        // Playback progress
        if (isPlaying)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: accent.withValues(alpha: 0.15),
            child: Row(children: [
              Icon(Icons.play_circle_filled, color: accent, size: 16),
              const SizedBox(width: 8),
              Text('播放中... ${state.playbackEventIndex + 1}/${state.playbackTotalEvents}',
                  style: TextStyle(color: accent, fontWeight: FontWeight.w600)),
            ]),
          ),

        // Error
        if (state.macroError.isNotEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: Colors.orange.withValues(alpha: 0.15),
            child: Text(state.macroError,
                style: const TextStyle(color: Colors.orange, fontSize: 13)),
          ),

        // Macro list
        Expanded(child: _buildMacroList(context, state, isDark, accent)),
      ]),
      floatingActionButton: !isRecording && !isPlaying
          ? FloatingActionButton(
              onPressed: () => _showCreateMacroDialog(context, state),
              backgroundColor: accent,
              child: const Icon(Icons.add, color: Colors.white),
            )
          : null,
    );
  }

  Widget _buildMacroList(BuildContext context, MobileAppState state,
      bool isDark, Color accent) {
    final macros = state.macros;
    if (macros.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.playlist_play, size: 48, color: isDark ? Colors.grey : Colors.grey),
          const SizedBox(height: 12),
          Text('暂无宏', style: TextStyle(fontSize: 15, color: isDark ? Colors.grey : Colors.grey)),
          const SizedBox(height: 8),
          Text('点击 + 创建宏，或使用录制按钮录制',
              style: TextStyle(fontSize: 13, color: isDark ? Colors.grey : Colors.grey)),
        ]),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      itemCount: macros.length,
      itemBuilder: (ctx, i) => _buildMacroCard(context, state, macros[i], isDark, accent),
    );
  }

  Widget _buildMacroCard(BuildContext context, MobileAppState state,
      MacroModel macro, bool isDark, Color accent) {
    final eventCount = macro.events.length;
    final duration = macro.totalDurationMs;

    return Card(
      color: isDark ? const Color(0xFF22223A) : Colors.white,
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        title: Text(macro.name,
            style: TextStyle(fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : Colors.black87)),
        subtitle: Text('$eventCount 个事件 | ${_formatDuration(duration)} | 重复 ${macro.repeatCount == 0 ? "无限" : "${macro.repeatCount}次"}',
            style: TextStyle(fontSize: 12,
                color: isDark ? Colors.grey : Colors.black54)),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          // Enable/disable toggle
          Switch(
            value: macro.enabled,
            activeThumbColor: accent,
            onChanged: (v) => state.updateMacro(macro.copyWith(enabled: v)),
          ),
          // Play button
          IconButton(
            icon: Icon(Icons.play_arrow, color: accent),
            onPressed: state.isPlaying ? null : () => state.playMacro(macro),
          ),
          // More options
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert, color: isDark ? Colors.grey : Colors.black54),
            onSelected: (action) {
              switch (action) {
                case 'edit':
                  _showEditMacroDialog(context, state, macro);
                  break;
                case 'rename':
                  _showRenameDialog(context, state, macro);
                  break;
                case 'delete':
                  _confirmDelete(context, state, macro);
                  break;
              }
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(value: 'edit', child: Text('编辑')),
              const PopupMenuItem(value: 'rename', child: Text('重命名')),
              const PopupMenuItem(value: 'delete', child: Text('删除')),
            ],
          ),
        ]),
      ),
    );
  }

  String _formatDuration(int ms) {
    if (ms >= 60000) return '${(ms / 60000).toStringAsFixed(1)}分钟';
    if (ms >= 1000) return '${(ms / 1000).toStringAsFixed(1)}秒';
    return '${ms}ms';
  }

  // ─── Create Macro Dialog ──────────────────────────────────

  void _showCreateMacroDialog(BuildContext context, MobileAppState state) {
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => _MobileMacroEditor(state: state, macro: null),
    ));
  }

  // ─── Edit Macro Dialog ────────────────────────────────────

  void _showEditMacroDialog(BuildContext context, MobileAppState state,
      MacroModel macro) {
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => _MobileMacroEditor(state: state, macro: macro),
    ));
  }

  // ─── Rename Dialog ────────────────────────────────────────

  void _showRenameDialog(BuildContext context, MobileAppState state,
      MacroModel macro) {
    final ctrl = TextEditingController(text: macro.name);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重命名'),
        content: TextField(controller: ctrl, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
            onPressed: () {
              if (ctrl.text.isNotEmpty) {
                state.renameMacro(macro, ctrl.text);
              }
              Navigator.pop(ctx);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  // ─── Delete Confirmation ──────────────────────────────────

  void _confirmDelete(BuildContext context, MobileAppState state,
      MacroModel macro) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除确认'),
        content: Text('确定要删除宏「${macro.name}」吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
            onPressed: () {
              state.deleteMacro(macro);
              Navigator.pop(ctx);
            },
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}

// ─── Macro Editor Page ──────────────────────────────────────

class _MobileMacroEditor extends StatefulWidget {
  final MobileAppState state;
  final MacroModel? macro; // null = new macro

  const _MobileMacroEditor({required this.state, this.macro});

  @override
  State<_MobileMacroEditor> createState() => _MobileMacroEditorState();
}

class _MobileMacroEditorState extends State<_MobileMacroEditor> {
  late List<MacroEvent> _events;
  late String _name;
  late int _repeatCount;
  late double _speed;
  late bool _enabled;

  @override
  void initState() {
    super.initState();
    final m = widget.macro;
    _name = m?.name ?? '新宏';
    _events = m != null ? List.from(m.events) : [];
    _repeatCount = m?.repeatCount ?? 1;
    _speed = m?.speed ?? 1.0;
    _enabled = m?.enabled ?? true;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.state.themeMode == 'dark';
    final accent = widget.state.accentColor;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.macro != null ? '编辑宏' : '新建宏'),
        centerTitle: true,
        backgroundColor: isDark ? const Color(0xFF1A1A2E) : accent.withValues(alpha: 0.1),
        foregroundColor: isDark ? Colors.white : accent,
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _save,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          // Name
          TextField(
            decoration: InputDecoration(
              labelText: '宏名称',
              labelStyle: TextStyle(color: isDark ? Colors.grey : null),
              border: const OutlineInputBorder(),
            ),
            controller: TextEditingController(text: _name),
            onChanged: (v) => _name = v,
          ),
          const SizedBox(height: 12),

          // Settings row
          Row(children: [
            Expanded(child: _settingCard('重复次数', _repeatCount == 0 ? '无限' : '$_repeatCount', isDark, () {
              _showRepeatDialog(isDark);
            })),
            const SizedBox(width: 8),
            Expanded(child: _settingCard('速度', '${_speed}x', isDark, () {
              _showSpeedDialog(isDark, accent);
            })),
            const SizedBox(width: 8),
            Expanded(child: _settingCard('启用', _enabled ? '开' : '关', isDark, () {
              setState(() => _enabled = !_enabled);
            })),
          ]),
          const SizedBox(height: 16),

          // Add event button
          Row(children: [
            Text('事件列表', style: TextStyle(fontWeight: FontWeight.w600,
                fontSize: 15, color: isDark ? Colors.white : Colors.black87)),
            const Spacer(),
            IconButton(
              icon: Icon(Icons.add_circle, color: accent),
              onPressed: () => _addEvent(isDark, accent),
            ),
          ]),

          const SizedBox(height: 4),

          // Event list
          if (_events.isEmpty)
            Center(child: Padding(
              padding: const EdgeInsets.all(32),
              child: Text('暂无事件，点击 + 添加',
                  style: TextStyle(color: isDark ? Colors.grey : Colors.grey)),
            )),

          ...List.generate(_events.length, (i) => _buildEventTile(i, isDark, accent)),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _settingCard(String label, String value, bool isDark, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Card(
        color: isDark ? const Color(0xFF22223A) : Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: TextStyle(fontSize: 11, color: isDark ? Colors.grey : Colors.black54)),
            const SizedBox(height: 2),
            Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : Colors.black87)),
          ]),
        ),
      ),
    );
  }

  Widget _buildEventTile(int index, bool isDark, Color accent) {
    final e = _events[index];
    final label = _eventLabel(e);

    return Dismissible(
      key: ValueKey('$index-${e.timestampMs}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        color: Colors.red,
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      onDismissed: (_) => setState(() => _events.removeAt(index)),
      child: Card(
        color: isDark ? const Color(0xFF22223A) : Colors.white,
        elevation: 0,
        margin: const EdgeInsets.symmetric(vertical: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        child: ListTile(
          dense: true,
          leading: Icon(_eventIcon(e.type), size: 18, color: accent),
          title: Text(label, style: TextStyle(fontSize: 13,
              color: isDark ? Colors.white70 : Colors.black87)),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            if (index > 0)
              IconButton(
                icon: Icon(Icons.arrow_upward, size: 16, color: isDark ? Colors.grey : Colors.black45),
                onPressed: () => setState(() {
                  final tmp = _events[index];
                  _events[index] = _events[index - 1];
                  _events[index - 1] = tmp;
                }),
              ),
            IconButton(
              icon: Icon(Icons.edit, size: 16, color: isDark ? Colors.grey : Colors.black45),
              onPressed: () => _editEvent(index, isDark, accent),
            ),
          ]),
        ),
      ),
    );
  }

  String _eventLabel(MacroEvent e) {
    String btnLabel(String? btn) => btn == 'right' ? '右键' : (btn == 'middle' ? '中键' : (btn == 'x1' ? '侧键1' : (btn == 'x2' ? '侧键2' : '左键')));
    switch (e.type) {
      case MacroEventType.mouseDown:
        return '${btnLabel(e.button)}按下 (${e.x}, ${e.y})';
      case MacroEventType.mouseUp:
        return '${btnLabel(e.button)}释放 (${e.x}, ${e.y})';
      case MacroEventType.click:
        return '${btnLabel(e.button)}点击 (${e.x}, ${e.y})';
      case MacroEventType.keyPress:
        return '按下 ${e.key ?? "?"}';
      case MacroEventType.keyRelease:
        return '释放 ${e.key ?? "?"}';
      case MacroEventType.scroll:
        final dir = (e.scrollDy ?? 0) > 0 ? '上' : '下';
        return '滚轮$dir';
      case MacroEventType.wait:
        final ms = e.timestampMs;
        if (ms >= 60000) return '等待 ${(ms / 60000).toStringAsFixed(1)} 分钟';
        if (ms >= 1000) return '等待 ${(ms / 1000).toStringAsFixed(1)} 秒';
        return '等待 $ms 毫秒';
      case MacroEventType.drag:
        return '拖拽 (${e.x},${e.y}) → (${e.endX},${e.endY})';
      case MacroEventType.swipe:
        return '滑动 (${e.x},${e.y}) → (${e.endX},${e.endY})';
    }
  }

  IconData _eventIcon(MacroEventType type) {
    switch (type) {
      case MacroEventType.mouseDown:
      case MacroEventType.mouseUp:
      case MacroEventType.click:
        return Icons.mouse;
      case MacroEventType.keyPress:
      case MacroEventType.keyRelease:
        return Icons.keyboard;
      case MacroEventType.scroll:
        return Icons.swap_vert;
      case MacroEventType.wait:
        return Icons.timer;
      case MacroEventType.drag:
        return Icons.open_with;
      case MacroEventType.swipe:
        return Icons.swipe;
    }
  }

  // ─── Add Event ────────────────────────────────────────────

  void _addEvent(bool isDark, Color accent) {
    String actionType = 'click';
    String clickButton = 'left';
    String? keyName;
    int waitMs = 500;
    double scrollDy = 3.0;
    int clickX = -1, clickY = -1;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('添加事件'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Event type
              Wrap(spacing: 6, children: [
                _dialogChip('点击', actionType == 'click', accent, () => setDialogState(() => actionType = 'click')),
                _dialogChip('按键', actionType == 'keyPress', accent, () => setDialogState(() => actionType = 'keyPress')),
                _dialogChip('滚轮', actionType == 'scroll', accent, () => setDialogState(() => actionType = 'scroll')),
                _dialogChip('等待', actionType == 'wait', accent, () => setDialogState(() => actionType = 'wait')),
              ]),
              const SizedBox(height: 12),

              if (actionType == 'click') ...[
                const Text('按钮:', style: TextStyle(fontSize: 12)),
                const SizedBox(height: 4),
                Wrap(spacing: 6, children: ['left', 'right', 'middle'].map((btn) {
                  final label = btn == 'left' ? '左键' : (btn == 'right' ? '右键' : '中键');
                  return _dialogChip(label, clickButton == btn, accent,
                      () => setDialogState(() => clickButton = btn));
                }).toList()),
              ],

              if (actionType == 'keyPress') ...[
                TextField(
                  decoration: const InputDecoration(labelText: '按键名称', border: OutlineInputBorder()),
                  onChanged: (v) => keyName = v,
                ),
              ],

              if (actionType == 'scroll') ...[
                Row(children: [
                  _dialogChip('上滚', scrollDy > 0, accent, () => setDialogState(() => scrollDy = 3.0)),
                  const SizedBox(width: 6),
                  _dialogChip('下滚', scrollDy < 0, accent, () => setDialogState(() => scrollDy = -3.0)),
                ]),
              ],

              if (actionType == 'wait') ...[
                TextField(
                  decoration: const InputDecoration(labelText: '等待时间(ms)', border: OutlineInputBorder()),
                  keyboardType: TextInputType.number,
                  controller: TextEditingController(text: waitMs.toString()),
                  onChanged: (v) {
                    final n = int.tryParse(v);
                    if (n != null) waitMs = n;
                  },
                ),
              ],
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            TextButton(
              onPressed: () {
                final baseTime = _events.isEmpty ? 0 : _events.last.timestampMs + 50;
                MacroEvent event;
                switch (actionType) {
                  case 'click':
                    event = MacroEvent(type: MacroEventType.click, timestampMs: baseTime, button: clickButton, x: clickX, y: clickY);
                    break;
                  case 'keyPress':
                    event = MacroEvent(type: MacroEventType.keyPress, timestampMs: baseTime, key: keyName ?? 'space');
                    break;
                  case 'scroll':
                    event = MacroEvent(type: MacroEventType.scroll, timestampMs: baseTime, scrollDx: 0, scrollDy: scrollDy);
                    break;
                  case 'wait':
                    event = MacroEvent(type: MacroEventType.wait, timestampMs: waitMs);
                    break;
                  default:
                    event = MacroEvent(type: MacroEventType.click, timestampMs: baseTime, button: clickButton);
                }
                setState(() => _events.add(event));
                Navigator.pop(ctx);
              },
              child: const Text('添加'),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Edit Event ───────────────────────────────────────────

  void _editEvent(int index, bool isDark, Color accent) {
    final e = _events[index];
    final holdCtrl = TextEditingController(text: e.holdMs.toString());
    final waitCtrl = TextEditingController(text: e.waitMs.toString());

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('编辑事件 - ${_eventLabel(e)}'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            const Text('按住(ms):', style: TextStyle(fontSize: 12)),
            const SizedBox(width: 8),
            SizedBox(width: 80, child: TextField(controller: holdCtrl, keyboardType: TextInputType.number)),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            const Text('等待(ms):', style: TextStyle(fontSize: 12)),
            const SizedBox(width: 8),
            SizedBox(width: 80, child: TextField(controller: waitCtrl, keyboardType: TextInputType.number)),
          ]),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
            onPressed: () {
              final newHoldMs = int.tryParse(holdCtrl.text) ?? e.holdMs;
              final newWaitMs = int.tryParse(waitCtrl.text) ?? e.waitMs;
              setState(() {
                _events[index] = e.copyWith(holdMs: newHoldMs, waitMs: newWaitMs);
              });
              Navigator.pop(ctx);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  // ─── Repeat Dialog ────────────────────────────────────────

  void _showRepeatDialog(bool isDark) {
    final ctrl = TextEditingController(text: _repeatCount == 0 ? '' : _repeatCount.toString());
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重复次数'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: ctrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(hintText: '0 = 无限'),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
            onPressed: () {
              setState(() => _repeatCount = int.tryParse(ctrl.text) ?? 1);
              Navigator.pop(ctx);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  // ─── Speed Dialog ─────────────────────────────────────────

  void _showSpeedDialog(bool isDark, Color accent) {
    double speed = _speed;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('播放速度'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('${speed.toStringAsFixed(1)}x', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            Slider(
              value: speed,
              min: 0.1, max: 10.0, divisions: 99,
              activeColor: accent,
              onChanged: (v) => setDialogState(() => speed = v),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            TextButton(
              onPressed: () {
                setState(() => _speed = speed);
                Navigator.pop(ctx);
              },
              child: const Text('确定'),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Save ─────────────────────────────────────────────────

  void _save() {
    if (_name.isEmpty) _name = '未命名宏';
    final macro = MacroModel(
      id: widget.macro?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
      name: _name,
      events: _events,
      repeatCount: _repeatCount,
      speed: _speed,
      enabled: _enabled,
      createdAt: widget.macro?.createdAt ?? DateTime.now(),
    );
    if (widget.macro != null) {
      widget.state.updateMacro(macro);
    } else {
      widget.state.saveMacroFromBuilder(macro);
    }
    Navigator.pop(context);
  }

  Widget _dialogChip(String label, bool selected, Color accent, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? accent.withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: selected ? accent : Colors.grey),
        ),
        child: Text(label, style: TextStyle(fontSize: 12,
            color: selected ? accent : Colors.grey,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal)),
      ),
    );
  }
}
