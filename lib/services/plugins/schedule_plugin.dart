/// 定时任务插件 — 定时自动开始 / 停止连点。
library;

import '../plugin/plugin_api.dart';
import '../plugin/plugin_manifest.dart';
import '../../screens/sidebar/schedule_page.dart';

class SchedulePlugin extends Plugin {
  @override
  final PluginManifest manifest = const PluginManifest(
    id: 'schedule',
    name: '定时任务',
    version: '1.0.0',
    author: 'Clicker',
    description: '定时自动开始 / 停止连点',
    category: 'automation',
    platforms: ['windows', 'linux', 'macos'],
    runtime: PluginRuntime.dart,
    permissions: [PluginPermission.storage],
    activationEvents: ['manual'],
    contributions: PluginContributions(pages: [
      PageContribution(
          id: 'schedule', title: '定时任务', icon: 'clock', order: 55),
    ]),
    icon: 'clock',
  );

  @override
  Future<void> onActivate(PluginContext context) async {
    context.registerPage(
      const PageContribution(
          id: 'schedule', title: '定时任务', icon: 'clock', order: 55),
      (context) => const SchedulePage(),
    );
  }

  @override
  Future<void> onDeactivate() async {}
}