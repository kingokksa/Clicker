/// Hold trigger plugin — 按住自动连发
library;

import '../plugin/plugin_api.dart';
import '../plugin/plugin_manifest.dart';
import '../../screens/sidebar/hold_trigger_page.dart';

class HoldTriggerPlugin extends Plugin {
  @override
  final PluginManifest manifest = const PluginManifest(
    id: 'hold_trigger',
    name: '按住触发',
    version: '1.0.0',
    author: 'Clicker',
    description: '按住指定按键时自动连发，松开即停',
    category: 'click',
    platforms: ['windows', 'linux', 'macos'],
    runtime: PluginRuntime.dart,
    permissions: [PluginPermission.input, PluginPermission.storage],
    activationEvents: ['manual'],
    contributions: PluginContributions(pages: [
      PageContribution(
          id: 'hold_trigger', title: '按住触发', icon: 'keyboard_classic', order: 30),
    ]),
    icon: 'keyboard_classic',
  );

  @override
  Future<void> onActivate(PluginContext context) async {
    context.registerPage(
      const PageContribution(
          id: 'hold_trigger', title: '按住触发', icon: 'keyboard_classic', order: 30),
      (context) => const HoldTriggerPage(),
    );
  }

  @override
  Future<void> onDeactivate() async {}
}
