/// 插件图标解析 — manifest 的 icon 字符串名映射到 FluentIcons。
/// 原生插件用字符串声明图标，宿主渲染时解析为 IconData。
library;

import 'package:fluent_ui/fluent_ui.dart';

/// 常用图标映射表（与 FluentIcons 字段名一致）
final Map<String, IconData> pluginIconMap = {
  'puzzle': FluentIcons.puzzle,
  'touch': FluentIcons.touch,
  'image_pixel': FluentIcons.image_pixel,
  'process_meta_task': FluentIcons.process_meta_task,
  'color': FluentIcons.color,
  'record2': FluentIcons.record2,
  'keyboard_classic': FluentIcons.keyboard_classic,
  'machine_learning': FluentIcons.machine_learning,
  'devices3': FluentIcons.devices3,
  'focus_view': FluentIcons.focus_view,
  'photo2': FluentIcons.photo2,
  'command_prompt': FluentIcons.command_prompt,
  'settings': FluentIcons.settings,
  'developer_tools': FluentIcons.developer_tools,
  'chat_bot': FluentIcons.chat_bot,
  'game': FluentIcons.game,
  'timer': FluentIcons.timer,
  'play': FluentIcons.play,
  'stop': FluentIcons.stop,
  'lightning_bolt': FluentIcons.lightning_bolt,
  'send': FluentIcons.send,
  'save': FluentIcons.save,
  'stack': FluentIcons.stack,
  'back_to_window': FluentIcons.back_to_window,
  'scroll_up_down': FluentIcons.scroll_up_down,
  'clock': FluentIcons.clock,
  'accounts': FluentIcons.accounts,
};

/// 解析图标名；未知名回退到 puzzle
IconData resolvePluginIcon(String? name) {
  if (name == null) return FluentIcons.puzzle;
  return pluginIconMap[name] ?? FluentIcons.puzzle;
}
