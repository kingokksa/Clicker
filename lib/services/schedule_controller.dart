/// 定时任务调度器 — PC 端与移动端共用的纯 Dart 逻辑。
///
/// 桌面 `AppState` 与移动 `MobileAppState` 各自持有本控制器实例，通过
/// 构造注入读写与动作回调，避免调度逻辑在两个 state 里各写一份。
/// UI 层仍各写一套（fluent_ui / Material），只共享逻辑。
///
/// 布防语义：[updateAt] 传 `rearm: true` 时重算 fireAtEpochMs —— 时间点模式取
/// 下一个 hh:mm（今天已过则顺延到明天），倒计时取当前时刻 + N 分钟。
/// 因此「一开开关」绝不会立即触发。
library;

import 'dart:async';

import '../models/clicker_config.dart';

/// 调度器到宿主的动作出口。由各端 state 实现。
abstract class ScheduleActions {
  const ScheduleActions();

  /// 启动连点（已在跑则忽略）。
  void startClick();

  /// 停止连点。
  void stopClick();

  /// 播放指定 id 的宏；id 为空或找不到时忽略。
  void playMacro(String? macroId);

  /// 停止宏播放。
  void stopMacro();
}

/// 定时任务调度器。
class ScheduleController {
  ScheduleController({
    required this.readSchedules,
    required this.writeSchedules,
    required this.actions,
    this.tickPeriod = const Duration(seconds: 5),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  /// 读取当前任务列表（通常是 `config.schedules`）。
  final List<ClickerSchedule> Function() readSchedules;

  /// 写回任务列表（通常是 `copyWith(schedules: list)` + 落盘）。
  final void Function(List<ClickerSchedule>) writeSchedules;

  /// 到点动作出口。
  final ScheduleActions actions;

  /// 轮询间隔。
  final Duration tickPeriod;

  final DateTime Function() _clock;

  Timer? _timer;
  bool _disposed = false;

  /// 启动轮询。重复调用会先取消旧 timer。
  void start() {
    if (_disposed) return;
    _timer?.cancel();
    _timer = Timer.periodic(tickPeriod, (_) => checkAll());
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
  }

  // ─── 列表增删改 ──────────────────────────────────────────

  /// 新增一个定时任务（默认：启动连点，每天 08:00）。
  void add() {
    final s = ClickerSchedule(
      id: ClickerSchedule.newId(),
      action: ScheduleAction.startClick,
      hour: 8,
      minute: 0,
    );
    writeSchedules([...readSchedules(), s]);
  }

  /// 删除指定下标的任务。越界静默返回。
  void removeAt(int index) {
    final list = readSchedules();
    if (index < 0 || index >= list.length) return;
    final next = [...list]..removeAt(index);
    writeSchedules(next);
  }

  /// 更新指定下标的任务。[rearm] 为 true 且启用时重新布防。
  void updateAt(int index, ClickerSchedule updated, {bool rearm = false}) {
    final list = readSchedules();
    if (index < 0 || index >= list.length) return;
    var ns = updated;
    if (rearm && ns.enabled) {
      ns = ns.copyWith(fireAtEpochMs: armTime(ns, now: _clock()));
    }
    final next = [...list];
    next[index] = ns;
    writeSchedules(next);
  }

  /// 计算布防时刻（epoch ms）。独立静态方法，便于单测。
  static int armTime(ClickerSchedule s, {DateTime? now}) {
    final base = now ?? DateTime.now();
    if (s.timing == ScheduleTiming.countdown) {
      return base.millisecondsSinceEpoch + s.afterMinutes * 60000;
    }
    var target = DateTime(base.year, base.month, base.day, s.hour, s.minute);
    if (!target.isAfter(base)) {
      // 今天的时刻已过 — 顺延到明天，避免「一开开关就立即触发」
      target = DateTime(base.year, base.month, base.day + 1, s.hour, s.minute);
    }
    return target.millisecondsSinceEpoch;
  }

  // ─── 轮询 ────────────────────────────────────────────────

  /// 检查全部任务并对到点的执行动作。
  void checkAll() {
    if (_disposed) return;
    final list = readSchedules();
    for (var i = 0; i < list.length; i++) {
      checkAt(i, list[i]);
    }
  }

  /// 检查单个任务：到点则触发，然后按重复策略停用或重新布防。
  void checkAt(int index, ClickerSchedule s) {
    if (!s.enabled || s.fireAtEpochMs == 0) return;
    if (_clock().millisecondsSinceEpoch < s.fireAtEpochMs) return;

    fire(s);

    if (s.timing == ScheduleTiming.countdown || s.repeat == ScheduleRepeat.once) {
      // 一次性：触发后停用
      updateAt(index, s.copyWith(enabled: false, fireAtEpochMs: 0));
    } else {
      // 每天：触发后布防到下一个同刻
      updateAt(index, s.copyWith(fireAtEpochMs: armTime(s, now: _clock())));
    }
  }

  /// 执行任务动作。
  void fire(ClickerSchedule s) {
    switch (s.action) {
      case ScheduleAction.startClick:
        actions.startClick();
      case ScheduleAction.stopClick:
        actions.stopClick();
      case ScheduleAction.playMacro:
        actions.playMacro(s.macroId);
      case ScheduleAction.stopMacro:
        actions.stopMacro();
    }
  }

  // ─── 展示辅助 ────────────────────────────────────────────

  /// 把布防时刻格式化为「今天 08:00」这类短文案，供两个端共用。
  static String formatFireAt(int epochMs, {DateTime? now}) {
    if (epochMs <= 0) return '未布防';
    final t = DateTime.fromMillisecondsSinceEpoch(epochMs);
    final base = now ?? DateTime.now();
    final today = DateTime(base.year, base.month, base.day);
    final day = DateTime(t.year, t.month, t.day);
    final diff = day.difference(today).inDays;
    final hm =
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    if (diff == 0) return '今天 $hm';
    if (diff == 1) return '明天 $hm';
    return '${t.month}-${t.day} $hm';
  }
}
