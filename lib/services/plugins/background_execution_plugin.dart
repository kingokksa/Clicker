/// Background execution plugin — send clicks to background windows
library;

import 'package:fluent_ui/fluent_ui.dart';
import '../plugin_system.dart';
import '../../screens/sidebar/background_execution_page.dart';

class BackgroundExecutionPlugin extends ClickerPlugin {
  @override
  final manifest = const ClickerPluginManifest(
    id: 'background_execution',
    name: '后台执行',
    version: '1.0.0',
    author: 'Clicker',
    icon: FluentIcons.remote,
    category: PluginCategory.automation,
    source: PluginSource.builtin,
    platforms: ['windows'],
  );

  @override
  Future<void> initialize() async {}

  @override
  Future<void> dispose() async {}

  @override
  Widget buildPage(BuildContext context) => const BackgroundExecutionPage();
}
