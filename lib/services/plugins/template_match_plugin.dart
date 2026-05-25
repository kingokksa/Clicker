/// Built-in template matching plugin — uses C++ NCC algorithm via platform channel.
/// Available on all platforms (Windows, Linux, macOS).
library;

import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import '../vision_plugin.dart';

class TemplateMatchPlugin extends VisionPlugin {
  static const _channel = MethodChannel('com.clicker.pro/platform');
  bool _available = false;

  @override
  final VisionPluginInfo info = const VisionPluginInfo(
    id: 'builtin_template',
    name: '模板匹配',
    description: '基于像素对比的图像模板查找，无需额外依赖',
    version: '1.0.0',
    author: 'Clicker',
    capabilities: [VisionCapability.templateMatch],
    isBuiltin: true,
  );

  @override
  bool get isAvailable => _available;

  @override
  Future<bool> initialize() async {
    // Template matching is always available via C++ platform channel
    _available = Platform.isWindows || Platform.isLinux || Platform.isMacOS;
    return _available;
  }

  @override
  Future<void> dispose() async {
    _available = false;
  }

  @override
  Future<List<VisionMatchResult>> findTemplate({
    required int regionX,
    required int regionY,
    required int regionW,
    required int regionH,
    required Uint8List templatePixels,
    required int templateWidth,
    required int templateHeight,
    double threshold = 0.8,
    int maxResults = 1,
  }) async {
    if (!_available) return [];

    try {
      final tplBytes = templatePixels.toList();
      final result = await _channel.invokeMethod<List>('findImage', [
        regionX, regionY, regionW, regionH,
        tplBytes, templateWidth, templateHeight, threshold,
      ]);
      if (result == null || result.isEmpty) return [];

      return result.map((item) {
        final match = item as Map;
        return VisionMatchResult(
          x: match['x'] as int,
          y: match['y'] as int,
          width: match['width'] as int,
          height: match['height'] as int,
          score: (match['score'] as num).toDouble(),
        );
      }).toList();
    } on PlatformException {
      return [];
    }
  }
}
