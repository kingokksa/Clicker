/// Image recognition plugin — template matching, OCR, condition triggers
library;

import 'package:fluent_ui/fluent_ui.dart';
import '../plugin_system.dart';
import '../plugin_registry.dart';
import 'ai_tracker_plugin.dart';
import '../../screens/sidebar/image_recognition_page.dart';

class ImageRecognitionPlugin extends ClickerPlugin {
  @override
  final manifest = const ClickerPluginManifest(
    id: 'image_recognition',
    name: '图像识别',
    version: '1.0.0',
    author: 'Clicker',
    icon: FluentIcons.image_pixel,
    category: PluginCategory.vision,
    source: PluginSource.builtin,
    platforms: ['windows'],
  );

  @override
  Future<void> onInitialize() async {
    // Install AI tracker together with image recognition
    final registry = PluginRegistry.instance;
    final aiTracker = registry.getPlugin('ai_tracker');
    if (aiTracker != null && !aiTracker.installed) {
      await registry.installPlugin('ai_tracker');
    }
  }

  @override
  Future<void> onDispose() async {}

  @override
  Future<void> onUninstall() async {
    // Uninstall AI tracker together with image recognition
    final registry = PluginRegistry.instance;
    final aiTracker = registry.getPlugin('ai_tracker');
    if (aiTracker != null && aiTracker.installed) {
      await registry.uninstallPlugin('ai_tracker');
    }
  }

  @override
  Widget onCreatePage(BuildContext context) => const ImageRecognitionPage();
}
