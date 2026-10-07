
import 'package:fluent_ui/fluent_ui.dart';
import 'package:provider/provider.dart';
import '../../models/clicker_config.dart';
import '../../services/app_state.dart';
import '../../services/schedule_controller.dart';

class SchedulePage extends StatelessWidget {
  const SchedulePage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final config = state.clickerConfig;
    final tasks = config.schedules;
    final isDark = FluentTheme.of(context).brightness == Brightness.dark;
    final subColor = isDark ? const Color(0xFF9090B0) : const Color(0xFF8A8A9A);

    return ScaffoldPage.scrollable(
      padding: const EdgeInsets.all(20),
      children: [
        Row(children: [
          Icon(FluentIcons.clock, size: 20, color: state.accentColor),
          const SizedBox(width: 10),
          const Text('定时任务', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(child: Text('共 ${tasks.length} 个任务', style: TextStyle(fontSize: 13, color: subColor))),
          Button(
            child: const Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(FluentIcons.add, size: 14),
              SizedBox(width: 6),
              Text('添加任务'),
            ]),
            onPressed: state.addSchedule,
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
            onDelete: () => state.removeScheduleAt(i),
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _ScheduleCard extends StatelessWidget {
  final int index;
  final ClickerSchedule task;
  final AppState state;
  final VoidCallback onDelete;
  const _ScheduleCard({
    required this.index,
    required this.task,
    required this.state,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = FluentTheme.of(context).brightness == Brightness.dark;
    final subColor = isDark ? const Color(0xFF9090B0) : const Color(0xFF8A8A9A);
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
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('任务 ${index + 1}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          const SizedBox(width: 10),
          Text(task.action.label, style: TextStyle(fontSize: 12, color: subColor)),
          const Spacer(),
          GestureDetector(
            onTap: onDelete,
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(FluentIcons.delete, size: 14, color: isDark ? const Color(0xFFE06666) : const Color(0xFFC0392B)),
                const SizedBox(width: 4),
                Text('删除', style: TextStyle(fontSize: 12, color: isDark ? const Color(0xFFE06666) : const Color(0xFFC0392B))),
              ]),
            ),
          ),
        ]),
        const SizedBox(height: 12),

        Row(children: [
          const SizedBox(width: 60, child: Text('动作', style: TextStyle(fontSize: 13))),
          Expanded(child: ComboBox<ScheduleAction>(
            value: task.action,
            isExpanded: true,
            items: ScheduleAction.values
                .map((a) => ComboBoxItem<ScheduleAction>(value: a, child: Text(a.label, style: const TextStyle(fontSize: 13))))
                .toList(),
            onChanged: (v) { if (v != null) setAction(v); },
          )),
          const SizedBox(width: 12),
          ToggleSwitch(
            checked: task.enabled,
            onChanged: (v) => update(task.copyWith(enabled: v, fireAtEpochMs: v ? task.fireAtEpochMs : 0), rearm: v),
          ),
        ]),
        const SizedBox(height: 6),

        if (task.action == ScheduleAction.playMacro) ...[
          Row(children: [
            const SizedBox(width: 60, child: Text('宏', style: TextStyle(fontSize: 13))),
            Expanded(child: macros.isEmpty
              ? _hint('暂无宏 — 请先在宏页面录制', isDark: isDark)
              : ComboBox<String>(
                  value: macros.any((m) => m.id == task.macroId) ? task.macroId : macros.first.id,
                  isExpanded: true,
                  items: macros.map((m) => ComboBoxItem<String>(value: m.id, child: Text(m.name, style: const TextStyle(fontSize: 13)))).toList(),
                  onChanged: (v) { if (v != null) update(task.copyWith(macroId: v)); },
                )),
          ]),
          const SizedBox(height: 6),
        ],

        Row(children: [
          const SizedBox(width: 60, child: Text('时间', style: TextStyle(fontSize: 13))),
          _chip(context, '时间点', task.timing == ScheduleTiming.clock, () => update(task.copyWith(timing: ScheduleTiming.clock), rearm: true)),
          const SizedBox(width: 6),
          _chip(context, '倒计时', task.timing == ScheduleTiming.countdown, () => update(task.copyWith(timing: ScheduleTiming.countdown), rearm: true)),
        ]),

        if (task.timing == ScheduleTiming.clock) ...[
          const SizedBox(height: 8),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SizedBox(width: 60, child: Text('重复', style: TextStyle(fontSize: 13))),
            Expanded(child: Wrap(spacing: 6, runSpacing: 6, children: [
              _chip(context, '仅一次', task.repeat == ScheduleRepeat.once, () => update(task.copyWith(repeat: ScheduleRepeat.once), rearm: true)),
              _chip(context, '每天', task.repeat == ScheduleRepeat.daily, () => update(task.copyWith(repeat: ScheduleRepeat.daily), rearm: true)),
              _chip(context, '每周', task.repeat == ScheduleRepeat.weekly, () => update(task.copyWith(repeat: ScheduleRepeat.weekly), rearm: true)),
              _chip(context, '工作日', task.repeat == ScheduleRepeat.weekdays, () => update(task.copyWith(repeat: ScheduleRepeat.weekdays), rearm: true)),
              _chip(context, '间隔', task.repeat == ScheduleRepeat.interval, () => update(task.copyWith(repeat: ScheduleRepeat.interval), rearm: true)),
            ])),
          ]),
          if (task.repeat == ScheduleRepeat.weekly) ...[
            const SizedBox(height: 8),
            Row(children: [
              const SizedBox(width: 60, child: Text('星期', style: TextStyle(fontSize: 13))),
              Expanded(child: Wrap(spacing: 6, runSpacing: 6, children: [
                for (var d = 1; d <= 7; d++)
                  _chip(context, _weekdayLabel(d), task.weekday == d, () => update(task.copyWith(weekday: d), rearm: true)),
              ])),
            ]),
          ],
        ],
        const SizedBox(height: 10),

        if (task.timing == ScheduleTiming.clock && task.repeat == ScheduleRepeat.interval)
          Row(children: [
            const SizedBox(width: 60),
            const Text('每隔', style: TextStyle(fontSize: 13)),
            const SizedBox(width: 8),
            SizedBox(width: 70, child: TextBox(
              controller: TextEditingController(text: task.intervalMinutes.toString()),
              textAlign: TextAlign.center,
              onChanged: (v) {
                final p = int.tryParse(v);
                if (p != null && p > 0) update(task.copyWith(intervalMinutes: p), rearm: true);
              },
            )),
            const Text(' 分钟触发', style: TextStyle(fontSize: 13)),
          ])
        else if (task.timing == ScheduleTiming.clock)
          Row(children: [
            const SizedBox(width: 60),
            const Text('时刻:', style: TextStyle(fontSize: 13)),
            const SizedBox(width: 8),
            _timeBox(task.hour, (v) => update(task.copyWith(hour: v % 24), rearm: true)),
            const Text(' 时 ', style: TextStyle(fontSize: 13)),
            _timeBox(task.minute, (v) => update(task.copyWith(minute: v % 60), rearm: true)),
            const Text(' 分', style: TextStyle(fontSize: 13)),
          ])
        else
          Row(children: [
            const SizedBox(width: 60),
            const Text('启用后', style: TextStyle(fontSize: 13)),
            const SizedBox(width: 8),
            SizedBox(width: 70, child: TextBox(
              controller: TextEditingController(text: task.afterMinutes.toString()),
              textAlign: TextAlign.center,
              onChanged: (v) {
                final p = int.tryParse(v);
                if (p != null && p > 0) update(task.copyWith(afterMinutes: p), rearm: true);
              },
            )),
            const Text(' 分钟后触发', style: TextStyle(fontSize: 13)),
          ]),

        if (task.enabled) ...[
          const SizedBox(height: 10),
          Row(children: [
            const SizedBox(width: 60),
            Icon(FluentIcons.info, size: 12, color: subColor),
            const SizedBox(width: 6),
            Text('下次触发：${_formatFireAt(task.fireAtEpochMs)}', style: TextStyle(fontSize: 12, color: subColor)),
          ]),
        ],
      ]),
    );
  }

  String _weekdayLabel(int weekday) =>
      const ['一', '二', '三', '四', '五', '六', '日'][weekday - 1];

  Widget _hint(String text, {required bool isDark}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: isDark ? const Color(0xFF303050) : const Color(0xFFF0F0F8),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text(text, style: TextStyle(fontSize: 12, color: isDark ? const Color(0xFF9090B0) : const Color(0xFF8A8A9A))),
  );

  String _formatFireAt(int epochMs) => ScheduleController.formatFireAt(epochMs);

  Widget _chip(BuildContext context, String label, bool selected, VoidCallback onTap) {
    final isDark = FluentTheme.of(context).brightness == Brightness.dark;
    final accent = FluentTheme.of(context).accentColor;
    final unselectedBg = isDark ? const Color(0xFF303050) : const Color(0xFFE8E8F0);
    final unselectedBorder = isDark ? const Color(0xFF404060) : const Color(0xFFD0D0D8);
    final unselectedText = isDark ? const Color(0xFFC0C0D8) : const Color(0xFF5A5A70);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
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
    );
  }

  Widget _timeBox(int value, ValueChanged<int> onChanged) {
    return SizedBox(
      width: 46,
      child: TextBox(
        controller: TextEditingController(text: value.toString()),
        textAlign: TextAlign.center,
        onChanged: (v) {
          final p = int.tryParse(v);
          if (p != null && p >= 0) onChanged(p);
        },
      ),
    );
  }
}