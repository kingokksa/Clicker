/// Plugin registry — manages both built-in Dart plugins and external native plugins.
/// Handles registration, installation, enabling/disabling, and persistence.
library;

import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'plugin_system.dart';
import 'native_plugin_loader.dart';
import 'app_paths.dart';

class PluginRegistry extends ChangeNotifier {
  PluginRegistry._();
  static final PluginRegistry instance = PluginRegistry._();

  final Map<String, ClickerPlugin> _plugins = {};
  final Set<String> _enabledIds = {};
  final Set<String> _installedIds = {};

  /// All registered plugins (including not-installed ones)
  List<ClickerPlugin> get plugins => _plugins.values.toList();

  /// Installed plugins
  List<ClickerPlugin> get installedPlugins =>
      _plugins.values.where((p) => p.installed).toList();

  /// Enabled plugins (installed + enabled — these show in nav)
  List<ClickerPlugin> get enabledPlugins =>
      _plugins.values.where((p) => p.enabled).toList();

  /// External (native) plugins only
  List<ClickerPlugin> get externalPlugins =>
      _plugins.values.where((p) => p.manifest.source != PluginSource.builtin).toList();

  /// Get plugin by id
  ClickerPlugin? getPlugin(String id) => _plugins[id];

  /// Register a built-in Dart plugin
  void registerPlugin(ClickerPlugin plugin) {
    final id = plugin.manifest.id;
    _plugins[id] = plugin;
    plugin.onStateChanged = () => notifyListeners();
    // Don't auto-install; user installs from the store
    notifyListeners();
  }

  /// Discover and register external native plugins from the plugins directory
  Future<void> discoverExternalPlugins() async {
    try {
      final manifests = await PluginDirManager.discoverPlugins();
      for (final manifest in manifests) {
        if (_plugins.containsKey(manifest.id)) continue; // Already registered

        final pluginDir = await PluginDirManager.getPluginDir(manifest.id);
        if (pluginDir == null) continue;

        final nativePlugin = LoadedNativePlugin(
          manifest: manifest,
          pluginDir: pluginDir,
        );
        final wrapper = NativeClickerPlugin(nativePlugin);
        wrapper.initManifest();
        _plugins[manifest.id] = wrapper;
        wrapper.onStateChanged = () => notifyListeners();

        // Mark as installed if it was previously installed
        if (_installedIds.contains(manifest.id)) {
          wrapper.installed = true;
        }
      }
      notifyListeners();
    } catch (_) {}
  }

  /// Install an external plugin from a zip file
  Future<bool> installFromZip(String zipPath) async {
    try {
      final manifest = await PluginDirManager.installFromZip(zipPath);
      if (manifest == null) return false;
      return await _registerExternalPlugin(manifest);
    } catch (_) {
      return false;
    }
  }

  /// Install an external plugin from a directory
  Future<bool> installFromDirectory(String sourceDir) async {
    try {
      final manifest = await PluginDirManager.installFromDirectory(sourceDir);
      if (manifest == null) return false;
      return await _registerExternalPlugin(manifest);
    } catch (_) {
      return false;
    }
  }

  Future<bool> _registerExternalPlugin(PluginManifest manifest) async {
    final pluginDir = await PluginDirManager.getPluginDir(manifest.id);
    if (pluginDir == null) return false;

    final nativePlugin = LoadedNativePlugin(manifest: manifest, pluginDir: pluginDir);
    final wrapper = NativeClickerPlugin(nativePlugin);
    wrapper.initManifest();
    _plugins[manifest.id] = wrapper;
    wrapper.onStateChanged = () => notifyListeners();

    await installPlugin(manifest.id);
    return true;
  }

  /// Install a plugin
  Future<void> installPlugin(String id) async {
    final plugin = _plugins[id];
    if (plugin == null || plugin.installed) return;
    _installedIds.add(id);
    plugin.installed = true;
    saveState();
    notifyListeners();
  }

  /// Uninstall a plugin
  Future<void> uninstallPlugin(String id) async {
    final plugin = _plugins[id];
    if (plugin == null || !plugin.installed) return;
    if (plugin.enabled) await disablePlugin(id);
    await plugin.dispose();
    await plugin.onUninstall();

    _installedIds.remove(id);
    plugin.installed = false;

    if (plugin.manifest.source != PluginSource.builtin) {
      await PluginDirManager.uninstall(id);
      _plugins.remove(id);
    }

    saveState();
    notifyListeners();
  }

  /// Enable a plugin (must be installed first)
  Future<void> enablePlugin(String id) async {
    final plugin = _plugins[id];
    if (plugin == null || !plugin.installed || plugin.enabled) return;
    _enabledIds.add(id);
    plugin.enabled = true;
    await plugin.initialize();
    saveState();
    notifyListeners();
  }

  /// Disable a plugin
  Future<void> disablePlugin(String id) async {
    final plugin = _plugins[id];
    if (plugin == null || !plugin.enabled) return;
    plugin.enabled = false;
    _enabledIds.remove(id);
    await plugin.dispose();
    saveState();
    notifyListeners();
  }

  /// Toggle plugin enabled state
  Future<void> togglePlugin(String id) async {
    final plugin = _plugins[id];
    if (plugin == null) return;
    if (plugin.enabled) {
      await disablePlugin(id);
    } else {
      if (!plugin.installed) await installPlugin(id);
      await enablePlugin(id);
    }
  }

  /// Load persisted state
  Future<void> loadState() async {
    try {
      final dir = await _getPluginDir();
      final file = File('${dir.path}${Platform.pathSeparator}plugin_state.json');
      if (await file.exists()) {
        final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        final installed = (json['installed'] as List?)?.cast<String>() ?? [];
        final enabled = (json['enabled'] as List?)?.cast<String>() ?? [];
        _installedIds.clear();
        _enabledIds.clear();
        _installedIds.addAll(installed);
        _enabledIds.addAll(enabled);
      } else {
        // First run — save empty state
        await saveState();
      }
    } catch (_) {
      // First run or corrupt state — save empty state
      await saveState();
    }

    // Apply state to registered plugins
    for (final plugin in _plugins.values) {
      final id = plugin.manifest.id;
      // Built-in Dart plugins: code is compiled in, but start
      // as "not installed" until user installs from the store.
      plugin.installed = _installedIds.contains(id);
      plugin.enabled = _enabledIds.contains(id);
      if (plugin.enabled && plugin.installed) {
        await plugin.initialize();
      }
    }

    // Discover external plugins
    await discoverExternalPlugins();

    notifyListeners();
  }

  /// Save state to disk
  Future<void> saveState() async {
    try {
      final dir = await _getPluginDir();
      final file = File('${dir.path}${Platform.pathSeparator}plugin_state.json');
      await file.writeAsString(jsonEncode({
        'installed': _installedIds.toList(),
        'enabled': _enabledIds.toList(),
      }));
    } catch (_) {}
  }

  Future<Directory> _getPluginDir() async {
    final path = await AppPaths.getDataDir();
    return Directory(path);
  }

  /// Open the plugins directory in file explorer
  Future<void> openPluginsDir() async {
    final dir = await PluginDirManager.getPluginsDir();
    if (Platform.isWindows) {
      await Process.run('explorer', [dir.path]);
    } else if (Platform.isLinux) {
      await Process.run('xdg-open', [dir.path]);
    } else if (Platform.isMacOS) {
      await Process.run('open', [dir.path]);
    }
  }
}
