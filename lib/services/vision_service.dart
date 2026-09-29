
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'app_paths.dart';
import 'vision_plugin.dart';
import 'vision_plugin_manager.dart';

class VisionService {
  VisionService._();
  static final VisionService instance = VisionService._();

  static const _channel = MethodChannel('com.clicker.pro/platform');

  static final Expando<String> _templateKeys = Expando<String>();
  static final Set<String> _warmTemplates = <String>{};

  static String _templateKeyOf(TemplateData template) {
    final cached = _templateKeys[template];
    if (cached != null) return cached;
    var h = 0x811c9dc5;
    final px = template.pixels;
    for (var i = 0; i < px.length; i++) {
      h = ((h ^ px[i]) * 0x01000193) & 0xFFFFFFFF;
    }
    final key = 'v1:${template.width}x${template.height}:${h.toRadixString(16)}';
    _templateKeys[template] = key;
    return key;
  }

  final VisionPluginManager _pluginManager = VisionPluginManager.instance;

  VisionPluginManager get pluginManager => _pluginManager;

  List<VisionPlugin> getPluginsFor(VisionCapability cap) {
    return _pluginManager.getPluginsWithCapability(cap);
  }

  VisionPlugin? getPreferredPlugin(VisionCapability cap) {
    return _pluginManager.getPluginForCapability(cap);
  }

  Future<Uint8List?> captureScreenRect(int x, int y, int w, int h) async {
    try {
      final result = await _channel.invokeMethod<dynamic>('captureScreenRect', [x, y, w, h]);
      if (result == null) return null;
      if (result == true) {
        await Future.delayed(const Duration(milliseconds: 300));
        final retry = await _channel.invokeMethod<dynamic>('captureScreenRect', [x, y, w, h]);
        if (retry == null) return null;
        if (retry is Uint8List) return retry;
        if (retry is List) return Uint8List.fromList(retry.cast<int>());
        return null;
      }
      if (result is Uint8List) return result;
      if (result is List) return Uint8List.fromList(result.cast<int>());
      return null;
    } on PlatformException {
      return null;
    }
  }

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

  Future<TemplateData?> captureTemplate(int x, int y, int w, int h) async {
    final pixels = await captureScreenRect(x, y, w, h);
    if (pixels == null) {
      debugPrint('[captureTemplate] captureScreenRect返回null: ($x,$y,$w,$h)');
      return null;
    }
    debugPrint('[captureTemplate] 成功: ($x,$y,$w,$h) pixels=${pixels.length} expected=${w * h * 4}');
    return TemplateData(pixels: pixels, width: w, height: h);
  }

