/// 插件源管理 — 多源插件商店 + GitHub URL 智能解析。
///
/// 源体系（插件分发渠道，用户可自由扩展）：
/// - 官方源（内置）：GitHub 官方插件仓库的 plugins/plugin_index.json
/// - 第三方源：其他作者自己的 GitHub 仓库（索引格式与官方一致）
/// - 直接导入：任意 GitHub 链接（zip 包 / 插件仓库 / Release）
///
/// 支持的 GitHub URL 形式：
///   https://github.com/{owner}/{repo}                       → 探测仓库索引
///   https://github.com/{owner}/{repo}/tree/{branch}/{dir}   → 探测子目录索引
///   https://raw.githubusercontent.com/.../plugin_index.json → 直接的索引 URL
///   https://github.com/{owner}/{repo}/releases/download/{tag}/{file}.zip → 插件包直链
///   https://github.com/{owner}/{repo}/releases              → 最新 Release 的 zip
///   https://github.com/{owner}/{repo}/archive/refs/heads/{branch}.zip    → 仓库打包
library;

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../app_paths.dart';

/// GitHub API / raw 请求公共头（GitHub 要求 User-Agent）
const Map<String, String> ghHeaders = {
  'User-Agent': 'Clicker-PluginStore',
};

/// 索引文件在仓库中的常见路径（按优先级探测）
const List<String> indexCandidates = [
  'plugins/plugin_index.json',
  'plugin_index.json',
  '.clicker/plugin_index.json',
  'index.json',
];

// ─── 源模型 ────────────────────────────────────────────────

/// 源类型
enum PluginSourceType {
  official('official'),
  thirdParty('third_party');

  final String id;
  const PluginSourceType(this.id);

  static PluginSourceType fromString(String? s) =>
      s == 'official' ? PluginSourceType.official : PluginSourceType.thirdParty;
}

/// 插件源 — 一个远程插件索引（GitHub 仓库或 raw URL）
class PluginSource {
  final String id;      // 稳定标识（官方固定 'official'，第三方按 URL 内容 hash）
  String name;          // 显示名称（拉取后从索引 name 字段更新）
  final String url;     // 用户输入的原始 URL
  final String indexUrl; // 解析后的索引 raw URL
  final PluginSourceType type;
  bool enabled;
  String? error;        // 上次拉取错误（null = 成功）
  int pluginCount = 0;  // 上次拉取到的插件数

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

// ─── GitHub URL 解析 ───────────────────────────────────────

/// 解析结果：索引 URL（可作为源添加）
class GithubIndexResolution {
  final String indexUrl;
  final String suggestedName;
  const GithubIndexResolution(this.indexUrl, this.suggestedName);
}

/// 解析结果：可直接下载安装的插件包
class GithubZipResolution {
  final String zipUrl;
  final String suggestedName;
  const GithubZipResolution(this.zipUrl, this.suggestedName);
}

/// GitHub URL 智能解析器
class GithubUrlResolver {
  GithubUrlResolver._();

  /// 解析任意 GitHub 链接。返回索引或 zip；无法识别返回 null。
  static Future<Object?> resolve(String input) async {
    final url = input.trim().replaceAll(RegExp(r'/+$'), '');
    if (url.isEmpty) return null;

    // 1. raw.githubusercontent 直链
    if (url.startsWith('https://raw.githubusercontent.com/')) {
      if (url.endsWith('.json')) {
        return GithubIndexResolution(url, _nameFromUrl(url));
      }
      if (url.endsWith('.zip')) {
        return GithubZipResolution(url, _nameFromUrl(url));
      }
      return null;
    }

    // 2. Release 下载直链
    final releaseZip = RegExp(
      r'^https?://github\.com/([^/]+)/([^/]+)/releases/download/([^/]+)/([^?#]+\.zip)$',
    ).firstMatch(url);
    if (releaseZip != null) {
      return GithubZipResolution(url, releaseZip.group(4)!);
    }

    // 3. archive 打包直链
    final archiveZip = RegExp(
      r'^https?://github\.com/([^/]+)/([^/]+)/archive/refs/heads/([^?#]+\.zip)$',
    ).firstMatch(url);
    if (archiveZip != null) {
      return GithubZipResolution(url, archiveZip.group(3)!);
    }

    // 4. github.com 仓库 / 子目录 / releases 页面
    final repo = RegExp(
      r'^https?://github\.com/([^/]+)/([^/]+)((/.*)?)$',
    ).firstMatch(url);
    if (repo == null) return null;

    final owner = repo.group(1)!;
    final repoName = repo.group(2)!;
    final path = (repo.group(3) ?? '').replaceAll(RegExp(r'^/|/$'), '');

    // releases 页面 → 最新 Release 的 zip 资产
    if (path == 'releases' || path.startsWith('releases/')) {
      return _resolveLatestRelease(owner, repoName);
    }

    // tree/子目录
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

    // 4a. 仓库/子目录本身是一个插件（有 manifest.json）→ 整包下载
    if (await _rawExists(owner, repoName, branch,
        subDir.isEmpty ? 'manifest.json' : '$subDir/manifest.json')) {
      final zipUrl = subDir.isEmpty
          ? 'https://github.com/$owner/$repoName/archive/refs/heads/$branch.zip'
          : 'https://github.com/$owner/$repoName/archive/refs/heads/$branch.zip'; // 子目录插件也下整包，installFromZip 会取 manifest 所在层
      return GithubZipResolution(zipUrl, repoName);
    }

    // 4b. 探测索引文件
    final indexUrl =
        await _probeIndex(owner, repoName, branch, subDir);
    if (indexUrl != null) {
      return GithubIndexResolution(indexUrl, repoName);
    }

    return null;
  }

  /// 获取仓库默认分支（GitHub API，失败回退 main/master 探测）
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

  /// 探测仓库/子目录下的索引文件
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

  /// 检查 raw 文件是否存在
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

  /// 最新 Release 的第一个 zip 资产
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
      // Release 没有 zip 资产 → 尝试源码包
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

// ─── 源仓库（持久化）──────────────────────────────────────

/// 插件源仓库 — 管理源列表，持久化到 data/plugin_sources.json
class PluginSourceRepository {
  PluginSourceRepository._();
  static final PluginSourceRepository instance = PluginSourceRepository._();

  /// 官方插件仓库（用户自己的 GitHub）
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

  /// 加载：官方源（固定）+ 持久化的第三方源
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

  /// 添加第三方源。
  /// [url] 任意 GitHub 链接；返回错误消息（null = 成功）。
  /// [onResolved] 解析成功后回调（可用于 UI 展示解析结果）。
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

    // 验证索引可访问且格式合法
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

  /// 直接移除第三方源
  Future<void> removeSource(String id) async {
    _sources.removeWhere((s) => s.id == id && !s.isOfficial);
    await save();
  }

  /// 启用/禁用源
  Future<void> setEnabled(String id, bool enabled) async {
    final s = byId(id);
    if (s == null || s.isOfficial) return;
    s.enabled = enabled;
    await save();
  }

  /// 拉取并校验索引 JSON；失败返回 null
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

  /// URL 内容 hash（FNV-1a 31bit，跨运行稳定）
  static String _idFromUrl(String url) {
    var h = 0x811c9dc5;
    for (final c in url.codeUnits) {
      h ^= c;
      h = (h * 0x01000193) & 0x7fffffff;
    }
    return 'src_$h';
  }
}
