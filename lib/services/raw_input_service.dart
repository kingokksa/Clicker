import 'dart:async';

import 'package:flutter/services.dart';

class RawInputService {
  RawInputService._() {
    _channel.setMethodCallHandler((call) async {
      final raw = call.arguments;
      final args = raw is Map ? raw.cast<Object?, Object?>() : const <Object?, Object?>{};
      int asInt(Object? value) => value is num ? value.toInt() : 0;
      switch (call.method) {
        case 'onRawMouseMove':
          final dx = asInt(args['dx']);
          final dy = asInt(args['dy']);
          if (!_mouseMoves.isClosed) _mouseMoves.add((dx, dy));
          break;
        case 'onRawKey':
          onRawKey?.call(asInt(args['vk']), args['down'] == true);
          break;
        case 'onUserInput':
          final kind = args['kind'];
          onUserInput?.call(
            kind is String ? kind : '',
            asInt(args['vk']),
            asInt(args['message']),
            asInt(args['dx']),
          );
          break;
      }
      return null;
    });
  }

  static final RawInputService instance = RawInputService._();

  static const MethodChannel _channel = MethodChannel('com.clicker.pro/rawinput');

  bool _rawInputEnabled = false;
  bool _monitoring = false;

  final StreamController<(int, int)> _mouseMoves =
      StreamController<(int, int)>.broadcast();

  Stream<(int, int)> get mouseMoves => _mouseMoves.stream;

  void Function(int vk, bool down)? onRawKey;
  void Function(String kind, int vk, int message, int delta)? onUserInput;

  bool get rawInputEnabled => _rawInputEnabled;
  bool get monitoring => _monitoring;

  Future<bool> setRawInputEnabled(bool enable) async {
    if (enable == _rawInputEnabled) return _rawInputEnabled;
    try {
      final ok = await _channel.invokeMethod<bool>('setRawInputEnabled', [enable]);
      _rawInputEnabled = ok ?? false;
    } catch (_) {
      _rawInputEnabled = false;
    }
    return _rawInputEnabled;
  }

  Future<bool> setUserInputMonitor(bool enable) async {
    try {
      final ok = await _channel.invokeMethod<bool>('setUserInputMonitor', [enable]);
      _monitoring = ok ?? false;
    } catch (_) {
      _monitoring = false;
    }
    return _monitoring;
  }
}
