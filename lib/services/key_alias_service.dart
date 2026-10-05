
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/key_alias.dart';
import 'app_paths.dart';

class KeyAliasService extends ChangeNotifier {
  KeyAliasService._();
  static final KeyAliasService instance = KeyAliasService._();

  static const String _fileName = 'key_aliases.json';

  final List<KeyAliasProfile> _profiles = [];
  final Map<String, String> _lookup = {};
  int _activeIndex = 0;
  bool _loaded = false;
  String? _filePath;

  List<KeyAliasProfile> get profiles => List.unmodifiable(_profiles);
  int get activeIndex => _activeIndex;
  KeyAliasProfile? get activeProfile =>
      _activeIndex >= 0 && _activeIndex < _profiles.length ? _profiles[_activeIndex] : null;
  List<KeyAlias> get aliases => activeProfile?.aliases ?? const [];
  List<KeyAlias> get keyboardAliases =>
      aliases.where((a) => !isMouseKey(a.key)).toList();
  List<KeyAlias> get mouseAliases => aliases.where((a) => isMouseKey(a.key)).toList();

  static bool isMouseKey(String key) => key.startsWith(mouseKeyPrefix);

  static String mouseButtonOf(String key) =>
      key.startsWith(mouseKeyPrefix) ? key.substring(mouseKeyPrefix.length) : key;

  Future<String> _path() async =>
      _filePath ??= '${await AppPaths.getDataDir()}${Platform.pathSeparator}$_fileName';

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final file = File(await _path());
      if (await file.exists()) {
        final json = jsonDecode(await file.readAsString());
        if (json is Map) {
          _activeIndex = (json['active'] as num?)?.toInt() ?? 0;
          final list = (json['profiles'] as List?) ?? const [];
          _profiles
            ..clear()
            ..addAll(list
                .whereType<Map>()
                .map((e) => KeyAliasProfile.fromJson(e.cast<String, dynamic>())));
        }
      }
    } catch (_) {}
    if (_profiles.isEmpty) _profiles.add(const KeyAliasProfile(name: '默认'));
    if (_activeIndex < 0 || _activeIndex >= _profiles.length) _activeIndex = 0;
    _rebuildLookup();
  }

  void _rebuildLookup() {
    _lookup.clear();
    for (final a in aliases) {
      final name = a.name.trim().toLowerCase();
      if (name.isEmpty || a.key.isEmpty) continue;
      _lookup[name] = a.key;
    }
  }

  Future<void> _save() async {
    try {
      final file = File(await _path());
      await file.writeAsString(jsonEncode({
        'version': 1,
        'active': _activeIndex,
        'profiles': _profiles.map((p) => p.toJson()).toList(),
      }));
    } catch (_) {}
  }

  String resolve(String input) {
    final trimmed = input.trim();
    if (!trimmed.startsWith(keyAliasPrefix)) return input;
    final name = trimmed.substring(keyAliasPrefix.length).trim().toLowerCase();
    if (name.isEmpty) return input;
    return _lookup[name] ?? input;
  }

  KeyAlias? byName(String name) {
    final key = _lookup[name.trim().toLowerCase()];
    if (key == null) return null;
    return KeyAlias(name: name.trim(), key: key);
  }

  bool isAliasReference(String input) {
    final trimmed = input.trim();
    if (!trimmed.startsWith(keyAliasPrefix)) return false;
    return _lookup.containsKey(
        trimmed.substring(keyAliasPrefix.length).trim().toLowerCase());
  }

  List<KeyAlias> _mutateAliases(void Function(List<KeyAlias> list) fn) {
    final current = activeProfile;
    if (current == null) return const [];
    final list = List<KeyAlias>.from(current.aliases);
    fn(list);
    _profiles[_activeIndex] = current.copyWith(aliases: list);
    _rebuildLookup();
    notifyListeners();
    return list;
  }

  Future<void> addAlias(String name, String key) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty || key.isEmpty) return;
    _mutateAliases((list) {
      final existing = list.indexWhere(
          (a) => a.name.trim().toLowerCase() == trimmed.toLowerCase());
      if (existing >= 0) {
        list[existing] = KeyAlias(name: trimmed, key: key);
      } else {
        list.add(KeyAlias(name: trimmed, key: key));
      }
    });
    await _save();
  }

  Future<void> updateAlias(int index, {String? name, String? key}) async {
    if (index < 0 || index >= aliases.length) return;
    _mutateAliases((list) => list[index] = list[index].copyWith(name: name, key: key));
    await _save();
  }

  Future<void> removeAlias(int index) async {
    if (index < 0 || index >= aliases.length) return;
    _mutateAliases((list) => list.removeAt(index));
    await _save();
  }

  Future<void> addProfile(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    _profiles.add(KeyAliasProfile(name: trimmed));
    _activeIndex = _profiles.length - 1;
    _rebuildLookup();
    notifyListeners();
    await _save();
  }

  Future<void> renameProfile(int index, String name) async {
    final trimmed = name.trim();
    if (index < 0 || index >= _profiles.length || trimmed.isEmpty) return;
    _profiles[index] = _profiles[index].copyWith(name: trimmed);
    notifyListeners();
    await _save();
  }

  Future<void> removeProfile(int index) async {
    if (index < 0 || index >= _profiles.length) return;
    _profiles.removeAt(index);
    if (_profiles.isEmpty) _profiles.add(const KeyAliasProfile(name: '默认'));
    if (_activeIndex >= _profiles.length) _activeIndex = _profiles.length - 1;
    _rebuildLookup();
    notifyListeners();
    await _save();
  }

  Future<void> setActive(int index) async {
    if (index < 0 || index >= _profiles.length || index == _activeIndex) return;
    _activeIndex = index;
    _rebuildLookup();
    notifyListeners();
    await _save();
  }

  Future<String> exportTo(String path) async {
    await ensureLoaded();
    final file = File(path);
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert({
      'version': 1,
      'active': _activeIndex,
      'profiles': _profiles.map((p) => p.toJson()).toList(),
    }));
    return file.path;
  }

  Future<int> importFrom(String path) async {
    await ensureLoaded();
    final json = jsonDecode(await File(path).readAsString());
    final list = (json is Map ? json['profiles'] : json) as List?;
    if (list == null) return 0;
    var added = 0;
    var firstImported = -1;
    for (final raw in list.whereType<Map>()) {
      final profile = KeyAliasProfile.fromJson(raw.cast<String, dynamic>());
      if (profile.name.trim().isEmpty) continue;
      final existing = _profiles.indexWhere(
          (p) => p.name.trim().toLowerCase() == profile.name.trim().toLowerCase());
      if (existing >= 0) {
        _profiles[existing] = profile;
        if (firstImported < 0) firstImported = existing;
      } else {
        _profiles.add(profile);
        if (firstImported < 0) firstImported = _profiles.length - 1;
      }
      added++;
    }
    if (firstImported >= 0) {
      _activeIndex = firstImported;
    } else if (json is Map && json['active'] is num) {
      final idx = (json['active'] as num).toInt();
      if (idx >= 0 && idx < _profiles.length) _activeIndex = idx;
    }
    _rebuildLookup();
    notifyListeners();
    await _save();
    return added;
  }
}
