
import 'dart:async';

import '../app_logger.dart';

class PluginEvent {
  final String name;
  final Map<String, dynamic> data;
  final DateTime timestamp;

  PluginEvent(this.name, [Map<String, dynamic>? data])
      : data = data ?? {},
        timestamp = DateTime.now();
}

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

class PluginEventBus {
  final Map<String, List<_Subscription>> _subscriptions = {};

  void Function() on(String event, PluginEventHandler handler, {String? subscriber}) {
    final sub = _Subscription(event, handler, subscriber);
    _subscriptions.putIfAbsent(event, () => []).add(sub);
    return () {
      _subscriptions[event]?.remove(sub);
    };
  }

  Future<void> emit(String event, [Map<String, dynamic>? data]) async {
    final subs = List<_Subscription>.from(_subscriptions[event] ?? []);
    if (subs.isEmpty) return;
    final e = PluginEvent(event, data);
    for (final sub in subs) {
      try {
        await sub.handler(e);
      } catch (err) {
        _log('event handler error [$event]: $err');
      }
    }
  }

  void unsubscribeAll(String subscriber) {
    for (final list in _subscriptions.values) {
      list.removeWhere((s) => s.subscriber == subscriber);
    }
  }

  int subscriptionCount(String event) => _subscriptions[event]?.length ?? 0;

  void _log(String msg) {
    AppLogger.instance.log('PluginEventBus', msg);
  }
}

class _Subscription {
  final String event;
  final PluginEventHandler handler;
  final String? subscriber;
  const _Subscription(this.event, this.handler, this.subscriber);
}
