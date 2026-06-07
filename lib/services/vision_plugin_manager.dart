/// Vision plugin manager — manages registration, discovery, and lifecycle of vision plugins.
/// Plugins are loaded on demand and can be enabled/disabled without affecting others.
library;

import 'dart:io' show Platform;

import 'vision_plugin.dart';
import 'plugins/template_match_plugin.dart';
import 'plugins/windows_ocr_plugin.dart';
import 'plugins/paddle_ocr_plugin.dart';
import 'plugins/android_ocr_plugin.dart';
import 'plugins/yolo_detect_plugin.dart';

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

  /// Get the first plugin with a specific capability (prefers available, but returns registered if none available)
  /// Non-builtin plugins (e.g. PaddleOCR) are preferred over builtin ones
  VisionPlugin? getPluginForCapability(VisionCapability cap) {
    VisionPlugin? builtin;
    VisionPlugin? builtinAvailable;
    VisionPlugin? external;
    VisionPlugin? externalAvailable;
    for (final p in _plugins.values) {
      if (p.info.capabilities.contains(cap) && p.enabled) {
        if (p.info.isBuiltin) {
          if (p.isAvailable) {
            builtinAvailable ??= p;
          }
          builtin ??= p;
        } else {
          if (p.isAvailable) {
            externalAvailable ??= p;
          }
          external ??= p;
        }
      }
    }
    // Prefer available plugins, fall back to registered (can be initialized later)
    return externalAvailable ?? builtinAvailable ?? external ?? builtin;
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

  /// Reset initialization cache for a plugin so it can be re-initialized
  void resetInitialized(String id) {
    _initialized.remove(id);
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
    if (Platform.isWindows) {
      await mgr.registerPlugin(WindowsOcrPlugin());
      // await mgr.registerPlugin(PaddleOcrPlugin()); // 暂时禁用，PaddlePaddle 3.x 与 PaddleOCR 不兼容
    }
    if (Platform.isWindows || Platform.isLinux) {
      await mgr.registerPlugin(YoloDetectPlugin());
    }
    if (Platform.isAndroid) {
      await mgr.registerPlugin(AndroidOcrPlugin());
    }
  }
}
