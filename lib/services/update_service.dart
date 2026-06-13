/// Update service — checks GitHub releases for new versions,
/// downloads and applies updates with restart.
library;

import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:archive/archive.dart';
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

  /// Check GitHub for the latest release
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

      // Find Windows zip asset
      final assets = json['assets'] as List<dynamic>? ?? [];
      String? zipUrl;
      for (final asset in assets) {
        final name = (asset['name'] as String?)?.toLowerCase() ?? '';
        if (name.endsWith('.zip') && (name.contains('win') || name.contains('windows'))) {
          zipUrl = asset['browser_download_url'] as String?;
          break;
        }
      }
      // Fallback: any zip
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

  /// Download and apply the update, then restart
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

      // Download with progress
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

      // Extract zip
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

      // Find the actual content directory (might be nested)
      String sourceDir = extractDir;
      final topItems = Directory(extractDir).listSync();
      if (topItems.length == 1 && topItems.first is Directory) {
        sourceDir = topItems.first.path;
      }

      // Create update script that copies files and restarts
      final scriptPath = '$tempDir${Platform.pathSeparator}apply_update.ps1';
      final exeName = Platform.resolvedExecutable.split(Platform.pathSeparator).last;
      final script = '''
\$sourceDir = "$sourceDir"
\$appDir = "$appDir"
\$exeName = "$exeName"

# Wait for the app to exit
Start-Sleep -Seconds 2

# Copy files, excluding data directory
Get-ChildItem -Path \$sourceDir -Recurse | Where-Object {
  \$_.FullName -notlike "*\\data\\*"
} | ForEach-Object {
  \$dest = \$_.FullName.Replace(\$sourceDir, \$appDir)
  if (\$_.PSIsContainer) {
    if (-not (Test-Path \$dest)) { New-Item -ItemType Directory -Path \$dest -Force | Out-Null }
  } else {
    Copy-Item -Path \$_.FullName -Destination \$dest -Force
  }
}

# Cleanup
Remove-Item -Path "$extractDir" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path "$zipPath" -Force -ErrorAction SilentlyContinue

# Restart the app
Start-Process -FilePath "\$appDir\\\$exeName"
Remove-Item -Path "$scriptPath" -Force -ErrorAction SilentlyContinue
''';
      await File(scriptPath).writeAsString(script);

      // Launch the update script and exit
      final process = await Process.start(
        'powershell',
        ['-WindowStyle', 'Hidden', '-ExecutionPolicy', 'Bypass', '-File', scriptPath],
        runInShell: true,
      );
      // Don't await - let it run independently
      process.stdout.drain();
      process.stderr.drain();

      // Exit the app
      _downloading = false;
      notifyListeners();
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
