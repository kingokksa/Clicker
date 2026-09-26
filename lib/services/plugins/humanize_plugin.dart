/// 拟人模式插件 — 拟人化节奏与反检测设置（随机偏移 / 延迟 / 抖动）。
library;

import '../plugin/plugin_api.dart';
import '../plugin/plugin_manifest.dart';
import '../../screens/sidebar/humanize_page.dart';

class HumanizePlugin extends Plugin {
  @override
  final PluginManifest manifest = const PluginManifest(
    id: 'humanize',
    name: '拟人模式',
    version: '1.0.0',
    author: 'Clicker',
    description: '拟人化节奏与反检测：随机偏移、随机延迟、按键抖动',
    category: 'click',
    platforms: ['windows', 'linux', 'macos'],
    runtime: PluginRuntime.dart,
    permissions: [PluginPermission.storage],
    activationEvents: ['manual'],
    contributions: PluginContributions(pages: [
      PageContribution(
          id: 'humanize', title: '拟人模式', icon: 'accounts', order: 35),
    ]),
    icon: 'accounts',
  );

  @override
  Future<void> onActivate(PluginContext context) async {
    context.registerPage(
      const PageContribution(
          id: 'humanize', title: '拟人模式', icon: 'accounts', order: 35),
      (context) => const HumanizePage(),
    );
  }

  @override
  Future<void> onDeactivate() async {}
}