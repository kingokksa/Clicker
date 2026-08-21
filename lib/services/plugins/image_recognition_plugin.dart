/// Image recognition plugin — 模板匹配、OCR、条件触发
library;

import '../plugin/plugin_api.dart';
import '../plugin/plugin_manifest.dart';
import '../plugin/plugin_manager.dart';
import '../../screens/sidebar/image_recognition_page.dart';

class ImageRecognitionPlugin extends Plugin {
  @override
  final PluginManifest manifest = const PluginManifest(
    id: 'image_recognition',
    name: '图像识别',
    version: '1.0.0',
    author: 'Clicker',
    description: '模板匹配与 OCR 识别，可作点击条件触发',
    category: 'vision',
    platforms: ['windows'],
    runtime: PluginRuntime.dart,
    permissions: [PluginPermission.screen, PluginPermission.input],
    activationEvents: ['manual'],
    contributions: PluginContributions(pages: [
      PageContribution(
          id: 'image_recognition', title: '图像识别', icon: 'image_pixel', order: 50),
    ]),
    icon: 'image_pixel',
  );

  @override
  Future<void> onActivate(PluginContext context) async {
    // 联动安装 AI 跟踪器（检测能力提供者）
    final manager = PluginManager.instance;
    final aiTracker = manager.byId('ai_tracker');
    if (aiTracker != null && !aiTracker.isInstalled) {
      await manager.installPlugin('ai_tracker');
    }

    context.registerPage(
      const PageContribution(
          id: 'image_recognition', title: '图像识别', icon: 'image_pixel', order: 50),
      (context) => const ImageRecognitionPage(),
    );
  }

  @override
  Future<void> onDeactivate() async {}
}
