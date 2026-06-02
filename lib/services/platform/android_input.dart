library;

import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'platform_input.dart';

class AndroidInput extends PlatformInput {
  static const _inputChannel = MethodChannel('clicker/input');
  static const _platformChannel = MethodChannel('com.clicker.pro/platform');

  final StreamController<String> _keyController =
      StreamController<String>.broadcast();

  bool _listening = false;

  @override
  bool get isSupported => Platform.isAndroid;

  @override
  Future<void> mouseClick({
    required int x,
    required int y,
    String button = 'left',
    bool doubleClick = false,
  }) async {
    try {
      for (int i = 0; i < (doubleClick ? 2 : 1); i++) {
        await _inputChannel.invokeMethod('dispatchGesture', {
          'x': x,
          'y': y,
          'action': 'click',
        });
        if (doubleClick && i == 0) {
          await Future.delayed(const Duration(milliseconds: 50));
        }
      }
    } catch (_) {}
  }

  @override
  void syncClick({required int x, required int y, String button = 'left'}) {
  }

  @override
  Future<void> mouseMove(int x, int y) async {
  }

  @override
  Future<void> mouseDown({
    required int x,
    required int y,
    String button = 'left',
  }) async {
    try {
      await _inputChannel.invokeMethod('dispatchGesture', {
        'x': x,
        'y': y,
        'action': 'down',
      });
    } catch (_) {}
  }

  @override
  Future<void> mouseUp({
    required int x,
    required int y,
    String button = 'left',
  }) async {
    try {
      await _inputChannel.invokeMethod('dispatchGesture', {
        'x': x,
        'y': y,
        'action': 'up',
      });
    } catch (_) {}
  }

  @override
  Future<void> mouseScroll({double dx = 0, double dy = 0}) async {
    try {
      await _inputChannel.invokeMethod('dispatchGesture', {
        'action': 'scroll',
        'dx': dx,
        'dy': dy,
      });
    } catch (_) {}
  }

  @override
  Future<void> keyPress(String key) async {
    try {
      await _inputChannel.invokeMethod('keyPress', {'key': key});
    } catch (_) {}
  }

  @override
  Future<void> keyRelease(String key) async {
    try {
      await _inputChannel.invokeMethod('keyRelease', {'key': key});
    } catch (_) {}
  }

  @override
  Future<void> keyType(String text, {int delayMs = 30}) async {
    try {
      await _inputChannel.invokeMethod('keyType', {
        'text': text,
        'delayMs': delayMs,
      });
    } catch (_) {}
  }

  @override
  Future<({int height, int width})> getScreenSize() async {
    try {
      final result = await _platformChannel.invokeMethod('getScreenSize');
      if (result != null) {
        final m = Map<String, dynamic>.from(result as Map);
        return (width: m['width'] as int, height: m['height'] as int);
      }
    } catch (_) {}
    return (width: 1080, height: 1920);
  }

  @override
  Stream<String> get globalKeyEvents => _keyController.stream;

  @override
  void startListening() {
    if (_listening) return;
    _listening = true;
    _inputChannel.setMethodCallHandler((call) async {
      if (call.method == 'onVolumeKeyEvent') {
        _keyController.add(call.arguments as String);
      }
    });
  }

  @override
  void stopListening() {
    _listening = false;
    _inputChannel.setMethodCallHandler(null);
  }

  @override
  void dispose() {
    stopListening();
    _keyController.close();
  }

  @override
  Future<dynamic> invokeMethod(String method, [dynamic arguments]) async {
    try {
      return await _platformChannel.invokeMethod(method, arguments);
    } catch (_) {
      return null;
    }
  }
}
