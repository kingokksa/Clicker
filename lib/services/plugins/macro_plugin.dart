/// Macro plugin — 宏录制与回放
library;

import '../plugin/plugin_api.dart';
import '../plugin/plugin_manifest.dart';
import '../../screens/macro/macro_page.dart';

class MacroPlugin extends Plugin {
  @override
  final PluginManifest manifest = const PluginManifest(
    id: 'macro',
    name: '宏录制与回放',
    version: '1.0.0',
    author: 'Clicker',
    description: '录制鼠标键盘操作并按需回放，支持循环与条件',
    category: 'automation',
    platforms: ['windows', 'linux', 'macos'],
    runtime: PluginRuntime.dart,
    permissions: [PluginPermission.input, PluginPermission.storage],
    activationEvents: ['manual'],
    contributions: PluginContributions(pages: [
      PageContribution(id: 'macro', title: '宏', icon: 'record2', order: 20),
    ]),
    icon: 'record2',
  );

  @override
  Future<void> onActivate(PluginContext context) async {
    context.registerPage(
      const PageContribution(id: 'macro', title: '宏', icon: 'record2', order: 20),
      (context) => const MacroPage(),
    );
  }

  @override
  Future<void> onDeactivate() async {
    // MacroService 由 AppState 持有，这里无需清理
  }
}
