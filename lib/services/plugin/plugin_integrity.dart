
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../app_paths.dart';

enum IntegrityVerdict {
  ok,
  changed,
  unknown,
}

String? _str(Map json, String key) {
  final v = json[key];
  return v is String ? v : null;
}

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

String normalizeHash(String? raw) {
  final s = (raw ?? '')
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^0-9a-f]'), '');
  return s.length == 64 ? s : '';
}

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

  String installedHashFor(String pluginId) {
    final rec = _records[pluginId];
    if (rec is! Map) return '';
    return normalizeHash(_str(rec, 'zipSha256'));
  }

  String installedVersionFor(String pluginId) {
    final rec = _records[pluginId];
    if (rec is! Map) return '';
    return _str(rec, 'version') ?? '';
  }

  Future<String> sha256FileOrNull(String filePath) async {
    try {
      final f = File(filePath);
      if (!await f.exists()) return '';
      return sha256.convert(await f.readAsBytes()).toString();
    } catch (_) {
      return '';
    }
  }

  Future<IntegrityVerdict> checkNativeLib(String pluginId, String libPath) async {
    await _load();
    final hash = await sha256FileOrNull(libPath);
    if (hash.isEmpty) return IntegrityVerdict.unknown;
    final key = 'nativeLib_${pluginId}';
    final previous = _records[key] is String ? _records[key] as String : '';
    if (normalizeHash(previous).isEmpty) {
      _records[key] = hash;
      await _save();
      return IntegrityVerdict.unknown;
    }
    return previous.toLowerCase() == hash
        ? IntegrityVerdict.ok
        : IntegrityVerdict.changed;
  }

  Future<void> dropNativeLibAnchor(String pluginId) async {
    await _load();
    final key = 'nativeLib_${pluginId}';
    if (_records.containsKey(key)) {
      _records.remove(key);
      await _save();
    }
  }
}
