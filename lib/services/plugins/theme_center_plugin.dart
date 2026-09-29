
import '../plugin/plugin_api.dart';
import '../plugin/plugin_manifest.dart';
import '../../screens/sidebar/theme_center_page.dart';

class ThemeCenterPlugin extends Plugin {
  @override
  final PluginManifest manifest = const PluginManifest(
    id: 'theme_center',
    name: '主题中心',
    version: '1.0.0',
    author: 'Clicker',
    category: 'ui',
    platforms: ['windows', 'linux', 'macos'],
    runtime: PluginRuntime.dart,
    permissions: [PluginPermission.storage],
    activationEvents: ['manual'],
    contributions: PluginContributions(pages: [
      PageContribution(id: 'theme_center', title: '主题中心', icon: 'color', order: 60),
    ]),
    icon: 'color',
  );

  @override
  Future<void> onActivate(PluginContext context) async {
    context.registerPage(
      const PageContribution(id: 'theme_center', title: '主题中心', icon: 'color', order: 60),
      (context) => const ThemeCenterPage(),
    );
  }

  @override
  Future<void> onDeactivate() async {}
}
