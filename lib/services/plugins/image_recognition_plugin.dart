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
  Future<void> onInitialize() async {}

  @override
  Future<void> onDispose() async {}

  @override
  Widget onCreatePage(BuildContext context) => const ImageRecognitionPage();
}
