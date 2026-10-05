
import '../../screens/sidebar/key_alias_page.dart';
import '../plugin/plugin_api.dart';
import '../plugin/plugin_manifest.dart';

class KeyAliasPlugin extends Plugin {
  @override
  final PluginManifest manifest = const PluginManifest(
    id: 'key_alias',
    name: '按键别名',
    version: '1.0.0',
    author: 'Clicker',
    category: 'input',
    platforms: ['windows', 'linux', 'macos'],
    runtime: PluginRuntime.dart,
    permissions: [PluginPermission.input, PluginPermission.storage],
    activationEvents: ['manual'],
    contributions: PluginContributions(pages: [
      PageContribution(
          id: 'key_alias', title: '按键别名', icon: 'keyboard_classic', order: 60),
    ]),
    icon: 'keyboard_classic',
  );

  @override
  Future<void> onActivate(PluginContext context) async {
    context.registerPage(
      const PageContribution(
          id: 'key_alias', title: '按键别名', icon: 'keyboard_classic', order: 60),
      (context) => const KeyAliasPage(),
    );
  }

  @override
  Future<void> onDeactivate() async {}
}
