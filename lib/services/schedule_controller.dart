
import 'dart:async';

import '../models/clicker_config.dart';

abstract class ScheduleActions {
  const ScheduleActions();

  void startClick();

  void stopClick();

  void playMacro(String? macroId);

  void stopMacro();
}

class ScheduleController {
  ScheduleController({
    required this.readSchedules,
    required this.writeSchedules,
    required this.actions,
    this.tickPeriod = const Duration(seconds: 5),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final List<ClickerSchedule> Function() readSchedules;

  final void Function(List<ClickerSchedule>) writeSchedules;

  final ScheduleActions actions;

  final Duration tickPeriod;

  final DateTime Function() _clock;

  Timer? _timer;
  bool _disposed = false;

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


  void add() {
    final s = ClickerSchedule(
      id: ClickerSchedule.newId(),
      action: ScheduleAction.startClick,
      hour: 8,
      minute: 0,
    );
    writeSchedules([...readSchedules(), s]);
  }

  void removeAt(int index) {
    final list = readSchedules();
    if (index < 0 || index >= list.length) return;
    final next = [...list]..removeAt(index);
    writeSchedules(next);
  }

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

  static int armTime(ClickerSchedule s, {DateTime? now}) {
    final base = now ?? DateTime.now();
    if (s.timing == ScheduleTiming.countdown) {
      return base.millisecondsSinceEpoch + s.afterMinutes * 60000;
    }
    if (s.repeat == ScheduleRepeat.interval) {
      final minutes = s.intervalMinutes.clamp(1, 1440);
      return base.millisecondsSinceEpoch + minutes * 60000;
    }
    var target = DateTime(base.year, base.month, base.day, s.hour, s.minute);
    if (!target.isAfter(base)) {
      target = DateTime(base.year, base.month, base.day + 1, s.hour, s.minute);
    }
    if (s.repeat == ScheduleRepeat.weekly) {
      final wanted = s.weekday.clamp(1, 7);
      while (target.weekday != wanted) {
        target =
            DateTime(target.year, target.month, target.day + 1, s.hour, s.minute);
      }
    } else if (s.repeat == ScheduleRepeat.weekdays) {
      while (target.weekday > DateTime.friday) {
        target =
            DateTime(target.year, target.month, target.day + 1, s.hour, s.minute);
      }
    }
    return target.millisecondsSinceEpoch;
  }


  void checkAll() {
    if (_disposed) return;
    final list = readSchedules();
    for (var i = 0; i < list.length; i++) {
      checkAt(i, list[i]);
    }
  }

  void checkAt(int index, ClickerSchedule s) {
    if (!s.enabled || s.fireAtEpochMs == 0) return;
    if (_clock().millisecondsSinceEpoch < s.fireAtEpochMs) return;

    fire(s);

    if (s.timing == ScheduleTiming.countdown || s.repeat == ScheduleRepeat.once) {
      updateAt(index, s.copyWith(enabled: false, fireAtEpochMs: 0));
    } else {
      updateAt(index, s.copyWith(fireAtEpochMs: armTime(s, now: _clock())));
    }
  }

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


  static String formatFireAt(int epochMs, {DateTime? now}) {
    if (epochMs <= 0) return '未布防';
    final t = DateTime.fromMillisecondsSinceEpoch(epochMs);
    final base = now ?? DateTime.now();
    final minutes = t.difference(base).inMinutes;
    if (minutes >= 0 && minutes < 60) return '$minutes 分钟后';
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
