/// 插件存储 — 每个插件独立的持久化键值存储。
/// 数据写入 <pluginsDir>/<pluginId>/data.json，与其他插件完全隔离。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'plugin_manifest.dart';

class PluginStorage {
  final String pluginId;
  final String filePath;
  Map<String, dynamic> _cache = {};
  bool _loaded = false;

  PluginStorage(this.pluginId, this.filePath);

  factory PluginStorage.forPlugin(String pluginsDir, String pluginId) {
    final sep = Platform.pathSeparator;
    return PluginStorage(
      pluginId,
      '$pluginsDir$sep$pluginId$sep' 'data.json',
    );
  }

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final file = File(filePath);
      if (await file.exists()) {
        final raw = await file.readAsString();
        if (raw.trim().isNotEmpty) {
          final decoded = jsonDecode(raw);
          if (decoded is Map<String, dynamic>) _cache = decoded;
        }
      }
    } catch (_) {
      _cache = {};
    }
  }

  /// 读取值；不存在时返回 [defaultValue]（通常取自设置定义）
  Future<T?> get<T>(String key, {T? defaultValue}) async {
    await _ensureLoaded();
    final value = _cache[key];
    if (value == null) return defaultValue;
    if (value is T) return value;
    // 宽松转换
    if (T == int && value is num) return value.round() as T;
    if (T == double && value is num) return value.toDouble() as T;
    if (T == String && value is! String) return value.toString() as T;
    return defaultValue;
  }

  /// 写入值并持久化
  Future<void> set(String key, Object? value) async {
    await _ensureLoaded();
    _cache[key] = value;
    await _flush();
  }

  /// 批量写入
  Future<void> setAll(Map<String, Object?> values) async {
    await _ensureLoaded();
    _cache.addAll(values);
    await _flush();
  }

  /// 读取全部键值（快照）
  Future<Map<String, dynamic>> all() async {
    await _ensureLoaded();
    return Map<String, dynamic>.from(_cache);
  }

  /// 删除键
  Future<void> remove(String key) async {
    await _ensureLoaded();
    _cache.remove(key);
    await _flush();
  }

  /// 按 manifest 设置定义补齐缺省值
  Future<void> applyDefaults(List<SettingDefinition> defs) async {
    await _ensureLoaded();
    var changed = false;
    for (final def in defs) {
      if (!_cache.containsKey(def.key) && def.defaultValue != null) {
        _cache[def.key] = def.defaultValue;
        changed = true;
      }
    }
    if (changed) await _flush();
  }

  Future<void> _flush() async {
    try {
      final file = File(filePath);
      await file.parent.create(recursive: true);
      await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert(_cache),
        flush: true,
      );
    } catch (_) {}
  }
}

/// 带内存缓存的同步存储 — 供原生插件 C 回调同步读写。
/// 写操作立即更新缓存并异步落盘（防抖）。
class CachedPluginStorage implements PluginStorageLike {
  final PluginStorage _storage;
  Map<String, dynamic> _cache = {};
  Timer? _flushTimer;
  bool _synced = false;

  CachedPluginStorage(this._storage);

  Future<void> load() async {
    _cache = await _storage.all();
    _synced = true;
  }

  @override
  Object? getSync(String key) {
    _ensureSynced();
    return _cache[key];
  }

  @override
  void setSync(String key, Object? value) {
    _ensureSynced();
    _cache[key] = value;
    _flushTimer?.cancel();
    _flushTimer = Timer(const Duration(milliseconds: 500), () {
      _storage.setAll(Map<String, Object?>.from(_cache));
    });
  }

  Map<String, dynamic> get all => Map<String, dynamic>.from(_cache);

  Future<void> dispose() async {
    _flushTimer?.cancel();
    await _storage.setAll(Map<String, Object?>.from(_cache));
  }

  void _ensureSynced() {
    if (_synced) return;
    // 同步路径在 load() 完成后才会被调用；此断言防止误用
    assert(_synced, 'CachedPluginStorage.load() must complete before sync access');
  }
}

/// 同步存储接口（native 回调桥接用）
abstract class PluginStorageLike {
  Object? getSync(String key);
  void setSync(String key, Object? value);
}