  Future<List<MatchResult>> findImageAll({
    required int regionX,
    required int regionY,
    required int regionW,
    required int regionH,
    required TemplateData template,
    double threshold = 0.8,
    int maxResults = 1,
    List<double>? scales,
    String? pluginId,
  }) async {
    final limit = maxResults < 1 ? 1 : maxResults;
    final multiScale = scales != null && scales.length > 1;

    if (!multiScale) {
      VisionPlugin? plugin;
      if (pluginId != null) {
        plugin = _pluginManager.getPlugin(pluginId);
        await _pluginManager.ensureInitialized(pluginId);
      } else {
        plugin = _pluginManager.getPluginForCapability(VisionCapability.templateMatch);
        if (plugin != null) await _pluginManager.ensureInitialized(plugin.info.id);
      }

      if (plugin != null && plugin.isAvailable) {
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
            maxResults: limit,
          ).timeout(const Duration(seconds: 15));
          final out = <MatchResult>[];
          for (final r in results) {
            if (r.score < threshold) continue;
            out.add(MatchResult(x: r.x, y: r.y, width: r.width, height: r.height, score: r.score));
            if (out.length >= limit) break;
          }
          return out;
        } catch (e) {
          debugPrint('[findImage] plugin异常: $e');
        }
      }
    }

    return _findImageDirect(
      regionX, regionY, regionW, regionH, template, threshold,
      maxResults: limit,
      scales: scales,
    );
  }

  Future<MatchResult?> findImage({
    required int regionX,
    required int regionY,
    required int regionW,
    required int regionH,
    required TemplateData template,
    double threshold = 0.8,
    String? pluginId,
  }) async {
    final all = await findImageAll(
      regionX: regionX,
      regionY: regionY,
      regionW: regionW,
      regionH: regionH,
      template: template,
      threshold: threshold,
      maxResults: 1,
      pluginId: pluginId,
    );
    return all.isEmpty ? null : all.first;
  }

  Future<List<MatchResult>> _findImageDirect(
    int regionX, int regionY, int regionW, int regionH,
    TemplateData template, double threshold, {
    int maxResults = 1,
    List<double>? scales,
  }) async {
    final tplKey = _templateKeyOf(template);

    Future<List<dynamic>?> invoke({required bool withPixels}) {
      return _channel.invokeMethod<List>('findImage', [
        regionX, regionY, regionW, regionH,
        withPixels ? template.pixels.toList() : null,
        template.width, template.height, threshold,
        maxResults,
        scales ?? const <double>[1.0],
        tplKey,
      ]);
    }

    List<dynamic>? result;
    try {
      final warm = _warmTemplates.contains(tplKey);
      result = await invoke(withPixels: !warm);
      if (!warm) _warmTemplates.add(tplKey);
    } on PlatformException catch (e) {
      if (e.code != 'TEMPLATE_NOT_CACHED') {
        debugPrint('[findImage] PlatformException: $e');
        return const <MatchResult>[];
      }
      _warmTemplates.remove(tplKey);
      try {
        result = await invoke(withPixels: true);
        _warmTemplates.add(tplKey);
      } on PlatformException catch (e2) {
        debugPrint('[findImage] PlatformException: $e2');
        return const <MatchResult>[];
      }
    }
    if (result == null || result.isEmpty) return const <MatchResult>[];

    final out = <MatchResult>[];
    for (final item in result) {
      if (item is! Map) continue;
      final score = (item['score'] as num?)?.toDouble() ?? 0.0;
      final matched = item['matched'] as bool? ?? (score >= threshold);
      final x = (item['x'] as num?)?.toInt() ?? -1;
      final y = (item['y'] as num?)?.toInt() ?? -1;
      if (!matched || x < 0 || y < 0 || score < threshold) continue;
      out.add(MatchResult(
        x: x,
        y: y,
        width: (item['width'] as num?)?.toInt() ?? template.width,
        height: (item['height'] as num?)?.toInt() ?? template.height,
        score: score,
      ));
    }
    return out;
  }

  Future<MatchResult?> waitForImage({
    required int regionX,
    required int regionY,
    required int regionW,
    required int regionH,
    required TemplateData template,
    double threshold = 0.8,
    int maxResults = 1,
    List<double>? scales,
    String? pluginId,
    Duration timeout = const Duration(seconds: 10),
    Duration interval = const Duration(milliseconds: 200),
  }) async {
    final deadline = DateTime.now().add(timeout);
    final step = interval.inMilliseconds < 20
        ? const Duration(milliseconds: 20)
        : interval;
    while (true) {
      final hits = await findImageAll(
        regionX: regionX,
        regionY: regionY,
        regionW: regionW,
        regionH: regionH,
        template: template,
        threshold: threshold,
        maxResults: maxResults,
        scales: scales,
        pluginId: pluginId,
      );
      if (hits.isNotEmpty) return hits.first;
      if (!DateTime.now().isBefore(deadline)) return null;
      await Future.delayed(step);
    }
  }

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
      return _ocrDirect(x, y, w, h, language);
    }

    OcrResult ocrResult;
    try {
      final result = await plugin.recognizeText(
        x: x, y: y, w: w, h: h, language: language,
      ).timeout(const Duration(seconds: 30));

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
      return _ocrDirect(x, y, w, h, language);
    }

    return ocrResult;
  }

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
        return const OcrResult(text: '', error: 'OCR不可用，请安装Windows OCR语言包');
      }
      return null;
    }
  }

  Future<List<OcrLine>> ocrLines({
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

    if (plugin != null && plugin.isAvailable) {
      try {
        final result = await plugin.recognizeText(
          x: x, y: y, w: w, h: h, language: language,
        ).timeout(const Duration(seconds: 30));
        if (result.lines.isNotEmpty) return result.lines;
        if (result.text.isNotEmpty) {
          return [
            OcrLine(
              text: result.text,
              x: result.x,
              y: result.y,
              width: result.width,
              height: result.height,
            ),
          ];
        }
        return const <OcrLine>[];
      } catch (e) {
        debugPrint('[ocrLines] plugin异常: $e');
      }
    }

    final fallback = await _ocrDirect(x, y, w, h, language);
    if (fallback == null || fallback.text.isEmpty) return const <OcrLine>[];
    return [
      OcrLine(
        text: fallback.text,
        x: fallback.x,
        y: fallback.y,
        width: fallback.width,
        height: fallback.height,
      ),
    ];
  }

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

  Future<VisionMatchResult?> findColor({
    required int regionX,
    required int regionY,
    required int regionW,
    required int regionH,
    required Color targetColor,
    int tolerance = 10,
    String? pluginId,
  }) async {
    VisionPlugin? plugin;
    if (pluginId != null) {
      plugin = _pluginManager.getPlugin(pluginId);
      await _pluginManager.ensureInitialized(pluginId);
    } else {
      plugin = _pluginManager.getPluginForCapability(VisionCapability.colorMatch);
      if (plugin != null) await _pluginManager.ensureInitialized(plugin.info.id);
    }

    if (plugin != null && plugin.isAvailable) {
      try {
        final hit = await plugin.findColor(
          regionX: regionX,
          regionY: regionY,
          regionW: regionW,
          regionH: regionH,
          targetColor: targetColor,
          tolerance: tolerance,
        ).timeout(const Duration(seconds: 10));
        if (hit != null) return hit;
      } catch (e) {
        debugPrint('[findColor] plugin异常: $e');
      }
    }

    if (regionW <= 0 || regionH <= 0) return null;
    final pixels = await captureScreenRect(regionX, regionY, regionW, regionH);
    if (pixels == null) return null;
    final tr = (targetColor.r * 255).round();
    final tg = (targetColor.g * 255).round();
    final tb = (targetColor.b * 255).round();
    for (var py = 0; py < regionH; py++) {
      for (var px = 0; px < regionW; px++) {
        final i = (py * regionW + px) * 4;
        if (i + 2 >= pixels.length) break;
        final b = pixels[i];
        final g = pixels[i + 1];
        final r = pixels[i + 2];
        if ((r - tr).abs() <= tolerance &&
            (g - tg).abs() <= tolerance &&
            (b - tb).abs() <= tolerance) {
          return VisionMatchResult(
            x: regionX + px,
            y: regionY + py,
            width: 1,
            height: 1,
            score: 1.0,
          );
        }
      }
    }
    return null;
  }

  Future<bool> startVisionClicker({
    required TemplateData template,
    double threshold = 0.85,
    int intervalMs = 500,
    int maxCount = 0,
    int maxDurationMs = 0,
  }) async {
    try {
      final result = await _channel.invokeMethod<bool>('startVisionClicker', [
        template.pixels.toList(),
        template.width,
        template.height,
        threshold,
        intervalMs,
        maxCount,
        maxDurationMs,
      ]);
      return result ?? false;
    } on PlatformException {
      return false;
    }
  }

  Future<bool> isScreenCaptureAvailable() async {
    try {
      final result = await _channel.invokeMethod<bool>('isScreenCaptureAvailable');
      return result ?? false;
    } on PlatformException {
      return false;
    }
  }

  Future<bool> requestScreenCapture() async {
    try {
      final result = await _channel.invokeMethod<bool>('requestScreenCapture');
      return result ?? false;
    } on PlatformException {
      return false;
    }
  }

  Future<void> stopVisionClicker() async {
    try {
      await _channel.invokeMethod<bool>('stopVisionClicker');
    } on PlatformException {
    }
  }

  Future<ElementDump> dumpElements({
    int maxDepth = 6,
    int maxElements = 400,
    int rootHwnd = 0,
  }) async {
    try {
      final result = await _channel.invokeMethod<Map>('dumpElements', [maxDepth, maxElements, rootHwnd]);
      if (result == null) return const ElementDump(elements: <UiElement>[]);
      final out = <UiElement>[];
      final raw = result['elements'];
      if (raw is List) {
        for (final item in raw) {
          if (item is! Map) continue;
          out.add(UiElement.fromMap(item));
        }
      }
      return ElementDump(
        elements: out,
        truncated: result['truncated'] as bool? ?? false,
      );
    } on PlatformException catch (e) {
      debugPrint('[dumpElements] PlatformException: $e');
      return ElementDump(elements: const <UiElement>[], error: e.message);
    }
  }

  static bool _blank(String? s) => s == null || s.trim().isEmpty;

  Future<UiElement?> findElement({
    String? name,
    String? automationId,
    String? className,
    String? controlType,
    int maxDepth = 6,
    int maxElements = 400,
    int rootHwnd = 0,
  }) async {
    if (_blank(name) &&
        _blank(automationId) &&
        _blank(className) &&
        _blank(controlType)) {
      return null;
    }
    final dump = await dumpElements(maxDepth: maxDepth, maxElements: maxElements, rootHwnd: rootHwnd);
    for (final el in dump.elements) {
      if (!el.hasBounds) continue;
      if (el.matches(name: name, automationId: automationId, className: className, controlType: controlType)) {
        return el;
      }
    }
    return null;
  }

  Future<UiElement?> waitForElement({
    String? name,
    String? automationId,
    String? className,
    String? controlType,
    int maxDepth = 6,
    int maxElements = 400,
    int rootHwnd = 0,
    Duration timeout = const Duration(seconds: 10),
    Duration interval = const Duration(milliseconds: 200),
  }) async {
    if (_blank(name) &&
        _blank(automationId) &&
        _blank(className) &&
        _blank(controlType)) {
      return null;
    }
    final step = interval.inMilliseconds < 20 ? const Duration(milliseconds: 20) : interval;
    final sw = Stopwatch()..start();
    while (true) {
      final el = await findElement(
        name: name,
        automationId: automationId,
        className: className,
        controlType: controlType,
        maxDepth: maxDepth,
        maxElements: maxElements,
        rootHwnd: rootHwnd,
      );
      if (el != null) return el;
      if (sw.elapsed >= timeout) return null;
      await Future<void>.delayed(step);
    }
  }

  Future<ScreenshotPng?> capturePng({
    required int x,
    required int y,
    required int w,
    required int h,
    int maxWidth = 0,
  }) async {
    try {
      final result = await _channel.invokeMethod<Map>('capturePng', [x, y, w, h, maxWidth]);
      return _pngFrom(result);
    } on PlatformException catch (e) {
      debugPrint('[capturePng] PlatformException: $e');
      return null;
    }
  }

  Future<ScreenshotPng?> captureAnnotatedPng({
    required int x,
    required int y,
    required int w,
    required int h,
    required List<MarkSpec> marks,
    int maxWidth = 0,
  }) async {
    try {
      final result = await _channel.invokeMethod<Map>('captureAnnotatedPng', [
        x, y, w, h,
        marks.map((m) => m.toMap()).toList(),
        maxWidth,
      ]);
      return _pngFrom(result);
    } on PlatformException catch (e) {
      debugPrint('[captureAnnotatedPng] PlatformException: $e');
      return null;
    }
  }

  ScreenshotPng? _pngFrom(Map? result) {
    if (result == null) return null;
    final raw = result['bytes'];
    final Uint8List? bytes = raw is Uint8List
        ? raw
        : (raw is List ? Uint8List.fromList(raw.cast<int>()) : null);
    if (bytes == null || bytes.isEmpty) return null;
    return ScreenshotPng(
      bytes: bytes,
      width: (result['width'] as num?)?.toInt() ?? 0,
      height: (result['height'] as num?)?.toInt() ?? 0,
      scale: (result['scale'] as num?)?.toDouble() ?? 1.0,
    );
  }

  Future<SetOfMarkResult?> setOfMark({
    int x = 0,
    int y = 0,
    int w = 0,
    int h = 0,
    int maxDepth = 6,
    int maxElements = 60,
    int maxWidth = 0,
    int rootHwnd = 0,
  }) async {
    var rx = x;
    var ry = y;
    var rw = w;
    var rh = h;
    if (rw <= 0 || rh <= 0) {
      final screen = await getScreenSize();
      if (screen == null) return null;
      rx = 0;
      ry = 0;
      rw = screen.width;
      rh = screen.height;
    }
    if (rw <= 0 || rh <= 0) return null;

    final dump = await dumpElements(maxDepth: maxDepth, maxElements: maxElements, rootHwnd: rootHwnd);
    final marked = <UiElement>[];
    final marks = <MarkSpec>[];
    for (final el in dump.elements) {
      if (!el.hasBounds || !el.markable) continue;
      if (el.x + el.width <= rx || el.y + el.height <= ry) continue;
      if (el.x >= rx + rw || el.y >= ry + rh) continue;
      marked.add(el);
      marks.add(MarkSpec(x: el.x, y: el.y, width: el.width, height: el.height, label: '${marked.length}'));
      if (marked.length >= maxElements) break;
    }

    final png = await captureAnnotatedPng(x: rx, y: ry, w: rw, h: rh, marks: marks, maxWidth: maxWidth);
    if (png == null) return null;
    return SetOfMarkResult(png: png, elements: marked, truncated: dump.truncated);
  }

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

class TemplateData {
  final Uint8List pixels;
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

class UiElement {
  final String name;
  final String automationId;
  final String className;
  final String controlType;
  final int controlTypeId;
  final int x;
  final int y;
  final int width;
  final int height;
  final bool enabled;
  final bool focused;
  final int hwnd;
  final int depth;

  const UiElement({
    required this.name,
    required this.automationId,
    required this.className,
    required this.controlType,
    required this.controlTypeId,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.enabled,
    required this.focused,
    required this.hwnd,
    required this.depth,
  });

  factory UiElement.fromMap(Map raw) => UiElement(
        name: (raw['name'] as String?) ?? '',
        automationId: (raw['automationId'] as String?) ?? '',
        className: (raw['className'] as String?) ?? '',
        controlType: (raw['controlType'] as String?) ?? '',
        controlTypeId: (raw['controlTypeId'] as num?)?.toInt() ?? 0,
        x: (raw['x'] as num?)?.toInt() ?? 0,
        y: (raw['y'] as num?)?.toInt() ?? 0,
        width: (raw['width'] as num?)?.toInt() ?? 0,
        height: (raw['height'] as num?)?.toInt() ?? 0,
        enabled: raw['enabled'] as bool? ?? true,
        focused: raw['focused'] as bool? ?? false,
        hwnd: (raw['hwnd'] as num?)?.toInt() ?? 0,
        depth: (raw['depth'] as num?)?.toInt() ?? 0,
      );

  int get centerX => x + width ~/ 2;
  int get centerY => y + height ~/ 2;
  bool get hasBounds => width > 0 && height > 0;

  bool get markable {
    if (name.isNotEmpty || automationId.isNotEmpty) return true;
    switch (controlType) {
      case 'Pane':
      case 'Group':
      case 'Custom':
      case 'Unknown':
      case 'Document':
        return false;
      default:
        return true;
    }
  }

  bool matches({String? name, String? automationId, String? className, String? controlType}) {
    if (name == null && automationId == null && className == null && controlType == null) return false;
    if (name != null && name.isNotEmpty && !this.name.toLowerCase().contains(name.toLowerCase())) return false;
    if (automationId != null && automationId.isNotEmpty && this.automationId != automationId) return false;
    if (className != null && className.isNotEmpty && this.className != className) return false;
    if (controlType != null && controlType.isNotEmpty && !this.controlType.toLowerCase().contains(controlType.toLowerCase())) {
      return false;
    }
    return true;
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'automationId': automationId,
        'className': className,
        'controlType': controlType,
        'x': x,
        'y': y,
        'width': width,
        'height': height,
        'centerX': centerX,
        'centerY': centerY,
        'enabled': enabled,
        'focused': focused,
        'hwnd': hwnd,
        'depth': depth,
      };
}

class ElementDump {
  final List<UiElement> elements;
  final bool truncated;
  final String? error;

  const ElementDump({required this.elements, this.truncated = false, this.error});

  bool get hasError => error != null;
}

class MarkSpec {
  final int x;
  final int y;
  final int width;
  final int height;
  final String label;

  const MarkSpec({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.label,
  });

  Map<String, dynamic> toMap() => {
        'x': x,
        'y': y,
        'width': width,
        'height': height,
        'label': label,
      };
}

class ScreenshotPng {
  final Uint8List bytes;
  final int width;
  final int height;
  final double scale;

  const ScreenshotPng({
    required this.bytes,
    required this.width,
    required this.height,
    this.scale = 1.0,
  });

  int get byteLength => bytes.length;
  String toBase64() => base64Encode(bytes);
}

class SetOfMarkResult {
  final ScreenshotPng png;
  final List<UiElement> elements;
  final bool truncated;

  const SetOfMarkResult({required this.png, required this.elements, this.truncated = false});
}
