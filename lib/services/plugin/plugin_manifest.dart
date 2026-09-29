
import 'dart:convert';
import 'dart:io' show Platform;

enum PluginRuntime {
  dart('dart'),
  native('native');

  final String id;
  const PluginRuntime(this.id);

  static PluginRuntime fromString(String? s) =>
      PluginRuntime.values.firstWhere((r) => r.id == s, orElse: () => PluginRuntime.dart);
}

class PluginPermission {
  static const input = 'input';
  static const screen = 'screen';
  static const storage = 'storage';
  static const notifications = 'notifications';
  static const clipboard = 'clipboard';
  static const processes = 'processes';

  static const all = [input, screen, storage, notifications, clipboard, processes];
}

class PageContribution {
  final String id;
  final String title;
  final String? icon;
  final int order;
  final bool showInNav;
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

class CommandContribution {
  final String id;
  final String title;
  final String? category;

  const CommandContribution({required this.id, required this.title, this.category});

  factory CommandContribution.fromJson(Map<String, dynamic> json) => CommandContribution(
    id: json['id'] as String? ?? '',
    title: json['title'] as String? ?? json['id'] as String? ?? '',
    category: json['category'] as String?,
  );
}

enum SettingType { toggle, number, slider, text, dropdown, hotkey, color }

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
  final List<Map<String, dynamic>> options;

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

class VisionProviderContribution {
  final String id;
  final String kind;
  final String name;

  const VisionProviderContribution({required this.id, required this.kind, required this.name});

  factory VisionProviderContribution.fromJson(Map<String, dynamic> json) =>
    VisionProviderContribution(
      id: json['id'] as String? ?? '',
      kind: json['kind'] as String? ?? 'templateMatch',
      name: json['name'] as String? ?? json['id'] as String? ?? '',
    );
}

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

class PluginManifest {
  final String id;
  final String name;
  final String version;
  final String apiVersion;
  final String author;
  final String description;
  final String category;
  final List<String> platforms;
  final PluginRuntime runtime;
  final Map<String, String> entry;
  final String? dartPluginId;
  final List<String> permissions;
  final List<String> activationEvents;
  final PluginContributions contributions;
  final String? icon;
  final int minAppVersion;
  final bool core;

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

  bool get supportsCurrentPlatform {
    if (platforms.isEmpty) return true;
    return platforms.contains(currentPluginPlatform);
  }

  bool get activatesOnDemand =>
      !activationEvents.contains('onStartup') && activationEvents.isNotEmpty;
}

String resolveFullPageId(String pluginId, String declaredId) {
  if (declaredId.contains(':')) return declaredId;
  if (declaredId == pluginId) return declaredId;
  return '$pluginId:$declaredId';
}

String get currentPluginPlatform {
  if (Platform.isWindows) return 'windows';
  if (Platform.isLinux) return 'linux';
  if (Platform.isMacOS) return 'darwin';
  if (Platform.isAndroid) return 'android';
  return 'unknown';
}
