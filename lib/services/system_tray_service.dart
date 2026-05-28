/// System tray service — minimize to tray, tray menu.
/// Uses platform channel to call native Win32 Shell_NotifyIcon API.
/// Also serves as the central MethodCallHandler for the
/// 'com.clicker.pro/platform' channel, dispatching events to
/// registered callbacks so that no other widget overwrites the handler.
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

  /// Reference to platform input for forwarding native callbacks.
  PlatformInput? platformInput;

  /// External method call handlers registered by other widgets/pages.
  /// Each handler can return a non-null value to indicate it handled the call,
  /// or null to let the next handler (or the default handler) process it.
  final List<Future<dynamic> Function(MethodCall)> _externalHandlers = [];

  /// Register an external method call handler. Returns a function that
  /// unregisters the handler when called.
  VoidCallback registerExternalHandler(
      Future<dynamic> Function(MethodCall) handler) {
    _externalHandlers.add(handler);
    return () {
      _externalHandlers.remove(handler);
    };
  }

  Future<void> init() async {
    if (_initialized || !Platform.isWindows) return;

    _channel.setMethodCallHandler(_handleMethodCall);
    await _channel.invokeMethod('initSystemTray');
    _initialized = true;
  }

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    // First, try external handlers (e.g., overlay callbacks from pages)
    for (final handler in _externalHandlers) {
      try {
        final result = await handler(call);
        if (result != null) return result;
      } catch (_) {
        // Handler threw, continue to next
      }
    }

    // Default handling for system-level events
    switch (call.method) {
      case 'onTrayIconClick':
        windowManager.show();
        windowManager.focus();
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
    windowManager.hide();
  }

  void showFromTray() {
    windowManager.show();
    windowManager.focus();
  }

  void dispose() {
    _channel.invokeMethod('destroySystemTray');
    _initialized = false;
  }

  void _cleanupAndExit() {
    // Stop native fast clicker immediately
    _channel.invokeMethod('stopFastClicker');
    // Destroy tray icon
    _channel.invokeMethod('destroySystemTray');
    _initialized = false;
    // Immediately destroy window and quit
    _channel.invokeMethod('destroyWindow');
  }
}
