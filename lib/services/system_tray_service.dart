library;

import 'dart:io';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';
import 'platform/platform_input.dart';

class SystemTrayService {
  static final SystemTrayService _instance = SystemTrayService._();
  factory SystemTrayService() => _instance;
  SystemTrayService._();

  static const _channel = MethodChannel('com.clicker.pro/platform');
  bool _initialized = false;

  VoidCallback? onShowFloatingWindow;
  VoidCallback? onShowMainWindow;

  PlatformInput? platformInput;

  final List<Future<dynamic> Function(MethodCall)> _externalHandlers = [];

  VoidCallback registerExternalHandler(
      Future<dynamic> Function(MethodCall) handler) {
    _externalHandlers.add(handler);
    return () {
      _externalHandlers.remove(handler);
    };
  }

  Future<void> init() async {
    // Always set up the method call handler (needed for overlay callbacks on all platforms)
    _channel.setMethodCallHandler(_handleMethodCall);

    if (_initialized) return;
    if (!Platform.isWindows && !Platform.isLinux) {
      _initialized = true;
      return;
    }

    await _channel.invokeMethod('initSystemTray');
    _initialized = true;
  }

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    for (final handler in _externalHandlers) {
      try {
        final result = await handler(call);
        if (result != null) return result;
      } catch (_) {}
    }

    switch (call.method) {
      case 'onTrayIconClick':
        if (Platform.isWindows || Platform.isLinux) {
          try {
            await windowManager.show();
            await windowManager.focus();
          } catch (_) {}
        }
        break;
      case 'onTrayShowMain':
        onShowMainWindow?.call();
        break;
      case 'onTrayFloating':
        onShowFloatingWindow?.call();
        break;
      case 'onTrayExit':
        _cleanupAndExit();
        break;
      case 'onFastClickerStopped':
        final args = call.arguments as Map<dynamic, dynamic>;
        final count = args['count'] as int? ?? 0;
        final generation = args['generation'] as int? ?? 0;
        platformInput?.onFastClickerStopped?.call(count, generation);
        break;
      case 'onKeyCaptured':
        final keyName = call.arguments as String? ?? '';
        platformInput?.onKeyCaptured?.call(keyName);
        break;
    }
  }

  void hideToTray() {
    if (Platform.isWindows || Platform.isLinux) {
      windowManager.hide();
    }
  }

  void showFromTray() {
    if (Platform.isWindows || Platform.isLinux) {
      windowManager.show();
      windowManager.focus();
    }
  }

  void dispose() {
    _channel.invokeMethod('destroySystemTray');
    _initialized = false;
  }

  void _cleanupAndExit() {
    _channel.invokeMethod('stopFastClicker');
    _channel.invokeMethod('destroySystemTray');
    _initialized = false;
    _channel.invokeMethod('destroyWindow');
  }
}
