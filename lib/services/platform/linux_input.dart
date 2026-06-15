library;

import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'platform_input.dart';

class LinuxInput extends PlatformInput {
  static const _channel = MethodChannel('com.clicker.pro/platform');

  final StreamController<String> _keyController =
      StreamController<String>.broadcast();

  bool _listening = false;

  @override
  bool get isSupported => Platform.isLinux;

  @override
  Future<void> mouseClick({
    required int x,
    required int y,
    String button = 'left',
    bool doubleClick = false,
  }) async {
    try {
      await _channel.invokeMethod('mouseClick', {
        'x': x,
        'y': y,
        'button': button,
        'doubleClick': doubleClick,
      });
    } catch (_) {
      await _xdotoolClick(x, y, button, doubleClick);
    }
  }

  @override
  void syncClick({required int x, required int y, String button = 'left'}) {
    _xdotoolClickSync(x, y, button);
  }

  @override
  Future<void> mouseMove(int x, int y) async {
    try {
      await _channel.invokeMethod('mouseMove', {'x': x, 'y': y});
    } catch (_) {
      await Process.run('xdotool', ['mousemove', '$x', '$y']);
    }
  }

  @override
  Future<void> mouseDown({
    required int x,
    required int y,
    String button = 'left',
  }) async {
    final btn = _linuxButton(button);
    try {
      await _channel.invokeMethod('mouseDown', {'x': x, 'y': y, 'button': btn});
    } catch (_) {
      await Process.run('xdotool', ['mousemove', '$x', '$y', 'mousedown', btn]);
    }
  }

  @override
  Future<void> mouseUp({
    required int x,
    required int y,
    String button = 'left',
  }) async {
    final btn = _linuxButton(button);
    try {
      await _channel.invokeMethod('mouseUp', {'x': x, 'y': y, 'button': btn});
    } catch (_) {
      await Process.run('xdotool', ['mousemove', '$x', '$y', 'mouseup', btn]);
    }
  }

  @override
  Future<void> mouseScroll({double dx = 0, double dy = 0}) async {
    try {
      await _channel.invokeMethod('mouseScroll', {'dx': dx, 'dy': dy});
    } catch (_) {
      final clicks = (dy.abs() / 120).round().clamp(1, 20);
      final btn = dy > 0 ? '5' : '4';
      for (int i = 0; i < clicks; i++) {
        await Process.run('xdotool', ['click', btn]);
      }
    }
  }

  @override
  Future<void> touchLongPress({required int x, required int y, int durationMs = 500}) async {
    await mouseDown(x: x, y: y);
    await Future.delayed(Duration(milliseconds: durationMs));
    await mouseUp(x: x, y: y);
  }

  @override
  Future<void> touchDrag({
    required int startX, required int startY,
    required int endX, required int endY,
    int durationMs = 300,
  }) async {
    await mouseMove(startX, startY);
    await mouseDown(x: startX, y: startY);
    final steps = (durationMs / 16).ceil().clamp(1, 60);
    final stepDelay = Duration(milliseconds: (durationMs / steps).round());
    for (int i = 1; i <= steps; i++) {
      final t = i / steps;
      final cx = (startX + (endX - startX) * t).round();
      final cy = (startY + (endY - startY) * t).round();
      await mouseMove(cx, cy);
      await Future.delayed(stepDelay);
    }
    await mouseUp(x: endX, y: endY);
  }

  @override
  Future<void> touchSwipe({
    required int startX, required int startY,
    required int endX, required int endY,
    int durationMs = 200,
  }) async {
    await touchDrag(
      startX: startX, startY: startY,
      endX: endX, endY: endY,
      durationMs: durationMs,
    );
  }

  @override
  Future<void> keyPress(String key) async {
    try {
      await _channel.invokeMethod('keyPress', {'key': key});
    } catch (_) {
      await Process.run('xdotool', ['key', key]);
    }
  }

  @override
  Future<void> keyRelease(String key) async {
    try {
      await _channel.invokeMethod('keyRelease', {'key': key});
    } catch (_) {
      await Process.run('xdotool', ['keyup', key]);
    }
  }

  @override
  Future<void> keyType(String text, {int delayMs = 30}) async {
    try {
      await _channel.invokeMethod('keyType', {'text': text, 'delayMs': delayMs});
    } catch (_) {
      await Process.run('xdotool', ['type', '--delay', '$delayMs', text]);
    }
  }

  @override
  Future<({int height, int width})> getScreenSize() async {
    try {
      final result = await _channel.invokeMethod('getScreenSize');
      if (result != null) {
        final m = Map<String, dynamic>.from(result as Map);
        return (width: m['width'] as int, height: m['height'] as int);
      }
    } catch (_) {}
    try {
      final result = await Process.run('xdotool', ['getdisplaygeometry']);
      final parts = (result.stdout as String).trim().split(' ');
      if (parts.length == 2) {
        return (width: int.parse(parts[0]), height: int.parse(parts[1]));
      }
    } catch (_) {}
    return (width: 1920, height: 1080);
  }

  @override
  Stream<String> get globalKeyEvents => _keyController.stream;

  @override
  void startListening() {
    if (_listening) return;
    _listening = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onGlobalKey') {
        _keyController.add(call.arguments as String);
      }
    });
  }

  @override
  void stopListening() {
    _listening = false;
    _channel.setMethodCallHandler(null);
  }

  @override
  void dispose() {
    stopListening();
    _keyController.close();
  }

  @override
  Future<dynamic> invokeMethod(String method, [dynamic arguments]) async {
    try {
      return await _channel.invokeMethod(method, arguments);
    } catch (_) {
      return null;
    }
  }

  String _linuxButton(String button) {
    switch (button) {
      case 'right': return '3';
      case 'middle': return '2';
      default: return '1';
    }
  }

  Future<void> _xdotoolClick(int x, int y, String button, bool doubleClick) async {
    final btn = _linuxButton(button);
    await Process.run('xdotool', ['mousemove', '$x', '$y', 'click', btn]);
    if (doubleClick) {
      await Future.delayed(const Duration(milliseconds: 50));
      await Process.run('xdotool', ['click', btn]);
    }
  }

  void _xdotoolClickSync(int x, int y, String button) {
    final btn = _linuxButton(button);
    Process.run('xdotool', ['mousemove', '$x', '$y', 'click', btn]);
  }
}
