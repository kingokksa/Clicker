/// Image recognition plugin — template matching, OCR, condition triggers
library;

import 'package:fluent_ui/fluent_ui.dart';
import '../plugin_system.dart';
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
  Future<void> initialize() async {}

  @override
  Future<void> dispose() async {}

  @override
  Widget buildPage(BuildContext context) => const ImageRecognitionPage();
}
