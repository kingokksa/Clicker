import 'dart:convert';
import 'dart:math';

import '../local_storage.dart';

class ApiToken {
  ApiToken._();

  static const String _key = 'api_token';

  static String? _cached;

  static String get current => _cached ??= _load();

  static String _load() {
    final stored = LocalStorage.instance.getString(_key);
    if (stored != null && stored.isNotEmpty) return stored;
    final t = generate();
    LocalStorage.instance.setString(_key, t);
    return t;
  }

  static String generate() {
    final rnd = Random.secure();
    final bytes = List<int>.generate(32, (_) => rnd.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  static String regenerate() {
    final t = generate();
    _cached = t;
    LocalStorage.instance.setString(_key, t);
    return t;
  }

  static bool verify(String? provided) {
    if (provided == null || provided.isEmpty) return false;
    final expected = current;
    if (expected.isEmpty) return false;
    if (provided.length != expected.length) return false;
    var diff = 0;
    for (var i = 0; i < expected.length; i++) {
      diff |= expected.codeUnitAt(i) ^ provided.codeUnitAt(i);
    }
    return diff == 0;
  }
}
