/// Persistent storage service using shared_preferences.
/// Handles app config, profiles, macros, and import/export.
library;

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import '../models/clicker_config.dart';
import '../models/hotkey_config.dart';
import '../models/macro_model.dart';

class StorageService {
  static const _keyClicker = 'clicker_config';
  static const _keyHotkeys = 'hotkey_config';
  static const _keyTheme = 'theme_mode';
  static const _keyAlwaysOnTop = 'always_on_top';
  static const _keyMinimizeToTray = 'minimize_to_tray';
  static const _keyFloatingAlwaysOnTop = 'floating_always_on_top';
  static const _keyAccentColor = 'accent_color';
  static const _keyProfiles = 'profiles';
  static const _keyMacroList = 'macro_list';

  late SharedPreferences _prefs;
  late String _macrosDir;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    final appDir = await getApplicationDocumentsDirectory();
    _macrosDir = '${appDir.path}/macros';
    await Directory(_macrosDir).create(recursive: true);
  }

  // ─── Clicker Config ───────────────────────────────────────

  ClickerConfig loadClickerConfig() {
    final json = _prefs.getString(_keyClicker);
    if (json != null) {
      return ClickerConfig.fromJson(jsonDecode(json));
    }
    return ClickerConfig();
  }

  Future<void> saveClickerConfig(ClickerConfig config) async {
    await _prefs.setString(_keyClicker, jsonEncode(config.toJson()));
  }

  // ─── Hotkey Config ────────────────────────────────────────

  HotkeyConfig loadHotkeyConfig() {
    final json = _prefs.getString(_keyHotkeys);
    if (json != null) {
      return HotkeyConfig.fromJson(jsonDecode(json));
    }
    return HotkeyConfig();
  }

  Future<void> saveHotkeyConfig(HotkeyConfig config) async {
    await _prefs.setString(_keyHotkeys, jsonEncode(config.toJson()));
  }

  // ─── Theme ────────────────────────────────────────────────

  String get themeMode => _prefs.getString(_keyTheme) ?? 'dark';

  Future<void> setThemeMode(String mode) async {
    await _prefs.setString(_keyTheme, mode);
  }

  // ─── Always On Top ────────────────────────────────────────

  bool get alwaysOnTop => _prefs.getBool(_keyAlwaysOnTop) ?? true;

  Future<void> setAlwaysOnTop(bool value) async {
    await _prefs.setBool(_keyAlwaysOnTop, value);
  }

  // ─── Minimize To Tray ─────────────────────────────────────

  bool get minimizeToTray => _prefs.getBool(_keyMinimizeToTray) ?? false;

  bool get hasAskedMinimizeToTray => _prefs.getBool('hasAskedMinimizeToTray') ?? false;

  Future<void> setMinimizeToTray(bool value) async {
    await _prefs.setBool(_keyMinimizeToTray, value);
    await _prefs.setBool('hasAskedMinimizeToTray', true);
  }

  // ─── Floating Always On Top ───────────────────────────────

  bool get floatingAlwaysOnTop => _prefs.getBool(_keyFloatingAlwaysOnTop) ?? true;

  Future<void> setFloatingAlwaysOnTop(bool value) async {
    await _prefs.setBool(_keyFloatingAlwaysOnTop, value);
  }

  // ─── Accent Color ─────────────────────────────────────────

  int get accentColorValue => _prefs.getInt(_keyAccentColor) ?? 0xFF7C4DFF;

  Future<void> setAccentColorValue(int value) async {
    await _prefs.setInt(_keyAccentColor, value);
  }

  // ─── Profiles ─────────────────────────────────────────────

  List<String> listProfiles() {
    final json = _prefs.getString(_keyProfiles);
    if (json != null) {
      return List<String>.from(jsonDecode(json));
    }
    return [];
  }

  Future<void> saveProfile(String name, ClickerConfig config) async {
    final profiles = listProfiles().toList();
    if (!profiles.contains(name)) {
      profiles.add(name);
      await _prefs.setString(_keyProfiles, jsonEncode(profiles));
    }
    await _prefs.setString('profile_$name', jsonEncode(config.toJson()));
  }

  ClickerConfig? loadProfile(String name) {
    final json = _prefs.getString('profile_$name');
    if (json != null) {
      return ClickerConfig.fromJson(jsonDecode(json));
    }
    return null;
  }

  Future<void> deleteProfile(String name) async {
    final profiles = listProfiles().toList();
    profiles.remove(name);
    await _prefs.setString(_keyProfiles, jsonEncode(profiles));
    await _prefs.remove('profile_$name');
  }

  // ─── Macros ───────────────────────────────────────────────

  Future<List<String>> listMacroFiles() async {
    final dir = Directory(_macrosDir);
    if (!await dir.exists()) return [];
    return dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.json'))
        .map((f) => f.uri.pathSegments.last)
        .toList();
  }

  Future<void> saveMacro(MacroModel macro) async {
    final file = File('$_macrosDir/${macro.id}.json');
    await file.writeAsString(macro.toJsonString());
  }

  Future<MacroModel?> loadMacro(String id) async {
    final file = File('$_macrosDir/$id.json');
    if (await file.exists()) {
      return MacroModel.fromJsonString(await file.readAsString());
    }
    return null;
  }

  Future<void> deleteMacro(String id) async {
    final file = File('$_macrosDir/$id.json');
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<List<MacroModel>> loadAllMacros() async {
    final files = await listMacroFiles();
    final macros = <MacroModel>[];
    for (final f in files) {
      try {
        final file = File('$_macrosDir/$f');
        macros.add(MacroModel.fromJsonString(await file.readAsString()));
      } catch (_) {}
    }
    macros.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return macros;
  }

  // ─── Import / Export ──────────────────────────────────────

  /// Export all configuration as a JSON string.
  Future<String> exportConfig({
    required ClickerConfig clickerConfig,
    required HotkeyConfig hotkeyConfig,
    required String themeMode,
    required bool alwaysOnTop,
  }) async {
    final macros = await loadAllMacros();
    final data = {
      'version': 1,
      'clickerConfig': clickerConfig.toJson(),
      'hotkeyConfig': hotkeyConfig.toJson(),
      'themeMode': themeMode,
      'alwaysOnTop': alwaysOnTop,
      'macros': macros.map((m) => m.toJson()).toList(),
      'profiles': {
        'list': listProfiles(),
        'data': {
          for (final p in listProfiles())
            p: loadProfile(p)?.toJson(),
        },
      },
    };
    return const JsonEncoder.withIndent('  ').convert(data);
  }

  /// Export config to a file chosen by the user.
  Future<bool> exportConfigToFile({
    required ClickerConfig clickerConfig,
    required HotkeyConfig hotkeyConfig,
    required String themeMode,
    required bool alwaysOnTop,
  }) async {
    try {
      final json = await exportConfig(
        clickerConfig: clickerConfig,
        hotkeyConfig: hotkeyConfig,
        themeMode: themeMode,
        alwaysOnTop: alwaysOnTop,
      );
      final path = await FilePicker.platform.saveFile(
        dialogTitle: '导出配置',
        fileName: 'clicker_config.json',
        type: FileType.custom,
        allowedExtensions: ['json'],
        bytes: utf8.encode(json),
      );
      return path != null;
    } catch (_) {
      return false;
    }
  }

  /// Import configuration from a JSON string.
  Future<ImportResult> importConfig(String jsonStr) async {
    try {
      final data = jsonDecode(jsonStr) as Map<String, dynamic>;
      final clickerConfig = ClickerConfig.fromJson(data['clickerConfig'] as Map<String, dynamic>);
      final hotkeyConfig = HotkeyConfig.fromJson(data['hotkeyConfig'] as Map<String, dynamic>);
      final themeMode = data['themeMode'] as String? ?? 'dark';
      final alwaysOnTop = data['alwaysOnTop'] as bool? ?? true;

      // Save configs
      await saveClickerConfig(clickerConfig);
      await saveHotkeyConfig(hotkeyConfig);
      await setThemeMode(themeMode);
      await setAlwaysOnTop(alwaysOnTop);

      // Import macros
      if (data['macros'] != null) {
        for (final m in data['macros'] as List) {
          final macro = MacroModel.fromJson(m as Map<String, dynamic>);
          await saveMacro(macro);
        }
      }

      // Import profiles
      if (data['profiles'] != null) {
        final profData = data['profiles'] as Map<String, dynamic>;
        final profList = List<String>.from(profData['list'] ?? []);
        for (final p in profList) {
          final pData = (profData['data'] as Map<String, dynamic>?)?[p];
          if (pData != null) {
            await saveProfile(p, ClickerConfig.fromJson(pData as Map<String, dynamic>));
          }
        }
      }

      return ImportResult(
        success: true,
        clickerConfig: clickerConfig,
        hotkeyConfig: hotkeyConfig,
        themeMode: themeMode,
        alwaysOnTop: alwaysOnTop,
      );
    } catch (e) {
      return ImportResult(success: false, error: e.toString());
    }
  }

  /// Import config from a file chosen by the user.
  Future<ImportResult> importConfigFromFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        dialogTitle: '导入配置',
        type: FileType.custom,
        allowedExtensions: ['json'],
        allowMultiple: false,
      );
      if (result == null || result.files.isEmpty) {
        return const ImportResult(success: false, error: '未选择文件');
      }
      final file = File(result.files.single.path!);
      final jsonStr = await file.readAsString();
      return importConfig(jsonStr);
    } catch (e) {
      return ImportResult(success: false, error: e.toString());
    }
  }
}

/// Result of a config import operation.
class ImportResult {
  final bool success;
  final String? error;
  final ClickerConfig? clickerConfig;
  final HotkeyConfig? hotkeyConfig;
  final String? themeMode;
  final bool? alwaysOnTop;

  const ImportResult({
    required this.success,
    this.error,
    this.clickerConfig,
    this.hotkeyConfig,
    this.themeMode,
    this.alwaysOnTop,
  });
}
