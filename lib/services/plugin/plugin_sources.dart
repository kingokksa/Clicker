
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../app_paths.dart';

const Map<String, String> ghHeaders = {
  'User-Agent': 'Clicker-PluginStore',
};

const List<String> indexCandidates = [
  'plugins/plugin_index.json',
  'plugin_index.json',
  '.clicker/plugin_index.json',
  'index.json',
];


enum PluginSourceType {
  official('official'),
  thirdParty('third_party');

  final String id;
  const PluginSourceType(this.id);

  static PluginSourceType fromString(String? s) =>
      s == 'official' ? PluginSourceType.official : PluginSourceType.thirdParty;
}

class PluginSource {
  final String id;
  String name;
  final String url;
  final String indexUrl;
  final PluginSourceType type;
  bool enabled;
  String? error;
  int pluginCount = 0;

  PluginSource({
    required this.id,
    required this.name,
    required this.url,
    required this.indexUrl,
    required this.type,
    this.enabled = true,
    this.error,
  });

  bool get isOfficial => type == PluginSourceType.official;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'url': url,
        'indexUrl': indexUrl,
        'type': type.id,
        'enabled': enabled,
      };

  factory PluginSource.fromJson(Map<String, dynamic> json) => PluginSource(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '未命名源',
        url: json['url'] as String? ?? '',
        indexUrl: json['indexUrl'] as String? ?? '',
        type: PluginSourceType.fromString(json['type'] as String?),
        enabled: json['enabled'] as bool? ?? true,
      );
}


class GithubIndexResolution {
  final String indexUrl;
  final String suggestedName;
  const GithubIndexResolution(this.indexUrl, this.suggestedName);
}

class GithubZipResolution {
  final String zipUrl;
  final String suggestedName;
  const GithubZipResolution(this.zipUrl, this.suggestedName);
}

class GithubUrlResolver {
  GithubUrlResolver._();

  static Future<Object?> resolve(String input) async {
    final url = input.trim().replaceAll(RegExp(r'/+$'), '');
    if (url.isEmpty) return null;

    if (url.startsWith('https://raw.githubusercontent.com/')) {
      if (url.endsWith('.json')) {
        return GithubIndexResolution(url, _nameFromUrl(url));
      }
      if (url.endsWith('.zip')) {
        return GithubZipResolution(url, _nameFromUrl(url));
      }
      return null;
    }

    final releaseZip = RegExp(
      r'^https?://github\.com/([^/]+)/([^/]+)/releases/download/([^/]+)/([^?#]+\.zip)$',
    ).firstMatch(url);
    if (releaseZip != null) {
      return GithubZipResolution(url, releaseZip.group(4)!);
    }

    final archiveZip = RegExp(
      r'^https?://github\.com/([^/]+)/([^/]+)/archive/refs/heads/([^?#]+\.zip)$',
    ).firstMatch(url);
    if (archiveZip != null) {
      return GithubZipResolution(url, archiveZip.group(3)!);
    }

    final repo = RegExp(
      r'^https?://github\.com/([^/]+)/([^/]+)((/.*)?)$',
    ).firstMatch(url);
    if (repo == null) return null;

    final owner = repo.group(1)!;
    final repoName = repo.group(2)!;
    final path = (repo.group(3) ?? '').replaceAll(RegExp(r'^/|/$'), '');

    if (path == 'releases' || path.startsWith('releases/')) {
      return _resolveLatestRelease(owner, repoName);
    }

    String subDir = '';
    String? explicitBranch;
    if (path.startsWith('tree/')) {
      final m =
          RegExp(r'^tree/([^/]+)(?:/(.+))?$').firstMatch(path);
      if (m != null) {
        explicitBranch = m.group(1);
        subDir = m.group(2) ?? '';
      }
    }

    final branch =
        explicitBranch ?? await _defaultBranch(owner, repoName) ?? 'main';

    if (await _rawExists(owner, repoName, branch,
        subDir.isEmpty ? 'manifest.json' : '$subDir/manifest.json')) {
      final zipUrl = subDir.isEmpty
          ? 'https://github.com/$owner/$repoName/archive/refs/heads/$branch.zip'
          : 'https://github.com/$owner/$repoName/archive/refs/heads/$branch.zip';
      return GithubZipResolution(zipUrl, repoName);
    }

    final indexUrl =
        await _probeIndex(owner, repoName, branch, subDir);
    if (indexUrl != null) {
      return GithubIndexResolution(indexUrl, repoName);
    }

    return null;
  }

