
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'app_paths.dart';
import 'plugin/plugin_manager.dart';
import 'plugin/plugin_manifest.dart' show currentPluginPlatform;
import 'plugin/plugin_integrity.dart';
import 'plugin/plugin_sources.dart';

class StorePluginEntry {
  final String id;
  final String name;
  final String version;
  final String author;
  final String description;
  final String category;
  final List<String> platforms;
  final String type;
  final String? dartPluginId;
  final String? icon;
  final int size;
  final String? downloadUrl;
  final int minAppVersion;

  final String? sha256;

  final String? nativeLib;

  final String sourceId;
  final String sourceName;

  const StorePluginEntry({
    required this.id,
    required this.name,
    required this.version,
    this.author = '',
    this.description = '',
    this.category = 'extension',
    this.platforms = const [],
    this.type = 'dart',
    this.dartPluginId,
    this.icon,
    this.size = 0,
    this.downloadUrl,
    this.minAppVersion = 1,
    this.sha256,
    this.nativeLib,
    this.sourceId = 'official',
    this.sourceName = '官方插件',
  });

  factory StorePluginEntry.fromJson(Map<String, dynamic> json,
      {String sourceId = 'official', String sourceName = '官方插件'}) {
    return StorePluginEntry(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      version: json['version'] as String? ?? '1.0.0',
      author: json['author'] as String? ?? '',
      description: json['description'] as String? ?? '',
      category: json['category'] as String? ?? 'extension',
      platforms: (json['platforms'] as List?)?.cast<String>() ?? [],
      type: json['type'] as String? ?? 'dart',
      dartPluginId: json['dartPluginId'] as String?,
      icon: json['icon'] as String?,
      size: json['size'] as int? ?? 0,
      downloadUrl: json['downloadUrl'] as String?,
      minAppVersion: json['minAppVersion'] as int? ?? 1,
      sha256: _normHash(json['sha256'] as String?),
      nativeLib: _entrySha256(json['entry']),
      sourceId: json['sourceId'] as String? ?? sourceId,
      sourceName: json['sourceName'] as String? ?? sourceName,
    );
  }

  String? get expectedSha256 => _resolveHash();

  String? _resolveHash() {
    final direct = _normHash(sha256);
    if (direct != null) return direct;
    return _normHash(nativeLib);
  }

  static String? _normHash(String? raw) {
    final s = raw?.trim().toLowerCase();
    if (s == null || s.isEmpty) return null;
    final cleaned = s.replaceAll(RegExp(r'[^0-9a-f]'), '');
    return cleaned.length == 64 ? cleaned : null;
  }

  static String? _entrySha256(Map<String, dynamic>? entry) {
    if (entry == null) return null;
    final v = entry['sha256'] ?? entry['sha256_windows'] ?? entry['sha256.*'];
    return _normHash(v is String ? v : null);
  }

  bool get supportsCurrentPlatform {
    return platforms.contains(currentPluginPlatform);
  }

  bool get isInstalled {
    final desc = PluginManager.instance.byId(dartPluginId ?? id);
    return desc != null && desc.isInstalled;
  }

  bool get isEnabled {
    final pid = dartPluginId ?? id;
    final pm = PluginManager.instance;
    return pm.isInstalled(pid) && pm.isEnabled(pid);
  }
}

class PluginStore extends ChangeNotifier {
  PluginStore._();
  static final PluginStore instance = PluginStore._();

  List<StorePluginEntry> _plugins = [];
  bool _isLoading = false;
  String? _error;

  List<StorePluginEntry> get plugins => _plugins;
  bool get isLoading => _isLoading;
  String? get error => _error;

  List<StorePluginEntry> get availablePlugins =>
    _plugins.where((p) => !p.isInstalled && p.supportsCurrentPlatform).toList();

  List<StorePluginEntry> get updatablePlugins {
    return _plugins.where((p) {
      if (!p.isInstalled) return false;
      final desc = PluginManager.instance.byId(p.dartPluginId ?? p.id);
      if (desc == null) return false;
      return _compareVersions(p.version, desc.manifest.version) > 0;
    }).toList();
  }

  Future<void> fetchIndex() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    await _loadBundledIndex();
    notifyListeners();

