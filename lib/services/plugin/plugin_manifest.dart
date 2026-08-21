/// 插件清单模型 — 新插件系统的核心描述文件。
///
/// manifest.json 描述插件的元数据、运行时类型、权限、激活事件和贡献
/// （contributes）。宿主只在激活插件时才加载代码/分配资源，
/// 纯 manifest 阅读零开销，实现真正的即需即用。
library;

import 'dart:convert';
import 'dart:io' show Platform;

/// 插件运行时类型
enum PluginRuntime {
  dart('dart'),
  native('native');

  final String id;
  const PluginRuntime(this.id);

  static PluginRuntime fromString(String? s) =>
      PluginRuntime.values.firstWhere((r) => r.id == s, orElse: () => PluginRuntime.dart);
}

/// 插件权限
class PluginPermission {
  static const input = 'input';               // 发送鼠标/键盘输入
  static const screen = 'screen';             // 屏幕捕获
  static const storage = 'storage';           // 插件私有持久化存储
  static const notifications = 'notifications'; // 系统通知/应用内提示
  static const clipboard = 'clipboard';       // 剪贴板读写
  static const processes = 'processes';       // 进程/窗口枚举

  static const all = [input, screen, storage, notifications, clipboard, processes];
}

/// 页面贡献 — 插件向主导航贡献一个页面
class PageContribution {
  final String id;
  final String title;
  final String? icon;      // FluentIcons 图标名（见 icon_resolver）
  final int order;         // 导航排序，越小越靠前
  final bool showInNav;    // false 时不进导航（如后台服务型插件）
  final String? description;

  const PageContribution({
    required this.id,
    required this.title,
    this.icon,
    this.order = 100,
    this.showInNav = true,
    this.description,
  });

  factory PageContribution.fromJson(Map<String, dynamic> json) => PageContribution(
    id: json['id'] as String? ?? '',
    title: json['title'] as String? ?? json['id'] as String? ?? '',
    icon: json['icon'] as String?,
    order: json['order'] as int? ?? 100,
    showInNav: json['showInNav'] as bool? ?? true,
    description: json['description'] as String?,
  );
}

/// 命令贡献 — 插件注册一个可执行命令（热键/脚本/宏均可触发）
class CommandContribution {
  final String id;         // 完整命令 id：pluginId.actionId
  final String title;
  final String? category;

  const CommandContribution({required this.id, required this.title, this.category});

  factory CommandContribution.fromJson(Map<String, dynamic> json) => CommandContribution(
    id: json['id'] as String? ?? '',
    title: json['title'] as String? ?? json['id'] as String? ?? '',
    category: json['category'] as String?,
  );
}

/// 设置项类型
enum SettingType { toggle, number, slider, text, dropdown, hotkey, color }

/// 设置定义 — 声明式设置项，宿主负责渲染与持久化，插件只读写值
class SettingDefinition {
  final String key;
  final SettingType type;
  final String title;
  final String? description;
  final dynamic defaultValue;
  final double? min;
  final double? max;
  final int? precision;
  final String? unit;
  final List<Map<String, dynamic>> options; // dropdown: [{value, label}]

  const SettingDefinition({
    required this.key,
    required this.type,
    required this.title,
    this.description,
    this.defaultValue,
    this.min,
    this.max,
    this.precision,
    this.unit,
    this.options = const [],
  });

  factory SettingDefinition.fromJson(Map<String, dynamic> json) => SettingDefinition(
    key: json['key'] as String? ?? '',
    type: SettingType.values.firstWhere(
      (t) => t.name == json['type'],
      orElse: () => SettingType.text,
    ),
    title: json['title'] as String? ?? json['key'] as String? ?? '',
    description: json['description'] as String?,
    defaultValue: json['default'],
    min: (json['min'] as num?)?.toDouble(),
    max: (json['max'] as num?)?.toDouble(),
    precision: json['precision'] as int?,
    unit: json['unit'] as String?,
    options: (json['options'] as List?)
        ?.map((o) => Map<String, dynamic>.from(o as Map))
        .toList() ?? [],
  );
}

/// 输入后端贡献 — 插件提供一种新的输入注入方式（如硬件驱动）
class InputBackendContribution {
  final String id;
  final String name;
  final String? description;

  const InputBackendContribution({required this.id, required this.name, this.description});

  factory InputBackendContribution.fromJson(Map<String, dynamic> json) => InputBackendContribution(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? json['id'] as String? ?? '',
    description: json['description'] as String?,
  );
}

/// 视觉提供者贡献 — 插件提供模板匹配/OCR/目标检测等视觉能力
class VisionProviderContribution {
  final String id;
  final String kind;   // templateMatch | ocr | detect | colorMatch
  final String name;

  const VisionProviderContribution({required this.id, required this.kind, required this.name});

  factory VisionProviderContribution.fromJson(Map<String, dynamic> json) =>
    VisionProviderContribution(
      id: json['id'] as String? ?? '',
      kind: json['kind'] as String? ?? 'templateMatch',
      name: json['name'] as String? ?? json['id'] as String? ?? '',
    );
}

/// 贡献集合 — 插件向宿主声明的全部扩展
class PluginContributions {
  final List<PageContribution> pages;
  final List<CommandContribution> commands;
  final List<SettingDefinition> settings;
  final List<InputBackendContribution> inputBackends;
  final List<VisionProviderContribution> visionProviders;

  const PluginContributions({
    this.pages = const [],
    this.commands = const [],
    this.settings = const [],
    this.inputBackends = const [],
    this.visionProviders = const [],
  });

