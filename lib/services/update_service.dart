
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:archive/archive.dart';
import 'package:window_manager/window_manager.dart';
import 'app_paths.dart';

class UpdateService extends ChangeNotifier {
  static final UpdateService instance = UpdateService._();
  UpdateService._();

  static const _owner = 'kingokksa';
  static const _repo = 'Clicker';
  static const _releasesUrl = 'https://api.github.com/repos/$_owner/$_repo/releases/latest';

  String _currentVersion = '';
  String _latestVersion = '';
  String _downloadUrl = '';
  String _releaseNotes = '';
  bool _checking = false;
  bool _downloading = false;
  double _downloadProgress = 0;
  String _updateError = '';
  bool _updateAvailable = false;

  String get currentVersion => _currentVersion;
  String get latestVersion => _latestVersion;
  String get releaseNotes => _releaseNotes;
  bool get checking => _checking;
  bool get downloading => _downloading;
  double get downloadProgress => _downloadProgress;
  String get updateError => _updateError;
  bool get updateAvailable => _updateAvailable;

  void setCurrentVersion(String version) {
    _currentVersion = version.replaceAll('+', '-build-');
  }

  Future<void> checkForUpdates() async {
    if (_checking) return;
    _checking = true;
    _updateError = '';
    notifyListeners();

    try {
      final response = await http.get(
        Uri.parse(_releasesUrl),
        headers: {'Accept': 'application/vnd.github+json'},
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        _updateError = '无法连接到更新服务器 (${response.statusCode})';
        _checking = false;
        notifyListeners();
        return;
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      _latestVersion = (json['tag_name'] as String?)?.replaceFirst(RegExp(r'^v'), '') ?? '';
      _releaseNotes = (json['body'] as String?) ?? '';

      final assets = json['assets'] as List<dynamic>? ?? [];
      String? zipUrl;
      for (final asset in assets) {
        final name = (asset['name'] as String?)?.toLowerCase() ?? '';
        if (name.endsWith('.zip') && (name.contains('win') || name.contains('windows'))) {
          zipUrl = asset['browser_download_url'] as String?;
          break;
        }
      }
      if (zipUrl == null) {
        for (final asset in assets) {
          final name = (asset['name'] as String?) ?? '';
          if (name.endsWith('.zip')) {
            zipUrl = asset['browser_download_url'] as String?;
            break;
          }
        }
      }
      _downloadUrl = zipUrl ?? '';

      _updateAvailable = _latestVersion.isNotEmpty &&
          _compareVersions(_latestVersion, _currentVersion) > 0;

      if (_downloadUrl.isEmpty && _updateAvailable) {
        _updateError = '未找到 Windows 更新包';
      }
    } catch (e) {
      _updateError = '检查更新失败: $e';
    }

    _checking = false;
    notifyListeners();
  }

  Future<bool> downloadAndInstall() async {
    if (_downloading || _downloadUrl.isEmpty) return false;
    _downloading = true;
    _downloadProgress = 0;
    _updateError = '';
    notifyListeners();

    try {
      final appDir = await AppPaths.getAppDir();
      final tempDir = await AppPaths.getTempDir();
      final zipPath = '$tempDir${Platform.pathSeparator}update.zip';
      final extractDir = '$tempDir${Platform.pathSeparator}update_extract';

      final request = http.Request('GET', Uri.parse(_downloadUrl));
      final response = await request.send();
      if (response.statusCode != 200) {
        _updateError = '下载失败 (${response.statusCode})';
        _downloading = false;
        notifyListeners();
        return false;
      }

      final contentLength = response.contentLength ?? 0;
      int downloaded = 0;
      final sink = File(zipPath).openWrite();

      await for (final chunk in response.stream) {
        sink.add(chunk);
        downloaded += chunk.length;
        if (contentLength > 0) {
          _downloadProgress = downloaded / contentLength;
        }
        notifyListeners();
      }
      await sink.close();

      _downloadProgress = 1.0;
      notifyListeners();

      final extractDirObj = Directory(extractDir);
      if (await extractDirObj.exists()) {
        await extractDirObj.delete(recursive: true);
      }
      await extractDirObj.create(recursive: true);

      final bytes = await File(zipPath).readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);
      for (final file in archive) {
        final filePath = '$extractDir${Platform.pathSeparator}${file.name}';
        if (file.isFile) {
          await File(filePath).create(recursive: true);
          await File(filePath).writeAsBytes(file.content as List<int>);
        } else {
          await Directory(filePath).create(recursive: true);
        }
      }

      String sourceDir = extractDir;
      final topItems = Directory(extractDir).listSync();
      if (topItems.length == 1 && topItems.first is Directory) {
        sourceDir = topItems.first.path;
      }

      final scriptPath = '$tempDir${Platform.pathSeparator}apply_update.bat';
      final exeName = Platform.resolvedExecutable.split(Platform.pathSeparator).last;
      final exePath = '$appDir\\$exeName';

      final script = '''@echo off
chcp 65001 >nul
echo Applying update...

:: Wait for the app to fully exit (up to 30 seconds)
set WAITED=0
:waitloop
tasklist /fi "imagename eq $exeName" 2>nul | find "$exeName" >nul
if not errorlevel 1 (
  set /a WAITED+=1
  if %WAITED% GEQ 30 (
    echo App did not exit in time, forcing...
    taskkill /f /im "$exeName" >nul 2>&1
    timeout /t 2 /nobreak >nul
    goto copyfiles
  )
  timeout /t 1 /nobreak >nul
  goto waitloop
)

:copyfiles
echo Copying files...
xcopy "$sourceDir\\*" "$appDir\\" /e /y /q

echo Cleaning up...
rd /s /q "$extractDir" 2>nul
del "$zipPath" 2>nul

echo Starting application...
start "" "$exePath"

:: Schedule self-delete in a detached window so the updater console exits
:: immediately. Doing it synchronously would block this batch (keeping the
:: updater window alive for 2s) AND deleting the running .bat would make
:: cmd fail with "The batch file cannot be found." when reading the next line.
start "" /min cmd /c "timeout /t 2 /nobreak >nul & del \"%~f0\""
exit /b
''';
      await File(scriptPath).writeAsString(script);

      try {
        await windowManager.close();
      } catch (_) {
      }

      await Future.delayed(const Duration(milliseconds: 500));

      await Process.start(
        'cmd',
        ['/c', 'start', '/min', '', scriptPath],
        mode: ProcessStartMode.detached,
        runInShell: true,
      );

      exit(0);
    } catch (e) {
      _updateError = '更新失败: $e';
      _downloading = false;
      notifyListeners();
      return false;
    }
  }

  int _compareVersions(String a, String b) {
    final partsA = a.split(RegExp(r'[.\-]')).where((s) => s.isNotEmpty).toList();
    final partsB = b.split(RegExp(r'[.\-]')).where((s) => s.isNotEmpty).toList();
    for (var i = 0; i < partsA.length && i < partsB.length; i++) {
      final numA = int.tryParse(partsA[i]) ?? 0;
      final numB = int.tryParse(partsB[i]) ?? 0;
      if (numA != numB) return numA - numB;
    }
    return partsA.length - partsB.length;
  }
}
