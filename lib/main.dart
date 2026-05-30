/// Main entry point.
library;

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart';
import 'package:flutter/services.dart';
import 'app.dart';
import 'services/plugin_registry.dart';
import 'services/plugins/macro_plugin.dart';
import 'services/plugins/hold_trigger_plugin.dart';
import 'services/plugins/image_recognition_plugin.dart';
import 'services/plugins/theme_center_plugin.dart';
import 'services/plugins/background_execution_plugin.dart';
import 'services/plugins/ai_tracker_plugin.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final registry = PluginRegistry.instance;
  registry.registerPlugin(MacroPlugin());
  registry.registerPlugin(HoldTriggerPlugin());
  registry.registerPlugin(ImageRecognitionPlugin());
  registry.registerPlugin(ThemeCenterPlugin());
  registry.registerPlugin(BackgroundExecutionPlugin());
  registry.registerPlugin(AiTrackerPlugin());
  await registry.loadState();

  // Configure window for desktop
  await windowManager.ensureInitialized();
  await windowManager.setMinimumSize(const Size(500, 680));
  await windowManager.setSize(const Size(920, 720));
  await windowManager.setTitle('Clicker');
  await windowManager.center();
  await windowManager.setPreventClose(true);

  // Enable acrylic / mica effect
  try {
    await Window.initialize();
    await Window.setEffect(
      effect: WindowEffect.acrylic,
      color: const Color(0xFF1A1A2E),
      dark: true,
    );
  } catch (_) {
    // Acrylic may fail on older Windows versions — continue without it
  }

  // Re-apply DWM fixes immediately after flutter_acrylic overrides them.
  // flutter_acrylic's setEffect() resets DwmExtendFrameIntoClientArea margins,
  // which causes white border flash to return.
  try {
    const platformChannel = MethodChannel('com.clicker.pro/platform');
    await platformChannel.invokeMethod('reapplyDwmFixes');
  } catch (_) {
    // DWM fixes are non-critical — continue without them
  }

  runApp(const ClickerApp());
}