  static Future<String?> _defaultBranch(String owner, String repo) async {
    try {
      final res = await http
          .get(Uri.parse('https://api.github.com/repos/$owner/$repo'),
              headers: ghHeaders)
          .timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final json = jsonDecode(res.body) as Map<String, dynamic>;
        return json['default_branch'] as String?;
      }
    } catch (_) {}
    for (final b in const ['main', 'master']) {
      if (await _rawExists(owner, repo, b, 'README.md')) return b;
    }
    return null;
  }

  static Future<String?> _probeIndex(
      String owner, String repo, String branch, String dir) async {
    for (final candidate in indexCandidates) {
      final path = dir.isEmpty ? candidate : '$dir/$candidate';
      if (await _rawExists(owner, repo, branch, path)) {
        return 'https://raw.githubusercontent.com/$owner/$repo/$branch/$path';
      }
    }
    return null;
  }

  static Future<bool> _rawExists(
      String owner, String repo, String branch, String path) async {
    try {
      final res = await http
          .head(Uri.parse(
              'https://raw.githubusercontent.com/$owner/$repo/$branch/$path'),
              headers: ghHeaders)
          .timeout(const Duration(seconds: 8));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  static Future<GithubZipResolution?> _resolveLatestRelease(
      String owner, String repo) async {
    try {
      final res = await http
          .get(Uri.parse(
              'https://api.github.com/repos/$owner/$repo/releases/latest'),
              headers: ghHeaders)
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return null;
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      final assets = (json['assets'] as List?) ?? [];
      for (final asset in assets) {
        final name = asset['name'] as String?;
        final url = asset['browser_download_url'] as String?;
        if (name != null && url != null && name.endsWith('.zip')) {
          return GithubZipResolution(url, name);
        }
      }
      final tag = json['tag_name'] as String?;
      if (tag != null) {
        return GithubZipResolution(
          'https://github.com/$owner/$repo/archive/refs/tags/$tag.zip',
          repo,
        );
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  static String _nameFromUrl(String url) {
    final segs = url.split('/');
    return segs.isEmpty ? url : segs.last;
  }
}


class PluginSourceRepository {
  PluginSourceRepository._();
  static final PluginSourceRepository instance = PluginSourceRepository._();

  static const String officialRepoUrl = 'https://github.com/kingokksa/Clicker';
  static const String officialRepoRaw =
      'https://raw.githubusercontent.com/kingokksa/Clicker/main/plugins/plugin_index.json';

  final List<PluginSource> _sources = [];
  bool _loaded = false;

  List<PluginSource> get sources => List.unmodifiable(_sources);
  List<PluginSource> get enabledSources =>
      _sources.where((s) => s.enabled).toList();
  PluginSource? byId(String id) {
    for (final s in _sources) {
      if (s.id == id) return s;
    }
    return null;
  }

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    _sources.clear();
    _sources.add(PluginSource(
      id: 'official',
      name: '官方插件',
      url: officialRepoUrl,
      indexUrl: officialRepoRaw,
      type: PluginSourceType.official,
    ));
    try {
      final dir = await AppPaths.getDataDir();
      final file =
          File('$dir${Platform.pathSeparator}plugin_sources.json');
      if (await file.exists()) {
        final json = jsonDecode(await file.readAsString());
        for (final s in (json['sources'] as List? ?? [])) {
          final src =
              PluginSource.fromJson(Map<String, dynamic>.from(s as Map));
          if (src.id.isNotEmpty && byId(src.id) == null) {
            _sources.add(src);
          }
        }
      }
    } catch (_) {}
  }

  Future<void> save() async {
    try {
      final dir = await AppPaths.getDataDir();
      final file =
          File('$dir${Platform.pathSeparator}plugin_sources.json');
      await file.writeAsString(jsonEncode({
        'version': 1,
        'sources': _sources
            .where((s) => !s.isOfficial)
            .map((s) => s.toJson())
            .toList(),
      }));
    } catch (_) {}
  }

  Future<String?> addSource(String url,
      {void Function(String indexUrl)? onResolved}) async {
    await load();
    final resolution = await GithubUrlResolver.resolve(url);
    if (resolution == null) {
      return '无法识别该链接：不是 GitHub 仓库、索引或插件包地址';
    }
    if (resolution is GithubZipResolution) {
      return '这是插件包直链，请使用「从链接导入」直接安装';
    }
    final index = resolution as GithubIndexResolution;

    final json = await fetchIndexJson(index.indexUrl);
    if (json == null) {
      return '索引文件无法访问或格式不合法（需要包含 plugins 数组）';
    }
    final name = (json['name'] as String?)?.isNotEmpty == true
        ? json['name'] as String
        : index.suggestedName;

    final id = _idFromUrl(url);
    final existing = byId(id);
    if (existing != null) {
      return '该源已添加：${existing.name}';
    }

    final source = PluginSource(
      id: id,
      name: name,
      url: url.trim(),
      indexUrl: index.indexUrl,
      type: PluginSourceType.thirdParty,
    );
    _sources.add(source);
    await save();
    onResolved?.call(index.indexUrl);
    return null;
  }

  Future<void> removeSource(String id) async {
    _sources.removeWhere((s) => s.id == id && !s.isOfficial);
    await save();
  }

  Future<void> setEnabled(String id, bool enabled) async {
    final s = byId(id);
    if (s == null || s.isOfficial) return;
    s.enabled = enabled;
    await save();
  }

  static Future<Map<String, dynamic>?> fetchIndexJson(String url) async {
    try {
      final res = await http.get(Uri.parse(url), headers: ghHeaders)
          .timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) return null;
      final json = jsonDecode(utf8.decode(res.bodyBytes));
      if (json is! Map<String, dynamic>) return null;
      if (json['plugins'] is! List) return null;
      return json;
    } catch (_) {
      return null;
    }
  }

  static String _idFromUrl(String url) {
    var h = 0x811c9dc5;
    for (final c in url.codeUnits) {
      h ^= c;
      h = (h * 0x01000193) & 0x7fffffff;
    }
    return 'src_$h';
  }
}
