
import 'dart:io' show Platform;

import 'vision_plugin.dart';
import 'plugins/template_match_plugin.dart';
import 'plugins/windows_ocr_plugin.dart';
import 'plugins/android_ocr_plugin.dart';
import 'plugins/yolo_detect_plugin.dart';
import 'plugins/rapid_ocr_plugin.dart';

class VisionPluginManager {
  final Map<String, VisionPlugin> _plugins = {};
  final Map<String, bool> _initialized = {};
  bool _disposed = false;

  List<VisionPlugin> get plugins => _plugins.values.toList();

  VisionPlugin? getPlugin(String id) => _plugins[id];

  List<VisionPlugin> getPluginsWithCapability(VisionCapability cap) {
    return _plugins.values
        .where((p) => p.info.capabilities.contains(cap) && p.enabled)
        .toList();
  }

  VisionPlugin? getPluginForCapability(VisionCapability cap) {
    final preferred = _preferredId == null ? null : _plugins[_preferredId!];
    if (preferred != null &&
        preferred.enabled &&
        preferred.isAvailable &&
        preferred.info.capabilities.contains(cap)) {
      return preferred;
    }
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
    return externalAvailable ?? builtinAvailable ?? external ?? builtin;
  }

  String? _preferredId;

  String? get preferredId => _preferredId;

  void setPreferred(String? id) {
    _preferredId = id;
  }

  bool _builtinRegistered = false;

  Future<void> registerPlugin(VisionPlugin plugin) async {
    if (_disposed) return;
    if (_plugins.containsKey(plugin.info.id)) return;
    _plugins[plugin.info.id] = plugin;
  }

  Future<void> unregisterPlugin(String id) async {
    final plugin = _plugins.remove(id);
    if (plugin != null) {
      await plugin.dispose();
      _initialized.remove(id);
    }
  }

  Future<bool> ensureInitialized(String id) async {
    if (_disposed) return false;
    final plugin = _plugins[id];
    if (plugin == null) return false;
    if (_initialized[id] == true) return true;
    final ok = await plugin.initialize();
    _initialized[id] = ok;
    return ok;
  }

  void resetInitialized(String id) {
    _initialized.remove(id);
  }

  Future<void> initializeAll() async {
    for (final id in _plugins.keys) {
      await ensureInitialized(id);
    }
  }

  void setPluginEnabled(String id, bool enabled) {
    final plugin = _plugins[id];
    if (plugin != null) {
      plugin.enabled = enabled;
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    for (final plugin in _plugins.values) {
      await plugin.dispose();
    }
    _plugins.clear();
    _initialized.clear();
  }


  static VisionPluginManager? _instance;

  static VisionPluginManager get instance {
    _instance ??= VisionPluginManager._create();
    return _instance!;
  }

  VisionPluginManager._create();

  static Future<void> registerBuiltinPlugins() async {
    final mgr = instance;
    if (mgr._builtinRegistered) return;
    mgr._builtinRegistered = true;
    await mgr.registerPlugin(TemplateMatchPlugin());
    if (Platform.isWindows) {
      await mgr.registerPlugin(WindowsOcrPlugin());
      await mgr.registerPlugin(RapidOcrPlugin());
    }
    if (Platform.isWindows || Platform.isLinux) {
      await mgr.registerPlugin(YoloDetectPlugin());
    }
    if (Platform.isAndroid) {
      await mgr.registerPlugin(AndroidOcrPlugin());
    }
  }
}
