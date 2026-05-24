/// Plugin API — abstract interfaces for extending Clicker.
///
/// Third-party code can implement these interfaces to add
/// custom functionality without modifying core source.
library;

import 'package:flutter/widgets.dart';
import '../models/clicker_config.dart';

/// Metadata describing a plugin.
class PluginInfo {
  final String id;
  final String name;
  final String version;
  final String author;
  final String description;

  const PluginInfo({
    required this.id,
    required this.name,
    required this.version,
    this.author = '',
    this.description = '',
  });
}

/// Base class for all Clicker plugins.
///
/// Override lifecycle hooks and register capabilities as needed.
abstract class ClickerPlugin {
  /// Unique metadata for this plugin.
  PluginInfo get info;

  /// Called once when the plugin is loaded.
  Future<void> onLoad(PluginContext context) async {}

  /// Called when the application is shutting down.
  Future<void> onUnload() async {}

  /// Optional: provide a settings widget shown in the settings page.
  Widget? buildSettingsPane() => null;

  /// Optional: provide a sidebar action widget (shown above footer items).
  Widget? buildSidebarAction() => null;
}

/// Runtime context passed to plugins for interacting with the app.
class PluginContext {
  /// Read the current clicker configuration.
  final ClickerConfig Function() getClickerConfig;

  /// Update the clicker configuration.
  final void Function(ClickerConfig) setClickerConfig;

  /// Post a snackbar message to the UI.
  final void Function(String) showMessage;

  /// Request the app to start/stop clicking.
  final void Function() toggleClicker;

  const PluginContext({
    required this.getClickerConfig,
    required this.setClickerConfig,
    required this.showMessage,
    required this.toggleClicker,
  });
}

/// Registry that holds loaded plugins.
class PluginRegistry {
  PluginRegistry._();
  static final PluginRegistry instance = PluginRegistry._();

  final List<ClickerPlugin> _plugins = [];

  /// All loaded plugins (read-only).
  List<ClickerPlugin> get plugins => List.unmodifiable(_plugins);

  /// Register a plugin.
  Future<void> register(ClickerPlugin plugin, PluginContext context) async {
    _plugins.add(plugin);
    await plugin.onLoad(context);
  }

  /// Unregister and unload a plugin by id.
  Future<void> unregister(String id) async {
    final idx = _plugins.indexWhere((p) => p.info.id == id);
    if (idx >= 0) {
      await _plugins[idx].onUnload();
      _plugins.removeAt(idx);
    }
  }

  /// Unload all plugins.
  Future<void> unloadAll() async {
    for (final p in _plugins) {
      await p.onUnload();
    }
    _plugins.clear();
  }
}
