library;

import '../plugin/plugin_api.dart';
import '../plugin/plugin_manifest.dart';
import '../../screens/sidebar/api_page.dart';

class ApiPlugin extends Plugin {
  @override
  final PluginManifest manifest = const PluginManifest(
    id: 'external_api',
    name: '外部接口',
    version: '1.0.0',
    author: 'Clicker',
    description: '供外部程序与 AI 调用的 MCP / REST 接口',
    category: 'automation',
    platforms: ['windows', 'linux', 'macos'],
    runtime: PluginRuntime.dart,
    permissions: [PluginPermission.storage],
    activationEvents: ['manual'],
    contributions: PluginContributions(pages: [
      PageContribution(
          id: 'external_api',
          title: '外部接口',
          icon: 'developer_tools',
          order: 65),
    ]),
    icon: 'developer_tools',
  );

  @override
  Future<void> onActivate(PluginContext context) async {
    context.registerPage(
      const PageContribution(
          id: 'external_api',
          title: '外部接口',
          icon: 'developer_tools',
          order: 65),
      (context) => const ApiPage(),
    );
  }

  @override
  Future<void> onDeactivate() async {}
}
