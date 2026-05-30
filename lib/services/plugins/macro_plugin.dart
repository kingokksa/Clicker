/// Macro plugin — macro recording and playback
library;

import 'package:fluent_ui/fluent_ui.dart';
import '../plugin_system.dart';
import '../../screens/macro/macro_page.dart';

class MacroPlugin extends ClickerPlugin {
  @override
  final manifest = const ClickerPluginManifest(
    id: 'macro',
    name: '宏录制与回放',
    version: '1.0.0',
    author: 'Clicker',
    icon: FluentIcons.record2,
    category: PluginCategory.automation,
    source: PluginSource.builtin,
    platforms: ['windows', 'linux', 'macos'],
  );

  @override
  Future<void> onInitialize() async {}

  @override
  Future<void> onDispose() async {}

  @override
  Widget onCreatePage(BuildContext context) => const MacroPage();
}
