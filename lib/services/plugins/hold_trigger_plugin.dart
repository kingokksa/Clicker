/// Hold trigger plugin — configure keys that auto-repeat when held
library;

import 'package:fluent_ui/fluent_ui.dart';
import '../plugin_system.dart';
import '../../screens/sidebar/hold_trigger_page.dart';

class HoldTriggerPlugin extends ClickerPlugin {
  @override
  final manifest = const ClickerPluginManifest(
    id: 'hold_trigger',
    name: '按住触发',
    version: '1.0.0',
    author: 'Clicker',
    icon: FluentIcons.keyboard_classic,
    category: PluginCategory.click,
    source: PluginSource.builtin,
    platforms: ['windows', 'linux', 'macos'],
  );

  @override
  Future<void> onInitialize() async {}

  @override
  Future<void> onDispose() async {}

  @override
  Widget onCreatePage(BuildContext context) => const HoldTriggerPage();
}
