/// Plugin store — 多源插件商店聚合。
///
/// 源体系见 plugin_sources.dart：
/// - 官方源（GitHub 官方仓库）
/// - 第三方源（其他作者自己的 GitHub 仓库，用户可添加）
/// - 直接导入（GitHub zip / 插件仓库 / Release 链接）
///
/// 拉取流程：本地内置索引（秒开）→ 遍历所有启用的源聚合远程索引。
library;

import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'app_paths.dart';
import 'plugin/plugin_manager.dart';
import 'plugin/plugin_manifest.dart' show currentPluginPlatform;
import 'plugin/plugin_sources.dart';

/// Remote plugin entry from a store index
class StorePluginEntry {
  final String id;
  final String name;
  final String version;
  final String author;
  final String description;
  final String category;
  final List<String> platforms;
  final String type;        // "dart" or "native"
  final String? dartPluginId; // For dart plugins: the id used by PluginManager
  final String? icon;
  final int size;           // Download size in bytes (0 for dart plugins)
  final String? downloadUrl; // For native plugins: zip download URL
  final int minAppVersion;

  // 来源信息（多源聚合）
  final String sourceId;    // 所属源 id（'official' / 'src_xxx'）
  final String sourceName;  // 所属源显示名

  const StorePluginEntry({
    required this.id,
    required this.name,
    required this.version,
    this.author = '',
    this.description = '',
    this.category = 'extension',
    this.platforms = const [],
    this.type = 'dart',
    this.dartPluginId,
    this.icon,
    this.size = 0,
    this.downloadUrl,
    this.minAppVersion = 1,
    this.sourceId = 'official',
    this.sourceName = '官方插件',
  });

  factory StorePluginEntry.fromJson(Map<String, dynamic> json,
      {String sourceId = 'official', String sourceName = '官方插件'}) {
    return StorePluginEntry(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      version: json['version'] as String? ?? '1.0.0',
      author: json['author'] as String? ?? '',
      description: json['description'] as String? ?? '',
      category: json['category'] as String? ?? 'extension',
      platforms: (json['platforms'] as List?)?.cast<String>() ?? [],
      type: json['type'] as String? ?? 'dart',
      dartPluginId: json['dartPluginId'] as String?,
      icon: json['icon'] as String?,
      size: json['size'] as int? ?? 0,
      downloadUrl: json['downloadUrl'] as String?,
      minAppVersion: json['minAppVersion'] as int? ?? 1,
      sourceId: json['sourceId'] as String? ?? sourceId,
      sourceName: json['sourceName'] as String? ?? sourceName,
    );
  }

  /// Whether this plugin supports the current platform
  bool get supportsCurrentPlatform {
    return platforms.contains(currentPluginPlatform);
  }

  /// Whether this plugin is already installed locally
  bool get isInstalled {
    final desc = PluginManager.instance.byId(dartPluginId ?? id);
    return desc != null && desc.isInstalled;
  }

  /// Whether this plugin is already enabled
  bool get isEnabled {
    final pid = dartPluginId ?? id;
    final pm = PluginManager.instance;
    return pm.isInstalled(pid) && pm.isEnabled(pid);
  }
}

/// Plugin store — aggregates remote plugin indexes from multiple sources
class PluginStore extends ChangeNotifier {
  PluginStore._();
  static final PluginStore instance = PluginStore._();

  List<StorePluginEntry> _plugins = [];
  bool _isLoading = false;
  String? _error;

  List<StorePluginEntry> get plugins => _plugins;
  bool get isLoading => _isLoading;
  String? get error => _error;

  /// Available plugins (not yet installed)
  List<StorePluginEntry> get availablePlugins =>
    _plugins.where((p) => !p.isInstalled && p.supportsCurrentPlatform).toList();

  /// Updatable plugins (installed but newer version available)
  List<StorePluginEntry> get updatablePlugins {
    return _plugins.where((p) {
      if (!p.isInstalled) return false;
      final desc = PluginManager.instance.byId(p.dartPluginId ?? p.id);
      if (desc == null) return false;
      return _compareVersions(p.version, desc.manifest.version) > 0;
    }).toList();
  }

  /// Fetch indexes from all enabled sources.
  /// Always loads local bundled index first, then aggregates remote sources.
  Future<void> fetchIndex() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    // 1. Always load local bundled index first (instant, always available)
    await _loadBundledIndex();
    notifyListeners();

