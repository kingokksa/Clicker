/// Mobile hold trigger page — long-press on screen to auto-repeat actions.
/// Adapted from desktop HoldTriggerPage for touch-based interaction.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/mobile_app_state.dart';
import '../../models/hold_trigger_key.dart';

class MobileHoldTriggerPage extends StatelessWidget {
  const MobileHoldTriggerPage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<MobileAppState>();
    final keys = state.holdTriggerKeys;
    final isDark = state.themeMode == 'dark';
    final accent = state.accentColor;

    return Scaffold(
      appBar: AppBar(
        title: const Text('按住触发'),
        centerTitle: true,
      ),
      body: keys.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.touch_app_outlined, size: 48,
                      color: isDark ? Colors.white30 : Colors.black26),
                  const SizedBox(height: 12),
                  Text('暂无触发项',
                      style: TextStyle(
                          fontSize: 15, color: isDark ? Colors.white38 : Colors.black38)),
                  const SizedBox(height: 8),
                  Text('长按屏幕可触发自动重复操作',
                      style: TextStyle(
                          fontSize: 12, color: isDark ? Colors.white24 : Colors.black26)),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              itemCount: keys.length,
              itemBuilder: (ctx, i) => _TriggerCard(
                triggerKey: keys[i],
                isDark: isDark,
                accent: accent,
                onToggle: (v) => state.updateHoldTriggerKey(
                    keys[i].id, keys[i].copyWith(enabled: v)),
                onDelete: () => state.removeHoldTriggerKey(keys[i].id),
                onEdit: () => _showEditDialog(context, state, keys[i], isDark, accent),
              ),
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddDialog(context, state, isDark, accent),
        child: const Icon(Icons.add),
      ),
    );
  }

  void _showAddDialog(BuildContext context, MobileAppState state,
      bool isDark, Color accent) {
    final key = HoldTriggerKey(
      triggerKey: '长按',
      triggerType: HoldTriggerType.mouse,
      action: HoldTriggerAction.mouseClick,
      mouseButton: 'left',
      intervalMs: 50,
    );
    _showEditDialog(context, state, key, isDark, accent, isNew: true);
  }

  void _showEditDialog(BuildContext context, MobileAppState state,
      HoldTriggerKey key, bool isDark, Color accent, {bool isNew = false}) {
    var action = key.action;
    var mouseButton = key.mouseButton;
    var keyToRepeat = key.keyToRepeat;
    var intervalMs = key.intervalMs;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(isNew ? '添加触发项' : '编辑触发项'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Action type
              const Text('触发动作', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              _buildChipGroup<HoldTriggerAction>(
                selected: action,
                options: [
                  (HoldTriggerAction.mouseClick, '鼠标点击'),
                  (HoldTriggerAction.keyRepeat, '按键重复'),
                ],
                accent: accent,
                onSelect: (v) => setDialogState(() => action = v),
              ),
              const SizedBox(height: 12),

              // Action params
              if (action == HoldTriggerAction.mouseClick) ...[
                const Text('鼠标按钮', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                _buildChipGroup<String>(
                  selected: mouseButton,
                  options: [
                    ('left', '左键'),
                    ('right', '右键'),
                    ('middle', '中键'),
                  ],
                  accent: accent,
                  onSelect: (v) => setDialogState(() => mouseButton = v),
                ),
              ],
              if (action == HoldTriggerAction.keyRepeat) ...[
                const Text('重复按键', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                TextField(
                  decoration: const InputDecoration(
                    hintText: '按键名称，如 space, A, 1',
                    isDense: true,
                  ),
                  controller: TextEditingController(text: keyToRepeat)
                    ..selection = TextSelection.collapsed(offset: keyToRepeat.length),
                  onChanged: (v) => keyToRepeat = v,
                ),
              ],
              const SizedBox(height: 12),

              // Interval
              const Text('重复间隔 (ms)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              TextField(
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(hintText: '10 ~ 600000', isDense: true),
                controller: TextEditingController(text: intervalMs.round().toString()),
                onChanged: (v) {
                  final val = int.tryParse(v);
                  if (val != null && val > 0) intervalMs = val.clamp(10, 600000).toDouble();
                },
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            TextButton(
              onPressed: () {
                final updated = key.copyWith(
                  action: action,
                  mouseButton: mouseButton,
                  keyToRepeat: keyToRepeat,
                  intervalMs: intervalMs,
                );
                if (isNew) {
                  state.addHoldTriggerKey(updated);
                } else {
                  state.updateHoldTriggerKey(key.id, updated);
                }
                Navigator.pop(ctx);
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChipGroup<T>({
    required T selected,
    required List<(T, String)> options,
    required Color accent,
    required ValueChanged<T> onSelect,
  }) {
    return Wrap(
      spacing: 6,
      children: options.map((opt) {
        final isSelected = opt.$1 == selected;
        return ChoiceChip(
          label: Text(opt.$2),
          selected: isSelected,
          selectedColor: accent.withValues(alpha: 0.2),
          side: BorderSide(color: isSelected ? accent : Colors.grey.shade400),
          onSelected: (_) => onSelect(opt.$1),
        );
      }).toList(),
    );
  }
}

class _TriggerCard extends StatelessWidget {
  final HoldTriggerKey triggerKey;
  final bool isDark;
  final Color accent;
  final ValueChanged<bool> onToggle;
  final VoidCallback onDelete;
  final VoidCallback onEdit;

  const _TriggerCard({
    required this.triggerKey,
    required this.isDark,
    required this.accent,
    required this.onToggle,
    required this.onDelete,
    required this.onEdit,
  });

  String get _actionLabel {
    switch (triggerKey.action) {
      case HoldTriggerAction.mouseClick:
        const btnNames = {'left': '左键', 'right': '右键', 'middle': '中键'};
        return '点击${btnNames[triggerKey.mouseButton] ?? triggerKey.mouseButton}';
      case HoldTriggerAction.keyRepeat:
        return '重复 ${triggerKey.keyToRepeat}';
      case HoldTriggerAction.keyCombo:
        return '组合键 ${triggerKey.comboKeys.join("+")}';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      color: isDark ? const Color(0xFF22223A) : Colors.white,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(children: [
          // Enable switch
          Switch(value: triggerKey.enabled, activeThumbColor: accent, onChanged: onToggle),
          const SizedBox(width: 8),

          // Info
          Expanded(child: GestureDetector(
            onTap: onEdit,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_actionLabel,
                  style: TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : Colors.black87)),
              const SizedBox(height: 2),
              Text('间隔 ${triggerKey.intervalMs.round()}ms',
                  style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.white54 : Colors.black45)),
            ]),
          )),

          // Delete
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 18),
            color: Colors.red.shade300,
            onPressed: onDelete,
          ),
        ]),
      ),
    );
  }
}
