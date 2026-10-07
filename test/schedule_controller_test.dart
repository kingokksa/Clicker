/// ScheduleController 测试 — 守护 PC 端与移动端共用的定时调度逻辑。
///
/// 控制器通过构造注入读写回调与 [DateTime] 时钟，因此这里用假时钟做确定性断言，
/// 不依赖真实 Timer 轮询（只有最后一组的 start/dispose 用到真实计时器）。
library;

import 'package:clicker/models/clicker_config.dart';
import 'package:clicker/services/schedule_controller.dart';
import 'package:flutter_test/flutter_test.dart';

/// 记录调度器触发的动作，替代真实的 ClickService / MacroService。
class _Recorder extends ScheduleActions {
  final List<String> log = [];

  @override
  void startClick() => log.add('startClick');

  @override
  void stopClick() => log.add('stopClick');

  @override
  void playMacro(String? macroId) => log.add('playMacro:$macroId');

  @override
  void stopMacro() => log.add('stopMacro');
}

/// 测试脚手架：持有任务列表 + 可控时钟。
class _Harness {
  final List<ClickerSchedule> schedules = [];
  final _Recorder actions = _Recorder();
  late final ScheduleController ctrl;

  /// 固定基准时间：2026-01-01 10:00
  DateTime now = DateTime(2026, 1, 1, 10, 0);

  _Harness() {
    ctrl = ScheduleController(
      readSchedules: () => schedules,
      writeSchedules: (l) {
        schedules
          ..clear()
          ..addAll(l);
      },
      actions: actions,
      clock: () => now,
    );
  }

  /// 放一个已启用且已到点的任务（默认 09:00，早于基准 10:00）。
  ClickerSchedule due({
    ScheduleAction action = ScheduleAction.startClick,
    ScheduleRepeat repeat = ScheduleRepeat.once,
    ScheduleTiming timing = ScheduleTiming.clock,
    String? macroId,
  }) {
    final s = ClickerSchedule(
      id: 's1',
      enabled: true,
      action: action,
      timing: timing,
      repeat: repeat,
      hour: 9,
      minute: 0,
      macroId: macroId,
      fireAtEpochMs: DateTime(2026, 1, 1, 9, 0).millisecondsSinceEpoch,
    );
    schedules.add(s);
    return s;
  }
}

