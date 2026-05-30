/// Theme center plugin — theme presets, accent colors, visual effects
library;

import 'package:fluent_ui/fluent_ui.dart';
import '../plugin_system.dart';
import '../../screens/sidebar/theme_center_page.dart';

class ThemeCenterPlugin extends ClickerPlugin {
  @override
  final manifest = const ClickerPluginManifest(
    id: 'theme_center',
    name: '主题中心',
    version: '1.0.0',
    author: 'Clicker',
    icon: FluentIcons.color,
    category: PluginCategory.ui,
    source: PluginSource.builtin,
    platforms: ['windows', 'linux', 'macos'],
  );

  @override
  Future<void> onInitialize() async {}

  @override
  Future<void> onDispose() async {}

  @override
  Widget onCreatePage(BuildContext context) => const ThemeCenterPage();
}
