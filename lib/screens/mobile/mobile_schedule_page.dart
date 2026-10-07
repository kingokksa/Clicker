
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/clicker_config.dart';
import '../../services/mobile_app_state.dart';
import '../../services/schedule_controller.dart';

class MobileSchedulePage extends StatelessWidget {
  const MobileSchedulePage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<MobileAppState>();
    final tasks = state.clickerConfig.schedules;
    final isDark = state.themeMode == 'dark';
    final accent = state.accentColor;
    final subColor = isDark ? Colors.white54 : Colors.black54;

    return Scaffold(
      appBar: AppBar(
        title: const Text('定时任务'),
        centerTitle: true,
        backgroundColor: isDark ? const Color(0xFF1A1A2E) : accent.withValues(alpha: 0.1),
        foregroundColor: isDark ? Colors.white : accent,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Text(
            '到点自动执行动作：先配置动作与时间，再打开「启用」开关布防',
            style: TextStyle(fontSize: 12, color: subColor),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: Text('共 ${tasks.length} 个任务',
                  style: TextStyle(fontSize: 13, color: subColor)),
            ),
            FilledButton.icon(
              onPressed: state.addSchedule,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('添加任务'),
            ),
          ]),
          const SizedBox(height: 12),
          if (tasks.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 48),
              child: Center(
                child: Text('还没有任务',
                    style: TextStyle(fontSize: 13, color: subColor)),
              ),
            ),
          for (var i = 0; i < tasks.length; i++) ...[
            _ScheduleCard(
              index: i,
              task: tasks[i],
              state: state,
              isDark: isDark,
              accent: accent,
              onDelete: () => state.removeScheduleAt(i),
            ),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

class _ScheduleCard extends StatelessWidget {
  final int index;
  final ClickerSchedule task;
  final MobileAppState state;
  final bool isDark;
  final Color accent;
  final VoidCallback onDelete;

  const _ScheduleCard({
    required this.index,
    required this.task,
    required this.state,
    required this.isDark,
    required this.accent,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final subColor = isDark ? Colors.white54 : Colors.black54;
    final macros = state.macros;

    void update(ClickerSchedule ns, {bool rearm = false}) {
      state.updateScheduleAt(index, ns, rearm: rearm);
    }

    void setAction(ScheduleAction a) {
      var ns = task.copyWith(action: a);
      if (a == ScheduleAction.playMacro && ns.macroId == null && macros.isNotEmpty) {
        ns = ns.copyWith(macroId: macros.first.id);
      }
      if (a != ScheduleAction.playMacro) ns = ns.copyWith(clearMacroId: true);
      update(ns, rearm: true);
    }

    return Card(
      color: isDark ? const Color(0xFF22223A) : Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text('任务 ${index + 1}',
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(task.action.label,
                  style: TextStyle(fontSize: 12, color: subColor),
                  overflow: TextOverflow.ellipsis),
            ),
            IconButton(
              onPressed: onDelete,
              icon: Icon(Icons.delete_outline,
                  size: 18, color: isDark ? const Color(0xFFE06666) : const Color(0xFFC0392B)),
              tooltip: '删除',
              visualDensity: VisualDensity.compact,
            ),
          ]),
          const SizedBox(height: 8),

          Row(children: [
            const SizedBox(width: 60, child: Text('动作', style: TextStyle(fontSize: 13))),
            Expanded(child: _dropdown<ScheduleAction>(
              value: task.action,
              isDark: isDark,
              items: ScheduleAction.values
                  .map((a) => DropdownMenuItem<ScheduleAction>(
                      value: a, child: Text(a.label, style: const TextStyle(fontSize: 13))))
                  .toList(),
              onChanged: (v) {
                if (v != null) setAction(v);
              },
            )),
          ]),

          if (task.action == ScheduleAction.playMacro) ...[
            const SizedBox(height: 8),
            Row(children: [
              const SizedBox(width: 60, child: Text('宏', style: TextStyle(fontSize: 13))),
              Expanded(
                child: macros.isEmpty
                    ? Text('暂无宏',
                        style: TextStyle(fontSize: 12, color: subColor))
                    : _dropdown<String>(
                        value: macros
                            .firstWhere((m) => m.id == task.macroId,
                                orElse: () => macros.first)
                            .id,
                        isDark: isDark,
                        items: macros
                            .map((m) => DropdownMenuItem<String>(
                                value: m.id, child: Text(m.name, style: const TextStyle(fontSize: 13))))
                            .toList(),
                        onChanged: (v) {
                          if (v != null) update(task.copyWith(macroId: v));
                        },
                      ),
              ),
            ]),
          ],

          const SizedBox(height: 8),

          Row(children: [
            const SizedBox(width: 60, child: Text('时间', style: TextStyle(fontSize: 13))),
            _chip('时间点', task.timing == ScheduleTiming.clock, accent, isDark,
                () => update(task.copyWith(timing: ScheduleTiming.clock), rearm: true)),
            const SizedBox(width: 6),
            _chip('倒计时', task.timing == ScheduleTiming.countdown, accent, isDark,
                () => update(task.copyWith(timing: ScheduleTiming.countdown), rearm: true)),
          ]),

          if (task.timing == ScheduleTiming.clock) ...[
            const SizedBox(height: 8),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const SizedBox(width: 60, child: Text('重复', style: TextStyle(fontSize: 13))),
              Expanded(child: Wrap(spacing: 6, runSpacing: 6, children: [
                _chip('仅一次', task.repeat == ScheduleRepeat.once, accent, isDark,
                    () => update(task.copyWith(repeat: ScheduleRepeat.once), rearm: true)),
                _chip('每天', task.repeat == ScheduleRepeat.daily, accent, isDark,
                    () => update(task.copyWith(repeat: ScheduleRepeat.daily), rearm: true)),
                _chip('每周', task.repeat == ScheduleRepeat.weekly, accent, isDark,
                    () => update(task.copyWith(repeat: ScheduleRepeat.weekly), rearm: true)),
                _chip('工作日', task.repeat == ScheduleRepeat.weekdays, accent, isDark,
                    () => update(task.copyWith(repeat: ScheduleRepeat.weekdays), rearm: true)),
                _chip('间隔', task.repeat == ScheduleRepeat.interval, accent, isDark,
                    () => update(task.copyWith(repeat: ScheduleRepeat.interval), rearm: true)),
              ])),
            ]),
            if (task.repeat == ScheduleRepeat.weekly) ...[
              const SizedBox(height: 8),
              Row(children: [
                const SizedBox(width: 60, child: Text('星期', style: TextStyle(fontSize: 13))),
                Expanded(child: Wrap(spacing: 6, runSpacing: 6, children: [
                  for (var d = 1; d <= 7; d++)
                    _chip(_weekdayLabel(d), task.weekday == d, accent, isDark,
                        () => update(task.copyWith(weekday: d), rearm: true)),
                ])),
              ]),
            ],
          ],

          const SizedBox(height: 10),

          if (task.timing == ScheduleTiming.clock && task.repeat == ScheduleRepeat.interval)
            Row(children: [
              const SizedBox(width: 60, child: Text('间隔', style: TextStyle(fontSize: 13))),
              _numBox(task.intervalMinutes, isDark, (v) {
                if (v > 0) update(task.copyWith(intervalMinutes: v), rearm: true);
              }, width: 64),
              const SizedBox(width: 6),
              const Text('分钟触发', style: TextStyle(fontSize: 13)),
            ])
          else if (task.timing == ScheduleTiming.clock)
            Row(children: [
              const SizedBox(width: 60, child: Text('时刻', style: TextStyle(fontSize: 13))),
              _numBox(task.hour, isDark, (v) => update(task.copyWith(hour: v % 24), rearm: true)),
              const SizedBox(width: 6),
              const Text('时', style: TextStyle(fontSize: 13)),
              const SizedBox(width: 10),
              _numBox(task.minute, isDark, (v) => update(task.copyWith(minute: v % 60), rearm: true)),
              const SizedBox(width: 6),
              const Text('分', style: TextStyle(fontSize: 13)),
            ])
          else
            Row(children: [
              const SizedBox(width: 60, child: Text('延迟', style: TextStyle(fontSize: 13))),
              _numBox(task.afterMinutes, isDark, (v) {
                if (v > 0) update(task.copyWith(afterMinutes: v), rearm: true);
              }, width: 64),
              const SizedBox(width: 6),
              const Text('分钟后触发', style: TextStyle(fontSize: 13)),
            ]),

          const SizedBox(height: 6),
          Row(children: [
            const SizedBox(width: 60, child: Text('启用', style: TextStyle(fontSize: 13))),
            Switch(
              value: task.enabled,
              onChanged: (v) => update(
                task.copyWith(enabled: v, fireAtEpochMs: v ? task.fireAtEpochMs : 0),
                rearm: v,
              ),
            ),
          ]),

          if (task.enabled) ...[
            const SizedBox(height: 4),
            Row(children: [
              const SizedBox(width: 60),
              Icon(Icons.info_outline, size: 14, color: subColor),
              const SizedBox(width: 6),
              Expanded(
                child: Text('下次触发：${ScheduleController.formatFireAt(task.fireAtEpochMs)}',
                    style: TextStyle(fontSize: 12, color: subColor)),
              ),
            ]),
          ],
        ]),
      ),
    );
  }

  Widget _dropdown<T>({
    required T value,
    required bool isDark,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF303050) : const Color(0xFFF0F0F8),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: isDark ? const Color(0xFF404060) : const Color(0xFFD8D8E0)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          items: items,
          onChanged: onChanged,
          isExpanded: true,
          isDense: true,
          style: TextStyle(fontSize: 13, color: isDark ? Colors.white : Colors.black87),
          dropdownColor: isDark ? const Color(0xFF2A2A44) : Colors.white,
        ),
      ),
    );
  }

  String _weekdayLabel(int weekday) =>
      const ['一', '二', '三', '四', '五', '六', '日'][weekday - 1];

  Widget _chip(String label, bool selected, Color accent, bool isDark, VoidCallback onTap) {
    final unselectedBg = isDark ? const Color(0xFF303050) : const Color(0xFFE8E8F0);
    final unselectedBorder = isDark ? const Color(0xFF404060) : const Color(0xFFD0D0D8);
    final unselectedText = isDark ? const Color(0xFFC0C0D8) : const Color(0xFF5A5A70);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? accent.withValues(alpha: 0.2) : unselectedBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: selected ? accent : unselectedBorder),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
            color: selected ? accent : unselectedText,
          ),
        ),
      ),
    );
  }

  Widget _numBox(int value, bool isDark, ValueChanged<int> onChanged,
      {double width = 52}) {
    return SizedBox(
      width: width,
      height: 36,
      child: TextField(
        controller: TextEditingController(text: value.toString()),
        textAlign: TextAlign.center,
        keyboardType: TextInputType.number,
        style: TextStyle(fontSize: 13, color: isDark ? Colors.white : Colors.black87),
        decoration: InputDecoration(
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          filled: true,
          fillColor: isDark ? const Color(0xFF303050) : const Color(0xFFF0F0F8),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: BorderSide.none,
          ),
        ),
        onChanged: (v) {
          final p = int.tryParse(v);
          if (p != null && p >= 0) onChanged(p);
        },
      ),
    );
  }
}
