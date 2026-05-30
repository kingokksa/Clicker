library;

import 'dart:io';

class AppPaths {
  AppPaths._();

  static String? _appDir;

  static Future<String> getAppDir() async {
    if (_appDir != null) return _appDir!;
    final exePath = Platform.resolvedExecutable;
    _appDir = File(exePath).parent.path;
    return _appDir!;
  }

  static Future<String> getDataDir() async {
    final appDir = await getAppDir();
    final dir = Directory('$appDir\\data');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir.path;
  }

  static Future<String> getMacrosDir() async {
    final dataDir = await getDataDir();
    final dir = Directory('$dataDir\\macros');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir.path;
  }

  static Future<String> getPluginsDir() async {
    final dataDir = await getDataDir();
    final dir = Directory('$dataDir\\plugins');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir.path;
  }

  static Future<String> getScreenshotsDir() async {
    final dataDir = await getDataDir();
    final dir = Directory('$dataDir\\screenshots');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir.path;
  }

  static Future<String> getTempDir() async {
    final dataDir = await getDataDir();
    final dir = Directory('$dataDir\\temp');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir.path;
  }

  static Future<String> getPluginDir(String pluginId) async {
    final pluginsDir = await getPluginsDir();
    final dir = Directory('$pluginsDir\\$pluginId');
    return dir.path;
  }
}
