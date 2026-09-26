library;

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'app.dart';
import 'mobile_app.dart';
import 'services/plugin/plugin_manager.dart';
import 'services/plugin/declarative_settings.dart';
import 'services/plugins/macro_plugin.dart';
import 'services/plugins/hold_trigger_plugin.dart';
import 'services/plugins/image_recognition_plugin.dart';
import 'services/plugins/theme_center_plugin.dart';
import 'services/plugins/background_execution_plugin.dart';
import 'services/plugins/ai_tracker_plugin.dart';
import 'services/plugins/schedule_plugin.dart';
import 'services/plugins/humanize_plugin.dart';
import 'services/system_tray_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    _registerBuiltinPlugins();
    await _initDesktopWindow();
    runApp(const ClickerApp());
  } else {
    // Mobile (Android/iOS) — use Material app
    // Initialize SystemTrayService to set up MethodChannel handler for overlay callbacks
    await SystemTrayService().init();
    runApp(const MobileClickerApp());
  }
}

/// 注册内置 Dart 插件工厂。
/// 惰性实例化：注册时仅创建探针实例读取 manifest，激活时才创建正式实例。
/// initialize() 由 AppState.init() 在宿主服务就绪后调用。
void _registerBuiltinPlugins() {
  final pm = PluginManager.instance;
  pm.registerDartPlugin(MacroPlugin.new);
  pm.registerDartPlugin(HoldTriggerPlugin.new);
  pm.registerDartPlugin(ImageRecognitionPlugin.new);
  pm.registerDartPlugin(ThemeCenterPlugin.new);
  pm.registerDartPlugin(BackgroundExecutionPlugin.new);
  pm.registerDartPlugin(AiTrackerPlugin.new);
  pm.registerDartPlugin(SchedulePlugin.new);
  pm.registerDartPlugin(HumanizePlugin.new);
  // 原生插件声明式设置页的渲染工厂（UI 层注入）
  PluginManager.declarativePageFactory = buildDeclarativePluginPage;
}

Future<void> _initDesktopWindow() async {
  try {
    await windowManager.ensureInitialized();
    await windowManager.setMinimumSize(const Size(500, 680));
    await windowManager.setSize(const Size(1080, 760));
    await windowManager.setTitle('Clicker');
    await windowManager.center();
    await windowManager.setPreventClose(true);
  } catch (_) {}
}
