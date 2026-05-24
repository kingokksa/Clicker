/// Main entry point.
library;

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart';
import 'app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Configure window for desktop
  await windowManager.ensureInitialized();
  await windowManager.setMinimumSize(const Size(500, 680));
  await windowManager.setSize(const Size(920, 720));
  await windowManager.setTitle('Clicker');
  await windowManager.center();
  await windowManager.setPreventClose(true);
  // Do NOT use setAsFrameless() -- it conflicts with WM_NCCALCSIZE in C++.
  // The WM_NCCALCSIZE handler in flutter_window.cpp removes the native title bar
  // while keeping the window frame for proper resize behavior.
  // Using both causes duplicate window buttons overlapping.

  // Enable acrylic / mica effect
  await Window.initialize();
  await Window.setEffect(
    effect: WindowEffect.acrylic,
    color: const Color(0xFF1A1A2E),
    dark: true,
  );

  runApp(const ClickerApp());
}
