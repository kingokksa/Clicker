/// Vision service — unified API for all image recognition operations.
/// Delegates to plugins via VisionPluginManager, while keeping screen capture
/// and overlay management as core (non-plugin) functionality.
library;

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
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
      return await _channel.invokeMethod<Uint8List>('captureScreenRect', [x, y, w, h]);
    } on PlatformException {
      return null;
    }
  }

  /// Save a screenshot of a screen region to a file
  Future<String?> saveScreenshot(int x, int y, int w, int h) async {
    try {
      final dir = await getApplicationSupportDirectory();
      final path = '${dir.path}\\screenshots';
      await Directory(path).create(recursive: true);
      final filePath = '$path\\${DateTime.now().millisecondsSinceEpoch}.bmp';
      await _channel.invokeMethod<bool>('saveScreenshot', [x, y, w, h, filePath]);
      return filePath;
    } on PlatformException {
      return null;
    }
  }

  /// Capture a screen region and return as template data (BGRA bytes + dimensions)
  Future<TemplateData?> captureTemplate(int x, int y, int w, int h) async {
    final pixels = await captureScreenRect(x, y, w, h);
    if (pixels == null) return null;
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

    final results = await plugin.findTemplate(
      regionX: regionX,
      regionY: regionY,
      regionW: regionW,
      regionH: regionH,
      templatePixels: template.pixels,
      templateWidth: template.width,
      templateHeight: template.height,
      threshold: threshold,
    );

    if (results.isEmpty) return null;
    final r = results.first;
    return MatchResult(x: r.x, y: r.y, width: r.width, height: r.height, score: r.score);
  }

  /// Direct platform channel fallback for template matching
  Future<MatchResult?> _findImageDirect(
    int regionX, int regionY, int regionW, int regionH,
    TemplateData template, double threshold,
  ) async {
    try {
      final tplBytes = template.pixels.toList();
      final result = await _channel.invokeMethod<List>('findImage', [
        regionX, regionY, regionW, regionH,
        tplBytes, template.width, template.height, threshold,
      ]);
      if (result == null || result.isEmpty) return null;
      final match = result.first as Map;
      return MatchResult(
        x: match['x'] as int,
        y: match['y'] as int,
        width: match['width'] as int,
        height: match['height'] as int,
        score: (match['score'] as num).toDouble(),
      );
    } on PlatformException {
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

    final result = await plugin.recognizeText(
      x: x, y: y, w: w, h: h, language: language,
    );

    return OcrResult(
      text: result.text,
      x: result.x,
      y: result.y,
      width: result.width,
      height: result.height,
      error: result.error,
    );
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
