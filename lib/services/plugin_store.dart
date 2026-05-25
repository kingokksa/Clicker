/// Plugin store — fetches remote plugin index from GitHub,
/// downloads and installs native plugins, enables Dart plugins.
library;

import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'plugin_system.dart';
import 'plugin_registry.dart';
import 'native_plugin_loader.dart';

/// Remote plugin entry from the store index
class StorePluginEntry {
  final String id;
  final String name;
  final String version;
  final String author;
  final String description;
  final String category;
  final List<String> platforms;
  final String type;        // "dart" or "native"
  final String? dartPluginId; // For dart plugins: the id used by PluginRegistry
  final String? icon;
  final int size;           // Download size in bytes (0 for dart plugins)
  final String? downloadUrl; // For native plugins: zip download URL
  final int minAppVersion;

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
  });

  factory StorePluginEntry.fromJson(Map<String, dynamic> json) => StorePluginEntry(
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
  );

  /// Whether this plugin supports the current platform
  bool get supportsCurrentPlatform {
    final current = LoadedNativePlugin.currentPlatform;
    return platforms.contains(current);
  }

  /// Whether this plugin is already installed locally
  bool get isInstalled {
    final registry = PluginRegistry.instance;
    final plugin = registry.getPlugin(dartPluginId ?? id);
    return plugin != null && plugin.installed;
  }

  /// Whether this plugin is already enabled
  bool get isEnabled {
    final registry = PluginRegistry.instance;
    final plugin = registry.getPlugin(dartPluginId ?? id);
    return plugin != null && plugin.enabled;
  }
}

/// Plugin store — manages remote plugin index and installation
class PluginStore extends ChangeNotifier {
  PluginStore._();
  static final PluginStore instance = PluginStore._();

  /// Default store index URL (GitHub raw)
  /// Replace with your actual repo URL after pushing
  static const String defaultIndexUrl =
    'https://raw.githubusercontent.com/kingokksa/Clicker/main/plugins/plugin_index.json';

  List<StorePluginEntry> _plugins = [];
  bool _isLoading = false;
  String? _error;
  String _indexUrl = defaultIndexUrl;

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
      final registry = PluginRegistry.instance;
      final plugin = registry.getPlugin(p.dartPluginId ?? p.id);
      if (plugin == null) return false;
      return _compareVersions(p.version, plugin.manifest.version) > 0;
    }).toList();
  }

  /// Set custom index URL
  void setIndexUrl(String url) {
    _indexUrl = url;
  }

  /// Fetch the remote plugin index.
  /// Always loads local bundled index first, then tries remote update.
  Future<void> fetchIndex() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    // 1. Always load local bundled index first (instant, always available)
    await _loadBundledIndex();
    notifyListeners();

    // 2. Try remote update in background
    try {
      final response = await http.get(Uri.parse(_indexUrl)).timeout(
        const Duration(seconds: 10),
      );

      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}');
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final pluginList = (json['plugins'] as List?) ?? [];

      _plugins = pluginList
        .map((p) => StorePluginEntry.fromJson(p as Map<String, dynamic>))
        .where((p) => p.id.isNotEmpty)
        .toList();

      _error = null;
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
        '${exeDir}${Platform.pathSeparator}plugins${Platform.pathSeparator}plugin_index.json',
        'plugins${Platform.pathSeparator}plugin_index.json',
        // When running from project root in dev mode
        '${exeDir}${Platform.pathSeparator}..${Platform.pathSeparator}..${Platform.pathSeparator}..${Platform.pathSeparator}..${Platform.pathSeparator}plugins${Platform.pathSeparator}plugin_index.json',
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

  /// Generate index from currently registered Dart plugins as last resort
  void _generateBundledIndex() {
    final registry = PluginRegistry.instance;
    _plugins = registry.plugins
      .where((p) => p.manifest.source == PluginSource.builtin)
      .map((p) {
        final m = p.manifest;
        return StorePluginEntry(
          id: m.id,
          name: m.name,
          version: m.version,
          author: m.author,
          description: m.description,
          category: m.category.id,
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

  /// Install a Dart plugin — just enable the already-compiled plugin
  Future<bool> _installDartPlugin(StorePluginEntry entry) async {
    final registry = PluginRegistry.instance;
    final dartId = entry.dartPluginId ?? entry.id;
    final plugin = registry.getPlugin(dartId);

    if (plugin == null) return false;

    if (!plugin.installed) {
      await registry.installPlugin(dartId);
    }
    if (!plugin.enabled) {
      await registry.enablePlugin(dartId);
    }

    notifyListeners();
    return true;
  }

  /// Install a native plugin — download zip and extract
  Future<bool> _installNativePlugin(StorePluginEntry entry) async {
    if (entry.downloadUrl == null) return false;

    try {
      // Download the zip
      final response = await http.get(Uri.parse(entry.downloadUrl!)).timeout(
        const Duration(seconds: 60),
      );
      if (response.statusCode != 200) return false;

      // Save to temp file
      final tempDir = await getTemporaryDirectory();
      final zipPath = '${tempDir.path}${Platform.pathSeparator}${entry.id}.zip';
      await File(zipPath).writeAsBytes(response.bodyBytes);

      // Install from zip
      final success = await PluginRegistry.instance.installFromZip(zipPath);

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
    final registry = PluginRegistry.instance;
    final dartId = entry.dartPluginId ?? entry.id;

    if (entry.type == 'dart') {
      // For Dart plugins, uninstall (disable + mark not installed)
      await registry.uninstallPlugin(dartId);
    } else {
      await registry.uninstallPlugin(dartId);
    }

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