    // 2. Aggregate all enabled remote sources
    try {
      await PluginSourceRepository.instance.load();
      final sources =
          PluginSourceRepository.instance.enabledSources.toList();

      final remote = <StorePluginEntry>[];
      var anyOk = false;
      for (final source in sources) {
        final json =
            await PluginSourceRepository.fetchIndexJson(source.indexUrl);
        if (json == null) {
          source.error = '索引无法访问';
          source.pluginCount = 0;
          continue;
        }
        anyOk = true;
        source.error = null;
        // 用索引里的 name 更新源显示名
        final idxName = json['name'] as String?;
        if (idxName != null && idxName.isNotEmpty) source.name = idxName;
        final list = (json['plugins'] as List? ?? []);
        final entries = list
            .map((p) => StorePluginEntry.fromJson(
                  Map<String, dynamic>.from(p as Map),
                  sourceId: source.id,
                  sourceName: source.name,
                ))
            .where((p) => p.id.isNotEmpty)
            .toList();
        source.pluginCount = entries.length;
        remote.addAll(entries);
      }

      if (anyOk && remote.isNotEmpty) {
        // 同 id 去重：官方源优先，然后按源顺序
        final seen = <String>{};
        _plugins = remote.where((p) {
          final key = p.dartPluginId ?? p.id;
          if (seen.contains(key)) return false;
          seen.add(key);
          return true;
        }).toList();
        _error = null;
      } else if (!anyOk && sources.isNotEmpty) {
        // 所有远程源都失败 — 保留本地索引
        _error = '所有远程源均无法访问';
      }
      await PluginSourceRepository.instance.save();
    } catch (e) {
      // Remote failed — keep local index, just note the error
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Load the bundled plugin index from the plugins/ directory
  Future<void> _loadBundledIndex() async {
    try {
      final exePath = Platform.resolvedExecutable;
      final exeDir = File(exePath).parent.path;
      // Try multiple paths: next to exe, project root, relative
      final candidates = [
        '$exeDir${Platform.pathSeparator}plugins${Platform.pathSeparator}plugin_index.json',
        'plugins${Platform.pathSeparator}plugin_index.json',
        // When running from project root in dev mode
        '$exeDir${Platform.pathSeparator}..${Platform.pathSeparator}..${Platform.pathSeparator}..${Platform.pathSeparator}..${Platform.pathSeparator}plugins${Platform.pathSeparator}plugin_index.json',
      ];
      for (final path in candidates) {
        final file = File(path);
        if (await file.exists()) {
          final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
          final pluginList = (json['plugins'] as List?) ?? [];
          _plugins = pluginList
            .map((p) => StorePluginEntry.fromJson(p as Map<String, dynamic>))
            .where((p) => p.id.isNotEmpty)
            .toList();
          return;
        }
      }
      // No local index found — generate from registered Dart plugins
      _generateBundledIndex();
    } catch (_) {
      _generateBundledIndex();
    }
  }

  /// Generate index from currently registered built-in plugins as last resort
  void _generateBundledIndex() {
    _plugins = PluginManager.instance.plugins
      .where((d) => d.isBuiltin)
      .map((d) {
        final m = d.manifest;
        return StorePluginEntry(
          id: m.id,
          name: m.name,
          version: m.version,
          author: m.author,
          description: m.description,
          category: m.category,
          platforms: m.platforms,
          type: 'dart',
          dartPluginId: m.id,
          minAppVersion: 1,
        );
      }).toList();
  }

  /// Install a plugin from the store
  Future<bool> installPlugin(StorePluginEntry entry) async {
    if (entry.type == 'dart') {
      return _installDartPlugin(entry);
    } else {
      return _installNativePlugin(entry);
    }
  }

  /// Install a Dart plugin — install + enable（onStartup 插件立即激活，
  /// 按需插件待页面/命令触发时激活）
  Future<bool> _installDartPlugin(StorePluginEntry entry) async {
    final pm = PluginManager.instance;
    final dartId = entry.dartPluginId ?? entry.id;

    final desc = pm.byId(dartId);
    if (desc == null) return false;

    if (!desc.isInstalled) {
      await pm.installPlugin(dartId);
    }
    if (!pm.isEnabled(dartId)) {
      await pm.enablePlugin(dartId);
    }

    notifyListeners();
    return true;
  }

  /// Install a native plugin — download zip and extract
  Future<bool> _installNativePlugin(StorePluginEntry entry) async {
    if (entry.downloadUrl == null) return false;
    return installFromZipUrl(entry.downloadUrl!);
  }

  /// 从 GitHub 链接直接导入安装插件。
  /// 支持：zip 直链 / 插件仓库 / Release 页面。
  /// 返回 null = 成功；否则为错误消息。
  Future<String?> installFromGithubUrl(String url) async {
    final resolution = await GithubUrlResolver.resolve(url);
    if (resolution == null) {
      return '无法识别该链接：不是 GitHub 仓库、插件包或 Release 地址';
    }
    if (resolution is GithubIndexResolution) {
      return '这是一个插件源（索引）链接，请使用「添加源」加入商店';
    }
    final zip = resolution as GithubZipResolution;
    final ok = await installFromZipUrl(zip.zipUrl);
    if (ok) {
      await PluginManager.instance.discoverExternalPlugins();
      notifyListeners();
      return null;
    }
    return '插件包下载或安装失败';
  }

  /// 下载 zip 并安装
  Future<bool> installFromZipUrl(String zipUrl) async {
    try {
      final response = await http.get(Uri.parse(zipUrl), headers: ghHeaders)
          .timeout(const Duration(seconds: 120));
      if (response.statusCode != 200) return false;

      // Save to temp file
      final tempDir = await AppPaths.getTempDir();
      final zipName = zipUrl.split('/').last;
      final zipPath = '$tempDir${Platform.pathSeparator}import_${DateTime.now().millisecondsSinceEpoch}_$zipName';
      await File(zipPath).writeAsBytes(response.bodyBytes);

      // Install from zip
      final success = await PluginManager.instance.installFromZip(zipPath);

      // Cleanup temp file
      try { await File(zipPath).delete(); } catch (_) {}

      notifyListeners();
      return success;
    } catch (_) {
      return false;
    }
  }

  /// Uninstall a plugin
  Future<void> uninstallPlugin(StorePluginEntry entry) async {
    final dartId = entry.dartPluginId ?? entry.id;
    await PluginManager.instance.uninstallPlugin(dartId);
    notifyListeners();
  }

  /// Compare version strings (returns >0 if a > b)
  int _compareVersions(String a, String b) {
    final partsA = a.split('.').map(int.parse).toList();
    final partsB = b.split('.').map(int.parse).toList();
    for (var i = 0; i < partsA.length && i < partsB.length; i++) {
      if (partsA[i] != partsB[i]) return partsA[i] - partsB[i];
    }
    return partsA.length - partsB.length;
  }
}
