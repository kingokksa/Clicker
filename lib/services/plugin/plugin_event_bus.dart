/// 插件事件总线 — 宿主与插件之间、插件与插件之间的解耦通信。
///
/// 内置事件由宿主发布；插件可通过 PluginContext.events 订阅/发布。
/// 订阅在插件停用时自动取消，避免泄漏。
library;

import 'dart:async';

/// 事件
class PluginEvent {
  final String name;       // 如 'clicker.started'
  final Map<String, dynamic> data;
  final DateTime timestamp;

  PluginEvent(this.name, [Map<String, dynamic>? data])
      : data = data ?? {},
        timestamp = DateTime.now();
}

/// 内置事件名
abstract final class PluginEvents {
  static const appStarted = 'app.started';
  static const appQuitting = 'app.quitting';
  static const clickerStarted = 'clicker.started';
  static const clickerStopped = 'clicker.stopped';
  static const macroStarted = 'macro.started';
  static const macroStopped = 'macro.stopped';
  static const configChanged = 'config.changed';
  static const pluginActivated = 'plugin.activated';
  static const pluginDeactivated = 'plugin.deactivated';
  static const hotkeyTriggered = 'hotkey.triggered';
}

typedef PluginEventHandler = FutureOr<void> Function(PluginEvent event);

/// 事件总线
class PluginEventBus {
  final Map<String, List<_Subscription>> _subscriptions = {};

  /// 订阅事件。返回取消函数；插件停用时由 PluginContext 统一取消。
  void Function() on(String event, PluginEventHandler handler, {String? subscriber}) {
    final sub = _Subscription(event, handler, subscriber);
    _subscriptions.putIfAbsent(event, () => []).add(sub);
    return () {
      _subscriptions[event]?.remove(sub);
    };
  }

  /// 发布事件（同步调度，异步等待全部处理器完成）
  Future<void> emit(String event, [Map<String, dynamic>? data]) async {
    final subs = List<_Subscription>.from(_subscriptions[event] ?? []);
    if (subs.isEmpty) return;
    final e = PluginEvent(event, data);
    for (final sub in subs) {
      try {
        await sub.handler(e);
      } catch (err) {
        // 单个处理器异常不影响其他处理器
        _log('event handler error [$event]: $err');
      }
    }
  }

  /// 取消某订阅者的全部订阅（插件停用时调用）
  void unsubscribeAll(String subscriber) {
    for (final list in _subscriptions.values) {
      list.removeWhere((s) => s.subscriber == subscriber);
    }
  }

  /// 事件订阅数（诊断用）
  int subscriptionCount(String event) => _subscriptions[event]?.length ?? 0;

  void _log(String msg) {
    // 避免循环依赖，这里不使用 PluginLogger
    assert(() {
      // ignore: avoid_print
      print('[PluginEventBus] $msg');
      return true;
    }());
  }
}

class _Subscription {
  final String event;
  final PluginEventHandler handler;
  final String? subscriber;
  const _Subscription(this.event, this.handler, this.subscriber);
}