void main() {
  // ─── armTime ──────────────────────────────────────────

  group('armTime', () {
    final base = DateTime(2026, 1, 1, 10, 0);

    test('clock 模式且时刻未过 — 取今天该时刻', () {
      const s = ClickerSchedule(hour: 12, minute: 30);
      final t = DateTime.fromMillisecondsSinceEpoch(
          ScheduleController.armTime(s, now: base));
      expect(t, DateTime(2026, 1, 1, 12, 30));
    });

    test('clock 模式且时刻已过 — 顺延到明天（不会立即触发）', () {
      const s = ClickerSchedule(hour: 8, minute: 0);
      final t = DateTime.fromMillisecondsSinceEpoch(
          ScheduleController.armTime(s, now: base));
      expect(t, DateTime(2026, 1, 2, 8, 0));
    });

    test('clock 模式且时刻恰好等于现在 — 也算已过，顺延到明天', () {
      const s = ClickerSchedule(hour: 10, minute: 0);
      final t = DateTime.fromMillisecondsSinceEpoch(
          ScheduleController.armTime(s, now: base));
      expect(t, DateTime(2026, 1, 2, 10, 0));
    });

    test('clock 模式跨月顺延正确（1 月 31 日 → 2 月 1 日）', () {
      const s = ClickerSchedule(hour: 9, minute: 0);
      final t = DateTime.fromMillisecondsSinceEpoch(
          ScheduleController.armTime(s, now: DateTime(2026, 1, 31, 10, 0)));
      expect(t, DateTime(2026, 2, 1, 9, 0));
    });

    test('countdown 模式 — 取基准时刻 + N 分钟', () {
      const s = ClickerSchedule(
        timing: ScheduleTiming.countdown,
        afterMinutes: 10,
      );
      final epoch = ScheduleController.armTime(s, now: base);
      expect(epoch - base.millisecondsSinceEpoch, 10 * 60000);
    });

    test('countdown 模式忽略 hour/minute', () {
      const s = ClickerSchedule(
        timing: ScheduleTiming.countdown,
        afterMinutes: 1,
        hour: 23,
        minute: 59,
      );
      final t = DateTime.fromMillisecondsSinceEpoch(
          ScheduleController.armTime(s, now: base));
      expect(t, DateTime(2026, 1, 1, 10, 1));
    });

    test('now 省略时使用真实当前时间且结果为正数', () {
      final epoch = ScheduleController.armTime(
        const ClickerSchedule(timing: ScheduleTiming.countdown, afterMinutes: 5),
      );
      expect(epoch, greaterThan(0));
      expect(epoch, greaterThan(DateTime.now().millisecondsSinceEpoch));
    });
  });

  // ─── add / removeAt ───────────────────────────────────

  group('add / removeAt', () {
    test('add 追加一个默认任务（启动连点 / 08:00 / 未启用）', () {
      final h = _Harness();
      h.ctrl.add();
      expect(h.schedules.length, 1);
      final s = h.schedules.first;
      expect(s.action, ScheduleAction.startClick);
      expect(s.hour, 8);
      expect(s.minute, 0);
      expect(s.enabled, isFalse);
      expect(s.fireAtEpochMs, 0);
    });

    test('add 生成的 id 非空', () {
      final h = _Harness();
      h.ctrl.add();
      expect(h.schedules.first.id, isNotEmpty);
    });

    test('add 两次 id 不重复', () {
      final h = _Harness();
      h.ctrl.add();
      h.ctrl.add();
      expect(h.schedules[0].id, isNot(h.schedules[1].id));
    });

    test('removeAt 删除指定下标', () {
      final h = _Harness();
      h.ctrl.add();
      h.ctrl.add();
      h.ctrl.removeAt(0);
      expect(h.schedules.length, 1);
    });

    test('removeAt 越界（负数 / 等于长度 / 超出）静默不报错', () {
      final h = _Harness();
      h.ctrl.add();
      h.ctrl.removeAt(-1);
      h.ctrl.removeAt(1);
      h.ctrl.removeAt(99);
      expect(h.schedules.length, 1);
    });

    test('removeAt 不修改原列表之外的元素', () {
      final h = _Harness();
      h.ctrl.add();
      h.ctrl.add();
      h.ctrl.add();
      final before = h.schedules[0].id;
      h.ctrl.removeAt(1);
      expect(h.schedules[0].id, before);
      expect(h.schedules.length, 2);
    });
  });

  // ─── updateAt ─────────────────────────────────────────

  group('updateAt', () {
    test('rearm=false 时不改 fireAtEpochMs', () {
      final h = _Harness();
      h.schedules.add(const ClickerSchedule(id: 'a', hour: 12));
      h.ctrl.updateAt(0, h.schedules[0].copyWith(hour: 15));
      expect(h.schedules[0].hour, 15);
      expect(h.schedules[0].fireAtEpochMs, 0);
    });

    test('rearm=true 且启用 — 布防到下一个该时刻', () {
      final h = _Harness();
      h.schedules.add(const ClickerSchedule(id: 'a', enabled: true, hour: 12));
      h.ctrl.updateAt(0, h.schedules[0], rearm: true);
      final t = DateTime.fromMillisecondsSinceEpoch(h.schedules[0].fireAtEpochMs);
      expect(t, DateTime(2026, 1, 1, 12, 0));
    });

    test('rearm=true 但未启用 — 不布防', () {
      final h = _Harness();
      h.schedules.add(const ClickerSchedule(id: 'a', enabled: false, hour: 12));
      h.ctrl.updateAt(0, h.schedules[0], rearm: true);
      expect(h.schedules[0].fireAtEpochMs, 0);
    });

    test('rearm=true 布防时用注入的时钟而非真实时间', () {
      final h = _Harness();
      h.now = DateTime(2030, 6, 15, 22, 0);
      h.schedules.add(const ClickerSchedule(id: 'a', enabled: true, hour: 7));
      h.ctrl.updateAt(0, h.schedules[0], rearm: true);
      final t = DateTime.fromMillisecondsSinceEpoch(h.schedules[0].fireAtEpochMs);
      expect(t, DateTime(2030, 6, 16, 7, 0));
    });

    test('越界更新静默返回', () {
      final h = _Harness();
      h.schedules.add(const ClickerSchedule(id: 'a'));
      h.ctrl.updateAt(5, const ClickerSchedule(id: 'b', hour: 3));
      expect(h.schedules.length, 1);
      expect(h.schedules[0].id, 'a');
    });
  });

  // ─── checkAt ──────────────────────────────────────────

  group('checkAt', () {
    test('未启用的任务不触发', () {
      final h = _Harness();
      h.schedules.add(ClickerSchedule(
        id: 'a',
        enabled: false,
        fireAtEpochMs: DateTime(2026, 1, 1, 9, 0).millisecondsSinceEpoch,
      ));
      h.ctrl.checkAt(0, h.schedules[0]);
      expect(h.actions.log, isEmpty);
    });

    test('未布防（fireAtEpochMs == 0）的任务不触发', () {
      final h = _Harness();
      h.schedules.add(const ClickerSchedule(id: 'a', enabled: true));
      h.ctrl.checkAt(0, h.schedules[0]);
      expect(h.actions.log, isEmpty);
    });

    test('未到点不触发', () {
      final h = _Harness();
      h.schedules.add(ClickerSchedule(
        id: 'a',
        enabled: true,
        fireAtEpochMs: DateTime(2026, 1, 1, 11, 0).millisecondsSinceEpoch,
      ));
      h.ctrl.checkAt(0, h.schedules[0]);
      expect(h.actions.log, isEmpty);
    });

    test('到点触发 — once 触发后停用并清空布防', () {
      final h = _Harness();
      h.due();
      h.ctrl.checkAt(0, h.schedules[0]);
      expect(h.actions.log, ['startClick']);
      expect(h.schedules[0].enabled, isFalse);
      expect(h.schedules[0].fireAtEpochMs, 0);
    });

    test('到点触发 — daily 触发后重新布防并仍启用', () {
      final h = _Harness();
      h.due(repeat: ScheduleRepeat.daily);
      h.ctrl.checkAt(0, h.schedules[0]);
      expect(h.actions.log, ['startClick']);
      expect(h.schedules[0].enabled, isTrue);
      // 09:00 已过（现在 10:00）→ 布防到明天 09:00
      final t = DateTime.fromMillisecondsSinceEpoch(h.schedules[0].fireAtEpochMs);
      expect(t, DateTime(2026, 1, 2, 9, 0));
    });

    test('countdown 触发后停用（无论 repeat）', () {
      final h = _Harness();
      h.schedules.add(ClickerSchedule(
        id: 'a',
        enabled: true,
        timing: ScheduleTiming.countdown,
        repeat: ScheduleRepeat.daily,
        afterMinutes: 5,
        fireAtEpochMs: DateTime(2026, 1, 1, 9, 0).millisecondsSinceEpoch,
      ));
      h.ctrl.checkAt(0, h.schedules[0]);
      expect(h.schedules[0].enabled, isFalse);
    });

    test('重复 checkAt 同一已停用任务不会二次触发', () {
      final h = _Harness();
      h.due();
      h.ctrl.checkAt(0, h.schedules[0]);
      h.ctrl.checkAt(0, h.schedules[0]);
      expect(h.actions.log.length, 1);
    });
  });

  // ─── checkAll ─────────────────────────────────────────

  group('checkAll', () {
    test('遍历全部任务并对到点的触发', () {
      final h = _Harness();
      h.due(action: ScheduleAction.startClick);
      h.schedules.add(ClickerSchedule(
        id: 's2',
        enabled: true,
        action: ScheduleAction.stopClick,
        fireAtEpochMs: DateTime(2026, 1, 1, 12, 0).millisecondsSinceEpoch,
      ));
      h.due(action: ScheduleAction.stopMacro);
      h.ctrl.checkAll();
      expect(h.actions.log, ['startClick', 'stopMacro']);
    });

    test('空列表不报错', () {
      final h = _Harness();
      h.ctrl.checkAll();
      expect(h.actions.log, isEmpty);
    });

    test('dispose 后 checkAll 不再触发', () {
      final h = _Harness();
      h.due();
      h.ctrl.dispose();
      h.ctrl.checkAll();
      expect(h.actions.log, isEmpty);
    });
  });

  // ─── fire ─────────────────────────────────────────────

  group('fire', () {
    test('startClick', () {
      final h = _Harness();
      h.ctrl.fire(const ClickerSchedule(action: ScheduleAction.startClick));
      expect(h.actions.log, ['startClick']);
    });

    test('stopClick', () {
      final h = _Harness();
      h.ctrl.fire(const ClickerSchedule(action: ScheduleAction.stopClick));
      expect(h.actions.log, ['stopClick']);
    });

    test('playMacro 带上 macroId', () {
      final h = _Harness();
      h.ctrl.fire(const ClickerSchedule(
        action: ScheduleAction.playMacro,
        macroId: 'macro_42',
      ));
      expect(h.actions.log, ['playMacro:macro_42']);
    });

    test('playMacro 且 macroId 为空 — 传给出口 null', () {
      final h = _Harness();
      h.ctrl.fire(const ClickerSchedule(action: ScheduleAction.playMacro));
      expect(h.actions.log, ['playMacro:null']);
    });

    test('stopMacro', () {
      final h = _Harness();
      h.ctrl.fire(const ClickerSchedule(action: ScheduleAction.stopMacro));
      expect(h.actions.log, ['stopMacro']);
    });
  });

  // ─── formatFireAt ─────────────────────────────────────

  group('formatFireAt', () {
    final now = DateTime(2026, 1, 1, 10, 0);
    int at(int month, int day, int h, int m) =>
        DateTime(2026, month, day, h, m).millisecondsSinceEpoch;

    test('未布防（0）', () {
      expect(ScheduleController.formatFireAt(0, now: now), '未布防');
    });

    test('未布防（负数）', () {
      expect(ScheduleController.formatFireAt(-1, now: now), '未布防');
    });

    test('今天的时刻 — 今天 hh:mm', () {
      expect(ScheduleController.formatFireAt(at(1, 1, 15, 30), now: now), '今天 15:30');
    });

    test('一小时内 — N 分钟后', () {
      expect(ScheduleController.formatFireAt(at(1, 1, 10, 42), now: now), '42 分钟后');
    });

    test('明天的时刻 — 明天 hh:mm', () {
      expect(ScheduleController.formatFireAt(at(1, 2, 8, 5), now: now), '明天 08:05');
    });

    test('更远的日期 — M-D hh:mm', () {
      expect(ScheduleController.formatFireAt(at(3, 5, 8, 5), now: now), '3-5 08:05');
    });

    test('小时/分钟补零', () {
      expect(ScheduleController.formatFireAt(at(1, 1, 9, 7), now: now), '今天 09:07');
    });

    test('now 省略时也不抛异常', () {
      final s = ScheduleController.formatFireAt(
        DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch,
      );
      expect(s, isNotEmpty);
    });
  });

  group('armTime — 每周 / 工作日 / 间隔', () {
    final base = DateTime(2026, 1, 1, 10, 0);

    test('每周 — 取本周内的目标星期', () {
      final s = ClickerSchedule(
          hour: 12,
          minute: 0,
          repeat: ScheduleRepeat.weekly,
          weekday: DateTime.saturday);
      final t = DateTime.fromMillisecondsSinceEpoch(
          ScheduleController.armTime(s, now: base));
      expect(t, DateTime(2026, 1, 3, 12, 0));
      expect(t.weekday, DateTime.saturday);
    });

    test('每周 — 目标星期已过则顺延到下周', () {
      final s = ClickerSchedule(
          hour: 9,
          minute: 0,
          repeat: ScheduleRepeat.weekly,
          weekday: DateTime.thursday);
      final t = DateTime.fromMillisecondsSinceEpoch(
          ScheduleController.armTime(s, now: base));
      expect(t, DateTime(2026, 1, 8, 9, 0));
    });

    test('每周 — 目标星期是今天且时刻未过，取今天', () {
      final s = ClickerSchedule(
          hour: 20,
          minute: 0,
          repeat: ScheduleRepeat.weekly,
          weekday: DateTime.thursday);
      final t = DateTime.fromMillisecondsSinceEpoch(
          ScheduleController.armTime(s, now: base));
      expect(t, DateTime(2026, 1, 1, 20, 0));
    });

    test('工作日 — 周五之后跳到周一', () {
      final s = ClickerSchedule(
          hour: 9, minute: 0, repeat: ScheduleRepeat.weekdays);
      final t = DateTime.fromMillisecondsSinceEpoch(
          ScheduleController.armTime(s, now: DateTime(2026, 1, 2, 10, 0)));
      expect(t, DateTime(2026, 1, 5, 9, 0));
      expect(t.weekday, DateTime.monday);
    });

    test('工作日 — 周末布防落到周一', () {
      final s = ClickerSchedule(
          hour: 9, minute: 0, repeat: ScheduleRepeat.weekdays);
      final t = DateTime.fromMillisecondsSinceEpoch(
          ScheduleController.armTime(s, now: DateTime(2026, 1, 4, 10, 0)));
      expect(t, DateTime(2026, 1, 5, 9, 0));
    });

    test('工作日 — 周内时刻未过取当天', () {
      final s = ClickerSchedule(
          hour: 18, minute: 30, repeat: ScheduleRepeat.weekdays);
      final t = DateTime.fromMillisecondsSinceEpoch(
          ScheduleController.armTime(s, now: DateTime(2026, 1, 6, 10, 0)));
      expect(t, DateTime(2026, 1, 6, 18, 30));
    });

    test('间隔 — 取基准时刻 + N 分钟', () {
      final s = ClickerSchedule(
          repeat: ScheduleRepeat.interval, intervalMinutes: 15);
      expect(ScheduleController.armTime(s, now: base),
          base.add(const Duration(minutes: 15)).millisecondsSinceEpoch);
    });

    test('间隔 — N 为 0 时按 1 分钟兜底', () {
      final s = ClickerSchedule(
          repeat: ScheduleRepeat.interval, intervalMinutes: 0);
      expect(ScheduleController.armTime(s, now: base),
          base.add(const Duration(minutes: 1)).millisecondsSinceEpoch);
    });

    test('间隔 — 忽略 hour/minute', () {
      final s = ClickerSchedule(
          hour: 23,
          minute: 59,
          repeat: ScheduleRepeat.interval,
          intervalMinutes: 5);
      expect(ScheduleController.armTime(s, now: base),
          base.add(const Duration(minutes: 5)).millisecondsSinceEpoch);
    });
  });

  group('checkAt — 每周 / 间隔', () {
    test('每周触发后重新布防到下周同一天并保持启用', () {
      final h = _Harness();
      final s = ClickerSchedule(
        id: 'w1',
        enabled: true,
        repeat: ScheduleRepeat.weekly,
        weekday: DateTime.thursday,
        hour: 9,
        minute: 0,
        fireAtEpochMs: DateTime(2026, 1, 1, 9, 0).millisecondsSinceEpoch,
      );
      h.schedules.add(s);
      h.ctrl.checkAt(0, s);
      expect(h.actions.log, ['startClick']);
      expect(h.schedules[0].enabled, isTrue);
      expect(
          DateTime.fromMillisecondsSinceEpoch(h.schedules[0].fireAtEpochMs),
          DateTime(2026, 1, 8, 9, 0));
    });

    test('间隔触发后按间隔重新布防', () {
      final h = _Harness();
      final s = ClickerSchedule(
        id: 'i1',
        enabled: true,
        repeat: ScheduleRepeat.interval,
        intervalMinutes: 20,
        fireAtEpochMs: DateTime(2026, 1, 1, 10, 0).millisecondsSinceEpoch,
      );
      h.schedules.add(s);
      h.ctrl.checkAt(0, s);
      expect(h.actions.log, ['startClick']);
      expect(
          DateTime.fromMillisecondsSinceEpoch(h.schedules[0].fireAtEpochMs),
          DateTime(2026, 1, 1, 10, 20));
    });

    test('倒计时即使选了间隔也只触发一次', () {
      final h = _Harness();
      final s = ClickerSchedule(
        id: 'c1',
        enabled: true,
        timing: ScheduleTiming.countdown,
        repeat: ScheduleRepeat.interval,
        intervalMinutes: 20,
        fireAtEpochMs: DateTime(2026, 1, 1, 10, 0).millisecondsSinceEpoch,
      );
      h.schedules.add(s);
      h.ctrl.checkAt(0, s);
      expect(h.actions.log, ['startClick']);
      expect(h.schedules[0].enabled, isFalse);
      expect(h.schedules[0].fireAtEpochMs, 0);
    });
  });

  // ─── start / dispose（真实 Timer） ────────────────────

  group('start / dispose', () {
    test('start 后轮询会触发到点任务', () async {
      final h = _Harness();
      h.due();
      // 5ms 轮询，等足够多拍
      final polling = ScheduleController(
        readSchedules: () => h.schedules,
        writeSchedules: (l) {
          h.schedules
            ..clear()
            ..addAll(l);
        },
        actions: h.actions,
        tickPeriod: const Duration(milliseconds: 5),
        clock: () => h.now,
      );
      polling.start();
      await Future<void>.delayed(const Duration(milliseconds: 200));
      polling.dispose();
      expect(h.actions.log, contains('startClick'));
    });

    test('dispose 后轮询停止（后续时间推进不再触发）', () async {
      final h = _Harness();
      final polling = ScheduleController(
        readSchedules: () => h.schedules,
        writeSchedules: (l) {
          h.schedules
            ..clear()
            ..addAll(l);
        },
        actions: h.actions,
        tickPeriod: const Duration(milliseconds: 5),
        clock: () => h.now,
      );
      polling.start();
      polling.dispose();
      // dispose 之后才放进任务，若仍在轮询就会被触发
      h.due();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(h.actions.log, isEmpty);
    });

    test('start 可重复调用而不产生重复轮询副作用', () async {
      final h = _Harness();
      h.due();
      final polling = ScheduleController(
        readSchedules: () => h.schedules,
        writeSchedules: (l) {
          h.schedules
            ..clear()
            ..addAll(l);
        },
        actions: h.actions,
        tickPeriod: const Duration(milliseconds: 5),
        clock: () => h.now,
      );
      polling.start();
      polling.start();
      await Future<void>.delayed(const Duration(milliseconds: 200));
      polling.dispose();
      // 任务是 once，触发后即停用，因此无论如何只会记一次
      expect(h.actions.log.where((e) => e == 'startClick').length, 1);
    });

    test('dispose 后 start 无效（已释放不再起轮询）', () async {
      final h = _Harness();
      final polling = ScheduleController(
        readSchedules: () => h.schedules,
        writeSchedules: (l) {
          h.schedules
            ..clear()
            ..addAll(l);
        },
        actions: h.actions,
        tickPeriod: const Duration(milliseconds: 5),
        clock: () => h.now,
      );
      polling.dispose();
      polling.start();
      h.due();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(h.actions.log, isEmpty);
    });
  });
}
