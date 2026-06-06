library;

import 'dart:io';
import 'package:flutter/services.dart';
import '../vision_plugin.dart';

class PaddleOcrPlugin extends VisionPlugin {
  static const _channel = MethodChannel('com.clicker.pro/platform');
  bool _available = false;
  String? _unavailableReason;

  @override
  final VisionPluginInfo info = const VisionPluginInfo(
    id: 'plugin_paddle_ocr',
    name: 'PaddleOCR',
    description: '百度飞桨OCR引擎，中文识别精度高，需安装Python依赖',
    version: '1.0.0',
    author: 'Clicker',
    capabilities: [VisionCapability.ocr],
    isBuiltin: false,
  );

  @override
  bool get isAvailable => _available;

  String? get unavailableReason => _unavailableReason;

  @override
  Future<bool> initialize() async {
    if (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS) {
      _available = false;
      _unavailableReason = '仅支持桌面平台';
      return false;
    }
    try {
      final result = await _channel.invokeMethod<Map>('checkPaddleOcr');
      if (result != null && result['available'] == true) {
        _available = true;
        _unavailableReason = null;
        return true;
      }
    } on PlatformException {
      // Method not implemented yet
    }
    _available = false;
    _unavailableReason = 'PaddleOCR未安装，请安装Python依赖';
    return false;
  }

  @override
  Future<void> dispose() async {
    _available = false;
  }

  Future<bool> install() async {
    try {
      await _channel.invokeMethod<bool>('installPaddleOcr');
      return await initialize();
    } on PlatformException {
      return false;
    }
  }

  Future<void> uninstall() async {
    try {
      await _channel.invokeMethod<bool>('uninstallPaddleOcr');
    } on PlatformException {
      // ignore
    }
    _available = false;
    _unavailableReason = 'PaddleOCR未安装';
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
        error: _unavailableReason ?? 'PaddleOCR 不可用',
      );
    }

    try {
      final result = await _channel.invokeMethod<Map>('paddleOcrRegion', [x, y, w, h, language]);
      if (result == null) {
        return const VisionOcrResult(text: '', error: 'PaddleOCR 返回空结果');
      }
      final text = result['text'] as String? ?? '';
      final lines = <OcrLine>[];
      final lineList = result['lines'] as List?;
      if (lineList != null) {
        for (final line in lineList) {
          final lineMap = line as Map;
          lines.add(OcrLine(
            text: lineMap['text'] as String? ?? '',
            x: lineMap['x'] as int? ?? 0,
            y: lineMap['y'] as int? ?? 0,
            width: lineMap['width'] as int? ?? 0,
            height: lineMap['height'] as int? ?? 0,
          ));
        }
      }
      return VisionOcrResult(
        text: text,
        lines: lines,
        x: result['x'] as int? ?? x,
        y: result['y'] as int? ?? y,
        width: result['width'] as int? ?? w,
        height: result['height'] as int? ?? h,
      );
    } on PlatformException catch (e) {
      return VisionOcrResult(text: '', error: 'PaddleOCR 错误: ${e.message}');
    }
  }
}
