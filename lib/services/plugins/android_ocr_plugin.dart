library;

import 'dart:io';
import 'package:flutter/services.dart';
import '../vision_plugin.dart';

class AndroidOcrPlugin extends VisionPlugin {
  static const _channel = MethodChannel('com.clicker.pro/platform');
  bool _available = false;
  String? _unavailableReason;

  @override
  final VisionPluginInfo info = const VisionPluginInfo(
    id: 'builtin_android_ocr',
    name: 'ML Kit OCR',
    description: 'Google ML Kit 文字识别引擎，支持中英文离线识别',
    version: '1.0.0',
    author: 'Clicker',
    capabilities: [VisionCapability.ocr],
    isBuiltin: true,
  );

  @override
  bool get isAvailable => _available;

  String? get unavailableReason => _unavailableReason;

  @override
  Future<bool> initialize() async {
    if (!Platform.isAndroid) {
      _available = false;
      _unavailableReason = '仅支持 Android 平台';
      return false;
    }
    try {
      final check = await _channel.invokeMethod<Map>('checkOcrAvailable');
      if (check != null && check['available'] == true) {
        _available = true;
        _unavailableReason = null;
        return true;
      }
    } on PlatformException {
      // checkOcrAvailable not implemented yet
    }
    try {
      final result = await _channel.invokeMethod<Map>('ocrRegion', [0, 0, 10, 10, 'zh']);
      if (result != null) {
        _available = true;
        _unavailableReason = null;
        return true;
      }
    } on PlatformException catch (e) {
      if (e.code == 'OCR_NOT_AVAILABLE') {
        _available = false;
        _unavailableReason = 'ML Kit OCR 不可用';
        return false;
      }
    }
    _available = true;
    _unavailableReason = null;
    return true;
  }

  @override
  Future<void> dispose() async {
    _available = false;
  }

  @override
  Future<VisionOcrResult> recognizeText({
    required int x,
    required int y,
    required int w,
    required int h,
    String language = 'zh-Hans-CN',
  }) async {
    if (!_available) {
      return VisionOcrResult(
        text: '',
        error: _unavailableReason ?? 'ML Kit OCR 不可用',
      );
    }

    try {
      final lang = language.startsWith('zh') ? 'zh' : 'en';
      final result = await _channel.invokeMethod<Map>('ocrRegion', [x, y, w, h, lang]);
      if (result == null) {
        return const VisionOcrResult(text: '', error: 'OCR 返回空结果');
      }
      return VisionOcrResult(
        text: result['text'] as String? ?? '',
        x: result['x'] as int? ?? x,
        y: result['y'] as int? ?? y,
        width: result['width'] as int? ?? w,
        height: result['height'] as int? ?? h,
      );
    } on PlatformException catch (e) {
      if (e.code == 'OCR_NOT_AVAILABLE') {
        _available = false;
        _unavailableReason = 'ML Kit OCR 不可用';
        return const VisionOcrResult(
          text: '',
          error: 'OCR不可用',
        );
      }
      return VisionOcrResult(text: '', error: 'OCR 错误: ${e.message}');
    }
  }
}
