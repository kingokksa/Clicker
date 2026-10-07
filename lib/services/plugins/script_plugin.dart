import '../../screens/sidebar/script_page.dart';
import '../plugin/plugin_api.dart';
import '../plugin/plugin_manifest.dart';

class ScriptPlugin extends Plugin {
  @override
  final PluginManifest manifest = const PluginManifest(
    id: 'script',
    name: '脚本',
    version: '1.0.0',
    author: 'Clicker',
    category: 'input',
    platforms: ['windows', 'linux', 'macos'],
    runtime: PluginRuntime.dart,
    permissions: [PluginPermission.input, PluginPermission.storage],
    activationEvents: ['manual'],
    contributions: PluginContributions(pages: [
      PageContribution(id: 'script', title: '脚本', icon: 'command_prompt', order: 57),
    ]),
    icon: 'command_prompt',
  );

  @override
  Future<void> onActivate(PluginContext context) async {
    context.registerPage(
      const PageContribution(id: 'script', title: '脚本', icon: 'command_prompt', order: 57),
      (context) => const ScriptPage(),
    );
  }

  @override
  Future<void> onDeactivate() async {}
}
