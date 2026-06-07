/// Local JSON file storage — replaces SharedPreferences.
/// All data is stored in {appDir}/data/config.json alongside the executable.
library;

import 'dart:convert';
import 'dart:io';
import 'app_paths.dart';

class LocalStorage {
  LocalStorage._();
  static final LocalStorage instance = LocalStorage._();

  Map<String, dynamic> _data = {};
  String? _filePath;
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    final dataDir = await AppPaths.getDataDir();
    _filePath = '$dataDir${Platform.pathSeparator}config.json';
    final file = File(_filePath!);
    if (await file.exists()) {
      try {
        final content = await file.readAsString();
        _data = jsonDecode(content) as Map<String, dynamic>;
      } catch (_) {
        _data = {};
      }
    }
    _initialized = true;
  }

  Future<void> _save() async {
    if (_filePath == null) return;
    final file = File(_filePath!);
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(_data));
  }

  // ─── Getters ──────────────────────────────────────────────

  String? getString(String key) => _data[key]?.toString();

  bool? getBool(String key) => _data[key] as bool?;

  int? getInt(String key) => _data[key] as int?;

  double? getDouble(String key) => (_data[key] as num?)?.toDouble();

  List<String>? getStringList(String key) {
    final value = _data[key];
    if (value is List) return value.cast<String>();
    return null;
  }

  // ─── Setters ──────────────────────────────────────────────

  Future<void> setString(String key, String value) async {
    _data[key] = value;
    await _save();
  }

  Future<void> setBool(String key, bool value) async {
    _data[key] = value;
    await _save();
  }

  Future<void> setInt(String key, int value) async {
    _data[key] = value;
    await _save();
  }

  Future<void> setDouble(String key, double value) async {
    _data[key] = value;
    await _save();
  }

  Future<void> setStringList(String key, List<String> value) async {
    _data[key] = value;
    await _save();
  }

  Future<void> remove(String key) async {
    _data.remove(key);
    await _save();
  }

  bool containsKey(String key) => _data.containsKey(key);
}
