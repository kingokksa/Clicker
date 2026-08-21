/// Background execution plugin — 后台窗口操作
library;

import '../plugin/plugin_api.dart';
import '../plugin/plugin_manifest.dart';
import '../../screens/sidebar/background_execution_page.dart';

class BackgroundExecutionPlugin extends Plugin {
  @override
  final PluginManifest manifest = const PluginManifest(
    id: 'background_execution',
    name: '后台执行',
    version: '1.0.0',
    author: 'Clicker',
    description: '向指定窗口后台发送输入，不抢占前台焦点',
    category: 'click',
    platforms: ['windows'],
    runtime: PluginRuntime.dart,
    permissions: [PluginPermission.input, PluginPermission.processes],
    activationEvents: ['manual'],
    contributions: PluginContributions(pages: [
      PageContribution(
          id: 'background_execution', title: '后台执行', icon: 'window_edit', order: 40),
    ]),
    icon: 'window_edit',
  );

  @override
  Future<void> onActivate(PluginContext context) async {
    context.registerPage(
      const PageContribution(
          id: 'background_execution', title: '后台执行', icon: 'window_edit', order: 40),
      (context) => const BackgroundExecutionPage(),
    );
  }

  @override
  Future<void> onDeactivate() async {}
}
