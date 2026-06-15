library;

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart' as acrylic;
import 'app.dart';
import 'mobile_app.dart';
import 'services/plugin_registry.dart';
import 'services/plugins/macro_plugin.dart';
import 'services/plugins/hold_trigger_plugin.dart';
import 'services/plugins/image_recognition_plugin.dart';
import 'services/plugins/theme_center_plugin.dart';
import 'services/plugins/background_execution_plugin.dart';
import 'services/plugins/ai_tracker_plugin.dart';
import 'services/system_tray_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    final registry = PluginRegistry.instance;
    registry.registerPlugin(MacroPlugin());
    registry.registerPlugin(HoldTriggerPlugin());
    registry.registerPlugin(ImageRecognitionPlugin());
    registry.registerPlugin(ThemeCenterPlugin());
    registry.registerPlugin(BackgroundExecutionPlugin());
    registry.registerPlugin(AiTrackerPlugin());
    await registry.loadState();

    await _initDesktopWindow();
    runApp(const ClickerApp());
  } else {
    // Mobile (Android/iOS) — use Material app
    // Initialize SystemTrayService to set up MethodChannel handler for overlay callbacks
    await SystemTrayService().init();
    runApp(const MobileClickerApp());
  }
}

Future<void> _initDesktopWindow() async {
  try {
    await windowManager.ensureInitialized();
    await windowManager.setMinimumSize(const Size(500, 680));
    await windowManager.setSize(const Size(920, 720));
    await windowManager.setTitle('Clicker');
    await windowManager.center();
    await windowManager.setPreventClose(true);
  } catch (_) {}

  if (Platform.isWindows) {
    try {
      await acrylic.Window.initialize();
      await acrylic.Window.setEffect(
        effect: acrylic.WindowEffect.acrylic,
        color: const Color(0xFF1A1A2E),
        dark: true,
      );
    } catch (_) {}

    try {
      const platformChannel = MethodChannel('com.clicker.pro/platform');
      await platformChannel.invokeMethod('reapplyDwmFixes');
    } catch (_) {}
  }
}
