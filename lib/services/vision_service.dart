/// Vision service — unified API for all image recognition operations.
/// Delegates to plugins via VisionPluginManager, while keeping screen capture
/// and overlay management as core (non-plugin) functionality.
library;

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'app_paths.dart';
import 'vision_plugin.dart';
import 'vision_plugin_manager.dart';

class VisionService {
  static const _channel = MethodChannel('com.clicker.pro/platform');

  final VisionPluginManager _pluginManager = VisionPluginManager.instance;

  // ─── Plugin Access ────────────────────────────────────────

  /// Get the plugin manager for direct plugin access
  VisionPluginManager get pluginManager => _pluginManager;

  /// Get all available plugins for a capability
  List<VisionPlugin> getPluginsFor(VisionCapability cap) {
    return _pluginManager.getPluginsWithCapability(cap);
  }

  /// Get the preferred plugin for a capability (first available)
  VisionPlugin? getPreferredPlugin(VisionCapability cap) {
    return _pluginManager.getPluginForCapability(cap);
  }

  // ─── Screen Capture ───────────────────────────────────────

  /// Capture a screen region as raw BGRA pixel data
  Future<Uint8List?> captureScreenRect(int x, int y, int w, int h) async {
    try {
      final result = await _channel.invokeMethod<dynamic>('captureScreenRect', [x, y, w, h]);
      if (result == null) return null;
      if (result is Uint8List) return result;
      if (result is List) return Uint8List.fromList(result.cast<int>());
      return null;
    } on PlatformException {
      return null;
    }
  }

  /// Save a screenshot of a screen region to a file
  Future<String?> saveScreenshot(int x, int y, int w, int h) async {
    try {
      final dir = await AppPaths.getScreenshotsDir();
      final filePath = '$dir\\${DateTime.now().millisecondsSinceEpoch}.bmp';
      await _channel.invokeMethod<bool>('saveScreenshot', [x, y, w, h, filePath]);
      return filePath;
    } on PlatformException {
      return null;
    }
  }

  /// Capture a screen region and return as template data (BGRA bytes + dimensions)
  Future<TemplateData?> captureTemplate(int x, int y, int w, int h) async {
    final pixels = await captureScreenRect(x, y, w, h);
    if (pixels == null) {
      debugPrint('[captureTemplate] captureScreenRect返回null: ($x,$y,$w,$h)');
      return null;
    }
    debugPrint('[captureTemplate] 成功: ($x,$y,$w,$h) pixels=${pixels.length} expected=${w * h * 4}');
    return TemplateData(pixels: pixels, width: w, height: h);
  }

  // ─── Image Matching (via plugins) ─────────────────────────

  /// Find a template image within a screen region using the specified or preferred plugin
  Future<MatchResult?> findImage({
    required int regionX,
    required int regionY,
    required int regionW,
    required int regionH,
    required TemplateData template,
    double threshold = 0.8,
    String? pluginId,
  }) async {
    VisionPlugin? plugin;
    if (pluginId != null) {
      plugin = _pluginManager.getPlugin(pluginId);
      await _pluginManager.ensureInitialized(pluginId);
    } else {
      plugin = _pluginManager.getPluginForCapability(VisionCapability.templateMatch);
      if (plugin != null) await _pluginManager.ensureInitialized(plugin.info.id);
    }

    if (plugin == null || !plugin.isAvailable) {
      // Fallback to direct platform channel
      return _findImageDirect(regionX, regionY, regionW, regionH, template, threshold);
    }

    try {
      final results = await plugin.findTemplate(
        regionX: regionX,
        regionY: regionY,
        regionW: regionW,
        regionH: regionH,
        templatePixels: template.pixels,
        templateWidth: template.width,
        templateHeight: template.height,
        threshold: threshold,
      ).timeout(const Duration(seconds: 15));

      if (results.isEmpty) return null;
      final r = results.first;
      debugPrint('[findImage] plugin返回: score=${r.score} threshold=$threshold x=${r.x} y=${r.y}');
      if (r.score < threshold) {
        debugPrint('[findImage] plugin分数${r.score}低于阈值$threshold');
        return null;
      }
      return MatchResult(x: r.x, y: r.y, width: r.width, height: r.height, score: r.score);
    } catch (e) {
      debugPrint('[findImage] plugin异常: $e');
      return _findImageDirect(regionX, regionY, regionW, regionH, template, threshold);
    }
  }

