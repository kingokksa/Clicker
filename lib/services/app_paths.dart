library;

import 'dart:io';

class AppPaths {
  AppPaths._();

  static String? _appDir;

  static String get sep => Platform.pathSeparator;

  static Future<String> getAppDir() async {
    if (_appDir != null) return _appDir!;
    if (Platform.isAndroid) {
      _appDir = '/data/data/com.clicker.app';
      return _appDir!;
    }
    final exePath = Platform.resolvedExecutable;
    _appDir = File(exePath).parent.path;
    return _appDir!;
  }

  static Future<String> getDataDir() async {
    final appDir = await getAppDir();
    final dir = Directory('$appDir${sep}data');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir.path;
  }

  static Future<String> getMacrosDir() async {
    final dataDir = await getDataDir();
    final dir = Directory('$dataDir${sep}macros');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir.path;
  }

  static Future<String> getPluginsDir() async {
    final dataDir = await getDataDir();
    final dir = Directory('$dataDir${sep}plugins');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir.path;
  }

  static Future<String> getScreenshotsDir() async {
    final dataDir = await getDataDir();
    final dir = Directory('$dataDir${sep}screenshots');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir.path;
  }

  static Future<String> getTempDir() async {
    final dataDir = await getDataDir();
    final dir = Directory('$dataDir${sep}temp');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir.path;
  }

  static Future<String> getPluginDir(String pluginId) async {
    final pluginsDir = await getPluginsDir();
    final dir = Directory('$pluginsDir${sep}$pluginId');
    return dir.path;
  }
}
