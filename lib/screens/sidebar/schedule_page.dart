/// 定时任务页面 — 定时自动开始 / 停止连点。
/// 配置字段落在 [ClickerConfig.startSchedule] / [ClickerConfig.stopSchedule]，
/// 实际调度由 AppState 的周期定时器执行。
library;

import 'package:fluent_ui/fluent_ui.dart';
import 'package:provider/provider.dart';
import '../../models/clicker_config.dart';
import '../../services/app_state.dart';

class SchedulePage extends StatelessWidget {
  const SchedulePage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    return ScaffoldPage.scrollable(
      padding: const EdgeInsets.all(20),
      children: [
        Row(children: [
          Icon(FluentIcons.clock, size: 20, color: state.accentColor),
          const SizedBox(width: 10),
          const Text('定时任务', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 16),
        _card(context, title: '定时开始', icon: FluentIcons.play, child: _ScheduleTile(state: state, isStart: true)),
        const SizedBox(height: 12),
        _card(context, title: '定时停止', icon: FluentIcons.stop, child: _ScheduleTile(state: state, isStart: false)),
      ],
    );
  }

  Widget _card(BuildContext context, {required String title, required IconData icon, required Widget child}) {
    return Card(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 16),
          const SizedBox(width: 8),
          Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        ]),
        const SizedBox(height: 12),
        child,
      ]),
    );
  }
}

class _ScheduleTile extends StatelessWidget {
  final AppState state;
  final bool isStart;
  const _ScheduleTile({required this.state, required this.isStart});

  @override
  Widget build(BuildContext context) {
    final config = state.clickerConfig;
    final s = isStart ? config.startSchedule : config.stopSchedule;
    final accent = FluentTheme.of(context).accentColor;

    void update(ClickerSchedule ns) {
      final updated = isStart
          ? config.copyWith(startSchedule: ns)
          : config.copyWith(stopSchedule: ns);
      state.setClickerConfig(updated);
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(isStart ? FluentIcons.play : FluentIcons.stop, size: 14, color: accent.withValues(alpha: 0.7)),
        const SizedBox(width: 8),
        const Expanded(child: Text('启用此定时', style: TextStyle(fontSize: 13))),
        ToggleSwitch(
          checked: s.enabled,
          onChanged: (v) => update(s.copyWith(enabled: v, fireAtEpochMs: 0)),
        ),
      ]),
      if (s.enabled) ...[
        const SizedBox(height: 10),
        Row(children: [
          _chip(context, '时间点', s.timing == ScheduleTiming.clock,
              () => update(s.copyWith(timing: ScheduleTiming.clock, fireAtEpochMs: 0))),
          const SizedBox(width: 6),
          _chip(context, '倒计时', s.timing == ScheduleTiming.countdown,
              () => update(s.copyWith(timing: ScheduleTiming.countdown, fireAtEpochMs: 0))),
          const Spacer(),
          if (s.timing == ScheduleTiming.clock) ...[
            _chip(context, '仅一次', s.repeat == ScheduleRepeat.once,
                () => update(s.copyWith(repeat: ScheduleRepeat.once))),
            const SizedBox(width: 6),
            _chip(context, '每天', s.repeat == ScheduleRepeat.daily,
                () => update(s.copyWith(repeat: ScheduleRepeat.daily))),
          ],
        ]),
        const SizedBox(height: 10),
        if (s.timing == ScheduleTiming.clock)
          Row(children: [
            const Text('时间:', style: TextStyle(fontSize: 12)),
            const SizedBox(width: 8),
            _timeBox(s.hour, (v) => update(s.copyWith(hour: v % 24))),
            const Text(' 时 ', style: TextStyle(fontSize: 12)),
            _timeBox(s.minute, (v) => update(s.copyWith(minute: v % 60))),
            const Text(' 分', style: TextStyle(fontSize: 12)),
          ])
        else
          Row(children: [
            const Text('启用后', style: TextStyle(fontSize: 12)),
            const SizedBox(width: 8),
            SizedBox(width: 70, child: TextBox(
              controller: TextEditingController(text: s.afterMinutes.toString()),
              textAlign: TextAlign.center,
              onChanged: (v) {
                final p = int.tryParse(v);
                if (p != null && p > 0) update(s.copyWith(afterMinutes: p, fireAtEpochMs: 0));
              },
            )),
            const Text(' 分钟后触发', style: TextStyle(fontSize: 12)),
          ]),
      ],
    ]);
  }

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