    try {
      await PluginSourceRepository.instance.load();
      final sources =
          PluginSourceRepository.instance.enabledSources.toList();

      final remote = <StorePluginEntry>[];
      var anyOk = false;
      for (final source in sources) {
        final json =
            await PluginSourceRepository.fetchIndexJson(source.indexUrl);
        if (json == null) {
          source.error = '索引无法访问';
          source.pluginCount = 0;
          continue;
        }
        anyOk = true;
        source.error = null;
        final idxName = json['name'] as String?;
        if (idxName != null && idxName.isNotEmpty) source.name = idxName;
        final list = (json['plugins'] as List? ?? []);
        final entries = list
            .map((p) => StorePluginEntry.fromJson(
                  Map<String, dynamic>.from(p as Map),
                  sourceId: source.id,
                  sourceName: source.name,
                ))
            .where((p) => p.id.isNotEmpty)
            .toList();
        source.pluginCount = entries.length;
        remote.addAll(entries);
      }

      if (anyOk && remote.isNotEmpty) {
        final seen = <String>{};
        _plugins = remote.where((p) {
          final key = p.dartPluginId ?? p.id;
          if (seen.contains(key)) return false;
          seen.add(key);
          return true;
        }).toList();
        _error = null;
      } else if (!anyOk && sources.isNotEmpty) {
        _error = '所有远程源均无法访问';
      }
      await PluginSourceRepository.instance.save();
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _loadBundledIndex() async {
    try {
      final exePath = Platform.resolvedExecutable;
      final exeDir = File(exePath).parent.path;
      final candidates = [
        '$exeDir${Platform.pathSeparator}plugins${Platform.pathSeparator}plugin_index.json',
        'plugins${Platform.pathSeparator}plugin_index.json',
        '$exeDir${Platform.pathSeparator}..${Platform.pathSeparator}..${Platform.pathSeparator}..${Platform.pathSeparator}..${Platform.pathSeparator}plugins${Platform.pathSeparator}plugin_index.json',
      ];
      for (final path in candidates) {
        final file = File(path);
        if (await file.exists()) {
          final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
          final pluginList = (json['plugins'] as List?) ?? [];
          _plugins = pluginList
            .map((p) => StorePluginEntry.fromJson(p as Map<String, dynamic>))
            .where((p) => p.id.isNotEmpty)
            .toList();
          return;
        }
      }
      _generateBundledIndex();
    } catch (_) {
      _generateBundledIndex();
    }
  }

  void _generateBundledIndex() {
    _plugins = PluginManager.instance.plugins
      .where((d) => d.isBuiltin)
      .map((d) {
        final m = d.manifest;
        return StorePluginEntry(
          id: m.id,
          name: m.name,
          version: m.version,
          author: m.author,
          description: m.description,
          category: m.category,
          platforms: m.platforms,
          type: 'dart',
          dartPluginId: m.id,
          minAppVersion: 1,
        );
      }).toList();
  }

  Future<bool> installPlugin(StorePluginEntry entry) async {
    if (entry.type == 'dart') {
      return _installDartPlugin(entry);
    } else {
      return _installNativePlugin(entry);
    }
  }

  Future<bool> _installDartPlugin(StorePluginEntry entry) async {
    final pm = PluginManager.instance;
    final dartId = entry.dartPluginId ?? entry.id;

    final desc = pm.byId(dartId);
    if (desc == null) return false;

    if (!desc.isInstalled) {
      await pm.installPlugin(dartId);
    }
    if (!pm.isEnabled(dartId)) {
      await pm.enablePlugin(dartId);
    }

    notifyListeners();
    return true;
  }

  Future<bool> _installNativePlugin(StorePluginEntry entry) async {
    if (entry.downloadUrl == null) return false;
    return installFromZipUrl(entry.downloadUrl!,
      expectedSha256: entry.expectedSha256,
      source: 'store:${entry.sourceId}',
    );
  }

  Future<String?> installFromGithubUrl(String url) async {
    final resolution = await GithubUrlResolver.resolve(url);
    if (resolution == null) {
      return '无法识别该链接：不是 GitHub 仓库、插件包或 Release 地址';
    }
    if (resolution is GithubIndexResolution) {
      return '这是一个插件源（索引）链接，请使用「添加源」加入商店';
    }
    final zip = resolution as GithubZipResolution;
    final ok = await installFromZipUrl(zip.zipUrl,
      source: 'github:url',
    );
    if (ok) {
      await PluginManager.instance.discoverExternalPlugins();
      notifyListeners();
      return null;
    }
    return '插件包下载或安装失败';
  }

  Future<bool> installFromZipUrl(String zipUrl,
      {String? expectedSha256, String source = 'url'}) async {
    String? tempPath;
    try {
      final response = await http.get(Uri.parse(zipUrl), headers: ghHeaders)
          .timeout(const Duration(seconds: 120));
      if (response.statusCode != 200) return false;

      final tempDir = await AppPaths.getTempDir();
      final zipName = zipUrl.split('/').last.replaceAll(RegExp(r'[^\w.\-]+'), '_');
      tempPath =
          '$tempDir${Platform.pathSeparator}import_${DateTime.now().millisecondsSinceEpoch}_$zipName';
      await File(tempPath).writeAsBytes(response.bodyBytes);

      final hash = await PluginIntegrity.instance.sha256FileOrNull(tempPath);
      final want = (expectedSha256 ?? '').toLowerCase();
      if (want.isNotEmpty && want.length == 64 && hash.toLowerCase() != want) {
        _error = 'SHA256 校验失败：来源声明与下载内容不一致，安装已中止';
        notifyListeners();
        return false;
      }

      final success = await PluginManager.instance.installFromZip(tempPath,
        beforeRegister: (manifest) async {
          await PluginIntegrity.instance.recordInstall(
            pluginId: manifest.id,
            version: manifest.version,
            zipSha256: hash,
            source: source,
          );
          return true;
        });

      _error = want.isEmpty ? '已安装，但该来源未声明 SHA256，未能校验完整性' : null;
      notifyListeners();
      return success;
    } catch (e) {
      _error = '插件包下载或安装失败：$e';
      notifyListeners();
      return false;
    } finally {
      if (tempPath != null) {
        try { await File(tempPath).delete(); } catch (_) {}
      }
    }
  }

  Future<void> uninstallPlugin(StorePluginEntry entry) async {
    final dartId = entry.dartPluginId ?? entry.id;
    await PluginManager.instance.uninstallPlugin(dartId);
    notifyListeners();
  }

  int _compareVersions(String a, String b) {
    final partsA = a.split('.').map(int.parse).toList();
    final partsB = b.split('.').map(int.parse).toList();
    for (var i = 0; i < partsA.length && i < partsB.length; i++) {
      if (partsA[i] != partsB[i]) return partsA[i] - partsB[i];
    }
    return partsA.length - partsB.length;
  }
}
