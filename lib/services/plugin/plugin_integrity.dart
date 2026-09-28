/// 插件包完整性校验 — SHA256 校验、安装留痕、原生库指纹复核。
///
/// 为什么需要：插件商店会从任意 GitHub 链接下载 zip 并 `DynamicLibrary.open`
/// 里面的 .dll。下载通道、Release 页面、GitHub 账号权限都是供应链攻击面。
/// 这里做三件事：
///   1. 下载后比对包体 SHA256（与索引声明核对），不匹配则拒绝安装
///   2. 每次安装写入 install_records.json，留存「谁、什么版本、装了什么指纹」
///   3. 原生插件激活前记录库指纹，下次激活时比对，漂移可被发现
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../app_paths.dart';

/// 校验结论
enum IntegrityVerdict {
  /// 指纹匹配
  ok,
  /// 指纹不匹配（内容被改动 / 被替换）
  changed,
  /// 无法判断（来源未声明指纹，或文件读不到）
  unknown,
}

/// 从 JSON map 安全取字符串（类型不符返回 null，不抛异常）
String? _str(Map json, String key) {
  final v = json[key];
  return v is String ? v : null;
}

/// 单次安装的留痕记录
class PluginInstallRecord {
  final String pluginId;
  final String version;
  final String zipSha256;
  final String source;
  final DateTime installedAt;

  const PluginInstallRecord({
    required this.pluginId,
    required this.version,
    required this.zipSha256,
    required this.source,
    required this.installedAt,
  });

  Map<String, dynamic> toJson() => {
        'pluginId': pluginId,
        'version': version,
        'zipSha256': zipSha256,
        'source': source,
        'installedAt': installedAt.toIso8601String(),
      };

  factory PluginInstallRecord.fromJson(Map json) => PluginInstallRecord(
        pluginId: _str(json, 'pluginId') ?? '',
        version: _str(json, 'version') ?? '',
        zipSha256: _str(json, 'zipSha256') ?? '',
        source: _str(json, 'source') ?? '',
        installedAt: DateTime.tryParse(_str(json, 'installedAt') ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
      );
}

/// 归一化指纹：小写、只留十六进制、必须 64 位
String normalizeHash(String? raw) {
  final s = (raw ?? '')
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^0-9a-f]'), '');
  return s.length == 64 ? s : '';
}

/// 完整性校验器（单例）
class PluginIntegrity {
  PluginIntegrity._();
  static final PluginIntegrity instance = PluginIntegrity._();

  final Map<String, dynamic> _records = {};
  bool _loaded = false;

  Future<void> _load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final dir = await AppPaths.getDataDir();
      final file = File('${dir}${Platform.pathSeparator}install_records.json');
      if (await file.exists()) {
        _records
            .addAll(jsonDecode(await file.readAsString()) as Map<String, dynamic>);
      }
    } catch (_) {
      // 损坏的留痕文件不应阻断插件流程
    }
  }

  Future<void> _save() async {
    try {
      final dir = await AppPaths.getDataDir();
      final file = File('${dir}${Platform.pathSeparator}install_records.json');
      await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert(_records),
      );
    } catch (_) {}
  }

  /// 安装完成后写入指纹留痕
  Future<void> recordInstall({
    required String pluginId,
    required String version,
    required String zipSha256,
    required String source,
  }) async {
    await _load();
    _records[pluginId] = PluginInstallRecord(
      pluginId: pluginId,
      version: version,
      zipSha256: normalizeHash(zipSha256),
      source: source,
      installedAt: DateTime.now(),
    ).toJson();
    await _save();
  }

  /// 读取该插件历史安装留下的包指纹
  String installedHashFor(String pluginId) {
    final rec = _records[pluginId];
    if (rec is! Map) return '';
    return normalizeHash(_str(rec, 'zipSha256'));
  }

  /// 读取该插件历史安装的版本
  String installedVersionFor(String pluginId) {
    final rec = _records[pluginId];
    if (rec is! Map) return '';
    return _str(rec, 'version') ?? '';
  }

  /// 计算文件 SHA256（十六进制小写）。文件不存在或不可读时返回空串。
  Future<String> sha256FileOrNull(String filePath) async {
    try {
      final f = File(filePath);
      if (!await f.exists()) return '';
      return sha256.convert(await f.readAsBytes()).toString();
    } catch (_) {
      return '';
    }
  }

  /// 原生库指纹复核。
  ///
  /// 首次见到某插件的原生库时没有历史锚点，返回 [IntegrityVerdict.unknown]
  /// 并记下指纹作为信任锚（TOFU）；之后每次激活都比对，不一致说明库文件
  /// 被改动过。
  Future<IntegrityVerdict> checkNativeLib(String pluginId, String libPath) async {
    await _load();
    final hash = await sha256FileOrNull(libPath);
    if (hash.isEmpty) return IntegrityVerdict.unknown;
    final key = 'nativeLib_${pluginId}';
    final previous = _records[key] is String ? _records[key] as String : '';
    if (normalizeHash(previous).isEmpty) {
      // 首次见到该库：记下指纹作为信任锚，下次激活起就能发现篡改。
      _records[key] = hash;
      await _save();
      return IntegrityVerdict.unknown;
    }
    return previous.toLowerCase() == hash
        ? IntegrityVerdict.ok
        : IntegrityVerdict.changed;
  }

  /// 该插件安装/升级后，旧的库指纹锚点已失效（升级本来就会换 dll）。
  /// 清掉它，让下次激活重新建立锚点，否则正常升级会被误判成篡改。
  Future<void> dropNativeLibAnchor(String pluginId) async {
    await _load();
    final key = 'nativeLib_${pluginId}';
    if (_records.containsKey(key)) {
      _records.remove(key);
      await _save();
    }
  }
}
