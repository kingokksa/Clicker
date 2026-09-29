
import 'dart:io';
import 'package:flutter/services.dart';
import '../vision_plugin.dart';

class WindowsOcrPlugin extends VisionPlugin {
  static const _channel = MethodChannel('com.clicker.pro/platform');
  bool _available = false;
  String? _unavailableReason;

  @override
  final VisionPluginInfo info = const VisionPluginInfo(
    id: 'builtin_windows_ocr',
    name: 'Windows OCR',
    description: 'Windows 内置文字识别引擎，需安装OCR语言包',
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
    if (!Platform.isWindows) {
      _available = false;
      _unavailableReason = '仅支持 Windows 平台';
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
    }
    try {
      final result = await _channel.invokeMethod<Map>('ocrRegion', [0, 0, 10, 10, 'en']);
      if (result != null) {
        _available = true;
        _unavailableReason = null;
        return true;
      }
    } on PlatformException catch (e) {
      if (e.code == 'OCR_NOT_AVAILABLE') {
        _available = false;
        _unavailableReason = '未安装OCR语言包，请在Windows设置中安装';
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
        error: _unavailableReason ?? 'Windows OCR 不可用',
      );
    }

    try {
      final result = await _channel.invokeMethod<Map>('ocrRegion', [x, y, w, h, language]);
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
        _unavailableReason = '未安装OCR语言包';
        return const VisionOcrResult(
          text: '',
          error: 'OCR不可用，请安装Windows OCR语言包',
        );
      }
      return VisionOcrResult(text: '', error: 'OCR 错误: ${e.message}');
    }
  }
}
