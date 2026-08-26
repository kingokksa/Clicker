library;

import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'platform_input.dart';

class AndroidInput extends PlatformInput {
  static const _inputChannel = MethodChannel('clicker/input');
  static const _platformChannel = MethodChannel('com.clicker.pro/platform');
  static const _recordChannel = MethodChannel('com.clicker.pro/record');

  final StreamController<String> _keyController =
      StreamController<String>.broadcast();

  bool _listening = false;

  /// Receives touch-gesture events captured by the native recording overlay
  /// while a macro is being recorded. Maps to MacroService's record handler.
  void Function(Map<String, dynamic> event)? onRecordEvent;

  /// Called when the user taps the native floating stop button during recording.
  void Function()? onStopRecordingRequested;

  /// Start capturing touch gestures via the native recording overlay.
  Future<void> startRecording() async {
    _recordChannel.setMethodCallHandler((call) async {
      if (call.method == 'onRecordEvent') {
        final args = call.arguments as Map?;
        if (args != null) {
          onRecordEvent?.call(args.cast<String, dynamic>());
        }
      } else if (call.method == 'stopRecordingRequested') {
        onStopRecordingRequested?.call();
      }
    });
    try {
      await _recordChannel.invokeMethod('startRecording');
    } catch (_) {}
  }

  /// Stop capturing touch gestures and remove the recording overlay.
  Future<void> stopRecording() async {
    _recordChannel.setMethodCallHandler(null);
    try {
      await _recordChannel.invokeMethod('stopRecording');
    } catch (_) {}
  }

  /// Check if accessibility service is enabled
  Future<bool> isAccessibilityServiceEnabled() async {
    try {
      final result = await _platformChannel.invokeMethod<bool>('isAccessibilityEnabled');
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Open accessibility settings
  Future<void> openAccessibilitySettings() async {
    try {
      await _platformChannel.invokeMethod('openAccessibilitySettings');
    } catch (_) {}
  }

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
    } on PlatformException catch (e) {
      print('[AndroidInput] mouseClick failed: ${e.code} - ${e.message}');
      rethrow;
    } catch (e) {
      print('[AndroidInput] mouseClick failed: $e');
      rethrow;
    }
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
  Future<void> touchLongPress({required int x, required int y, int durationMs = 500}) async {
    try {
      await _inputChannel.invokeMethod('dispatchGesture', {
        'action': 'longPress',
        'x': x,
        'y': y,
        'durationMs': durationMs,
      });
    } catch (_) {}
  }

  @override
  Future<void> touchDrag({
    required int startX, required int startY,
    required int endX, required int endY,
    int durationMs = 300,
  }) async {
    try {
      await _inputChannel.invokeMethod('dispatchGesture', {
        'action': 'drag',
        'startX': startX, 'startY': startY,
        'endX': endX, 'endY': endY,
        'durationMs': durationMs,
      });
    } catch (_) {}
  }

  @override
  Future<void> touchSwipe({
    required int startX, required int startY,
    required int endX, required int endY,
    int durationMs = 200,
  }) async {
    try {
      await _inputChannel.invokeMethod('dispatchGesture', {
        'action': 'swipe',
        'startX': startX, 'startY': startY,
        'endX': endX, 'endY': endY,
        'durationMs': durationMs,
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
