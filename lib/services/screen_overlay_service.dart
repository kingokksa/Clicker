library;

import 'dart:async';
import 'package:flutter/services.dart';
import 'system_tray_service.dart';

class ScreenOverlayService {
  ScreenOverlayService._();
  static final ScreenOverlayService instance = ScreenOverlayService._();

  static const _channel = MethodChannel('com.clicker.pro/platform');

  Completer<(int, int, int, int)>? _areaSelectCompleter;
  Completer<(int, int)>? _pickCompleter;
  bool _overlayActive = false;
  VoidCallback? _unregisterHandler;

  bool get overlayActive => _overlayActive;

  void _ensureHandler() {
    _unregisterHandler?.call();
    _unregisterHandler = SystemTrayService().registerExternalHandler(
      (call) async {
        switch (call.method) {
          case 'onOverlayClick':
            final args = call.arguments as Map;
            final x = args['x'] as int;
            final y = args['y'] as int;
            await _channel.invokeMethod('stopOverlay');
            _overlayActive = false;
            if (_pickCompleter != null && !_pickCompleter!.isCompleted) {
              _pickCompleter!.complete((x, y));
            }
            return true;
          case 'onOverlayWindowPick':
            final args = call.arguments as Map;
            final x = args['x'] as int;
            final y = args['y'] as int;
            await _channel.invokeMethod('stopOverlay');
            _overlayActive = false;
            if (_pickCompleter != null && !_pickCompleter!.isCompleted) {
              _pickCompleter!.complete((x, y));
            }
            return true;
          case 'onOverlayAreaSelected':
            final args = call.arguments as Map;
            final x1 = args['x1'] as int;
            final y1 = args['y1'] as int;
            final x2 = args['x2'] as int;
            final y2 = args['y2'] as int;
            await _channel.invokeMethod('stopOverlay');
            _overlayActive = false;
            if (_areaSelectCompleter != null && !_areaSelectCompleter!.isCompleted) {
              _areaSelectCompleter!.complete((x1, y1, x2, y2));
            }
            return true;
          case 'onOverlayCancelled':
            await _channel.invokeMethod('stopOverlay');
            _overlayActive = false;
            if (_areaSelectCompleter != null && !_areaSelectCompleter!.isCompleted) {
              _areaSelectCompleter!.completeError('cancelled');
            }
            if (_pickCompleter != null && !_pickCompleter!.isCompleted) {
              _pickCompleter!.completeError('cancelled');
            }
            return true;
          default:
            return null;
        }
      },
    );
  }

  Future<(int, int, int, int)?> startAreaSelect() async {
    _areaSelectCompleter = Completer<(int, int, int, int)>();
    _overlayActive = true;
    _ensureHandler();
    try {
      await _channel.invokeMethod('startAreaSelectOverlay');
      return await _areaSelectCompleter!.future;
    } on PlatformException {
      _overlayActive = false;
      _areaSelectCompleter = null;
      return null;
    } catch (e) {
      _overlayActive = false;
      _areaSelectCompleter = null;
      return null;
    }
  }

  Future<(int, int)?> startPick() async {
    _pickCompleter = Completer<(int, int)>();
    _overlayActive = true;
    _ensureHandler();
    try {
      await _channel.invokeMethod('startPickOverlay');
      return await _pickCompleter!.future;
    } on PlatformException {
      _overlayActive = false;
      _pickCompleter = null;
      return null;
    } catch (e) {
      _overlayActive = false;
      _pickCompleter = null;
      return null;
    }
  }

  Future<(int, int)?> startWindowPick(int hwnd) async {
    _pickCompleter = Completer<(int, int)>();
    _overlayActive = true;
    _ensureHandler();
    try {
      await _channel.invokeMethod('startWindowPickOverlay', [hwnd]);
      return await _pickCompleter!.future;
    } on PlatformException {
      _overlayActive = false;
      _pickCompleter = null;
      return null;
    } catch (e) {
      _overlayActive = false;
      _pickCompleter = null;
      return null;
    }
  }

  Future<void> showDetectionBoxes(List<Map<String, dynamic>> boxes) async {
    try {
      await _channel.invokeMethod('showDetectionBoxes', [boxes]);
      _overlayActive = true;
    } on PlatformException {
      _overlayActive = false;
    }
  }

  Future<void> updateDetectionBoxes(List<Map<String, dynamic>> boxes) async {
    try {
      await _channel.invokeMethod('updateDetectionBoxes', [boxes]);
    } on PlatformException {}
  }

  Future<void> stopOverlay() async {
    try {
      await _channel.invokeMethod('stopOverlay');
      _overlayActive = false;
    } on PlatformException {}
  }
}