  /// Direct platform channel fallback for template matching
  Future<MatchResult?> _findImageDirect(
    int regionX, int regionY, int regionW, int regionH,
    TemplateData template, double threshold,
  ) async {
    try {
      debugPrint('[findImage] 调用: region=($regionX,$regionY,$regionW,$regionH) tpl=(${template.width}x${template.height}) pixels=${template.pixels.length} threshold=$threshold');
      final tplBytes = template.pixels.toList();
      final result = await _channel.invokeMethod<List>('findImage', [
        regionX, regionY, regionW, regionH,
        tplBytes, template.width, template.height, threshold,
      ]);
      if (result == null || result.isEmpty) {
        debugPrint('[findImage] C++返回空');
        return null;
      }
      final match = result.first as Map;
      final score = (match['score'] as num).toDouble();
      final matched = match['matched'] as bool? ?? (score >= threshold);
      final x = match['x'] as int;
      final y = match['y'] as int;
      debugPrint('[findImage] C++返回: score=$score matched=$matched x=$x y=$y threshold=$threshold');
      if (!matched || x < 0) return null;
      if (score < threshold) {
        debugPrint('[findImage] 分数$score低于阈值$threshold，未匹配');
        return null;
      }
      return MatchResult(
        x: x,
        y: y,
        width: match['width'] as int,
        height: match['height'] as int,
        score: score,
      );
    } on PlatformException catch (e) {
      debugPrint('[findImage] PlatformException: $e');
      return null;
    }
  }

  // ─── OCR (via plugins) ────────────────────────────────────

  /// Perform OCR on a screen region using the specified or preferred plugin
  Future<OcrResult?> ocrRegion({
    required int x,
    required int y,
    required int w,
    required int h,
    String language = 'zh-Hans-CN',
    String? pluginId,
  }) async {
    VisionPlugin? plugin;
    if (pluginId != null) {
      plugin = _pluginManager.getPlugin(pluginId);
      await _pluginManager.ensureInitialized(pluginId);
    } else {
      plugin = _pluginManager.getPluginForCapability(VisionCapability.ocr);
      if (plugin != null) await _pluginManager.ensureInitialized(plugin.info.id);
    }

    if (plugin == null || !plugin.isAvailable) {
      // Fallback to direct platform channel
      return _ocrDirect(x, y, w, h, language);
    }

    OcrResult ocrResult;
    try {
      final result = await plugin.recognizeText(
        x: x, y: y, w: w, h: h, language: language,
      ).timeout(const Duration(seconds: 30));

      // If plugin returned an error, fall back to direct OCR
      if (result.error != null && result.error!.isNotEmpty) {
        return _ocrDirect(x, y, w, h, language);
      }

      ocrResult = OcrResult(
        text: result.text,
        x: result.x,
        y: result.y,
        width: result.width,
        height: result.height,
        error: result.error,
      );
    } catch (e) {
      // Plugin failed or timed out, try direct fallback
      return _ocrDirect(x, y, w, h, language);
    }

    return ocrResult;
  }

  /// Direct platform channel fallback for OCR
  Future<OcrResult?> _ocrDirect(int x, int y, int w, int h, String language) async {
    try {
      final result = await _channel.invokeMethod<Map>('ocrRegion', [x, y, w, h, language]);
      if (result == null) return null;
      return OcrResult(
        text: result['text'] as String? ?? '',
        x: result['x'] as int? ?? x,
        y: result['y'] as int? ?? y,
        width: result['width'] as int? ?? w,
        height: result['height'] as int? ?? h,
      );
    } on PlatformException catch (e) {
      if (e.code == 'OCR_NOT_AVAILABLE') {
        return OcrResult(text: '', error: 'OCR不可用，请安装Windows OCR语言包');
      }
      return null;
    }
  }

  // ─── Pixel Color ──────────────────────────────────────────

  /// Get pixel color at screen coordinates
  Future<Color?> getPixelColor(int x, int y) async {
    try {
      final result = await _channel.invokeMethod<Map>('getPixelColor', [x, y]);
      if (result != null) {
        return Color.fromARGB(255, result['r'] as int, result['g'] as int, result['b'] as int);
      }
    } on PlatformException {
      return null;
    }
    return null;
  }

  // ─── Screen Info ──────────────────────────────────────────

  /// Get screen size
  Future<({int width, int height})?> getScreenSize() async {
    try {
      final result = await _channel.invokeMethod<Map>('getScreenSize');
      if (result != null) {
        return (width: result['width'] as int, height: result['height'] as int);
      }
    } on PlatformException {
      return null;
    }
    return null;
  }
}

// ─── Data Classes ────────────────────────────────────────────

class TemplateData {
  final Uint8List pixels; // BGRA raw pixel data
  final int width;
  final int height;

  const TemplateData({required this.pixels, required this.width, required this.height});
}

class MatchResult {
  final int x;
  final int y;
  final int width;
  final int height;
  final double score;

  const MatchResult({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.score,
  });

  /// Center point of the match
  int get centerX => x + width ~/ 2;
  int get centerY => y + height ~/ 2;
}

class OcrResult {
  final String text;
  final int x;
  final int y;
  final int width;
  final int height;
  final String? error;

  const OcrResult({
    required this.text,
    this.x = 0,
    this.y = 0,
    this.width = 0,
    this.height = 0,
    this.error,
  });

  bool get hasError => error != null;
  bool get hasText => text.isNotEmpty;
}