  factory PluginContributions.fromJson(Map<String, dynamic> json) => PluginContributions(
    pages: (json['pages'] as List?)
        ?.map((p) => PageContribution.fromJson(Map<String, dynamic>.from(p as Map)))
        .toList() ?? [],
    commands: (json['commands'] as List?)
        ?.map((c) => CommandContribution.fromJson(Map<String, dynamic>.from(c as Map)))
        .toList() ?? [],
    settings: (json['settings'] as List?)
        ?.map((s) => SettingDefinition.fromJson(Map<String, dynamic>.from(s as Map)))
        .toList() ?? [],
    inputBackends: (json['inputBackends'] as List?)
        ?.map((b) => InputBackendContribution.fromJson(Map<String, dynamic>.from(b as Map)))
        .toList() ?? [],
    visionProviders: (json['visionProviders'] as List?)
        ?.map((v) => VisionProviderContribution.fromJson(Map<String, dynamic>.from(v as Map)))
        .toList() ?? [],
  );
}

/// 插件清单 — manifest.json 的 Dart 模型
class PluginManifest {
  final String id;
  final String name;
  final String version;
  final String apiVersion;    // 插件 API 版本，宿主据此协商
  final String author;
  final String description;
  final String category;      // core|click|vision|automation|ui|extension
  final List<String> platforms;
  final PluginRuntime runtime;
  final Map<String, String> entry;    // native: 平台 -> 库相对路径
  final String? dartPluginId;         // dart: 内置注册 id（缺省同 id）
  final List<String> permissions;
  final List<String> activationEvents;
  final PluginContributions contributions;
  final String? icon;
  final int minAppVersion;
  final bool core;            // 核心插件：不可卸载

  const PluginManifest({
    required this.id,
    required this.name,
    required this.version,
    this.apiVersion = '1.0',
    this.author = '',
    this.description = '',
    this.category = 'extension',
    this.platforms = const [],
    this.runtime = PluginRuntime.dart,
    this.entry = const {},
    this.dartPluginId,
    this.permissions = const [],
    this.activationEvents = const ['manual'],
    this.contributions = const PluginContributions(),
    this.icon,
    this.minAppVersion = 1,
    this.core = false,
  });

  /// 从 manifest.json 解析
  factory PluginManifest.fromJson(Map<String, dynamic> json) => PluginManifest(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? '',
    version: json['version'] as String? ?? '1.0.0',
    apiVersion: json['apiVersion'] as String? ?? '1.0',
    author: json['author'] as String? ?? '',
    description: json['description'] as String? ?? '',
    category: json['category'] as String? ?? 'extension',
    platforms: (json['platforms'] as List?)?.cast<String>() ?? [],
    runtime: PluginRuntime.fromString(json['runtime'] as String?),
    entry: (json['entry'] as Map<String, dynamic>?)
        ?.map((k, v) => MapEntry(k, v.toString())) ?? {},
    dartPluginId: json['dartPluginId'] as String?,
    permissions: (json['permissions'] as List?)?.cast<String>() ?? [],
    activationEvents: (json['activationEvents'] as List?)
        ?.cast<String>() ?? ['manual'],
    contributions: json['contributes'] is Map
        ? PluginContributions.fromJson(
            Map<String, dynamic>.from(json['contributes'] as Map))
        : const PluginContributions(),
    icon: json['icon'] as String?,
    minAppVersion: json['minAppVersion'] as int? ?? 1,
    core: json['core'] as bool? ?? false,
  );

  factory PluginManifest.fromJsonString(String raw) =>
      PluginManifest.fromJson(jsonDecode(raw) as Map<String, dynamic>);

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'version': version,
    'apiVersion': apiVersion,
    'author': author,
    'description': description,
    'category': category,
    'platforms': platforms,
    'runtime': runtime.id,
    'entry': entry,
    if (dartPluginId != null) 'dartPluginId': dartPluginId,
    'permissions': permissions,
    'activationEvents': activationEvents,
    'contributions': {
      'pages': contributions.pages,
      'commands': contributions.commands,
      'settings': contributions.settings,
      'inputBackends': contributions.inputBackends,
      'visionProviders': contributions.visionProviders,
    },
    if (icon != null) 'icon': icon,
    'minAppVersion': minAppVersion,
    'core': core,
  };

  /// 当前平台是否支持
  bool get supportsCurrentPlatform {
    if (platforms.isEmpty) return true;
    return platforms.contains(currentPluginPlatform);
  }

  /// 是否按需激活（非启动即激活）
  bool get activatesOnDemand =>
      !activationEvents.contains('onStartup') && activationEvents.isNotEmpty;
}

/// 页面完整 id 解析规则：
/// - 声明 id 已含 ':' → 原样使用（显式完整 id）
/// - 声明 id == 插件 id → 原样使用（内置 Dart 插件约定）
/// - 其余 → 'pluginId:pageId'（避免原生插件间页面 id 冲突）
String resolveFullPageId(String pluginId, String declaredId) {
  if (declaredId.contains(':')) return declaredId;
  if (declaredId == pluginId) return declaredId;
  return '$pluginId:$declaredId';
}

/// 当前运行平台名（与 manifest.platforms / entry 的 key 对应）
String get currentPluginPlatform {
  if (Platform.isWindows) return 'windows';
  if (Platform.isLinux) return 'linux';
  if (Platform.isMacOS) return 'darwin';
  if (Platform.isAndroid) return 'android';
  return 'unknown';
}
