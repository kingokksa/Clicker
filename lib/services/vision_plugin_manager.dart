/// Vision plugin manager — manages registration, discovery, and lifecycle of vision plugins.
/// Plugins are loaded on demand and can be enabled/disabled without affecting others.
library;

import 'vision_plugin.dart';
import 'plugins/template_match_plugin.dart';
import 'plugins/windows_ocr_plugin.dart';

class VisionPluginManager {
  final Map<String, VisionPlugin> _plugins = {};
  final Map<String, bool> _initialized = {};
  bool _disposed = false;

  /// All registered plugins
  List<VisionPlugin> get plugins => _plugins.values.toList();

  /// Get a plugin by ID
  VisionPlugin? getPlugin(String id) => _plugins[id];

  /// Get all plugins with a specific capability
  List<VisionPlugin> getPluginsWithCapability(VisionCapability cap) {
    return _plugins.values
        .where((p) => p.info.capabilities.contains(cap) && p.enabled)
        .toList();
  }

  /// Get the first available plugin with a specific capability
  VisionPlugin? getPluginForCapability(VisionCapability cap) {
    return _plugins.values
        .where((p) => p.info.capabilities.contains(cap) && p.enabled && p.isAvailable)
        .firstOrNull;
  }

  bool _builtinRegistered = false;

  /// Register a plugin (no-op if already registered with same ID)
  Future<void> registerPlugin(VisionPlugin plugin) async {
    if (_disposed) return;
    if (_plugins.containsKey(plugin.info.id)) return;
    _plugins[plugin.info.id] = plugin;
  }

  /// Unregister and dispose a plugin
  Future<void> unregisterPlugin(String id) async {
    final plugin = _plugins.remove(id);
    if (plugin != null) {
      await plugin.dispose();
      _initialized.remove(id);
    }
  }

  /// Ensure a plugin is initialized before use
  Future<bool> ensureInitialized(String id) async {
    if (_disposed) return false;
    final plugin = _plugins[id];
    if (plugin == null) return false;
    if (_initialized[id] == true) return true;
    final ok = await plugin.initialize();
    _initialized[id] = ok;
    return ok;
  }

  /// Initialize all registered plugins
  Future<void> initializeAll() async {
    for (final id in _plugins.keys) {
      await ensureInitialized(id);
    }
  }

  /// Enable/disable a plugin
  void setPluginEnabled(String id, bool enabled) {
    final plugin = _plugins[id];
    if (plugin != null) {
      plugin.enabled = enabled;
    }
  }

  /// Dispose all plugins
  Future<void> dispose() async {
    _disposed = true;
    for (final plugin in _plugins.values) {
      await plugin.dispose();
    }
    _plugins.clear();
    _initialized.clear();
  }

  // ─── Singleton ────────────────────────────────────────────

  static VisionPluginManager? _instance;

  static VisionPluginManager get instance {
    _instance ??= VisionPluginManager._create();
    return _instance!;
  }

  VisionPluginManager._create();

  /// Register all built-in plugins (safe to call multiple times)
  static Future<void> registerBuiltinPlugins() async {
    final mgr = instance;
    if (mgr._builtinRegistered) return;
    mgr._builtinRegistered = true;
    await mgr.registerPlugin(TemplateMatchPlugin());
    await mgr.registerPlugin(WindowsOcrPlugin());
  }
}
