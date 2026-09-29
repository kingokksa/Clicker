
import 'dart:typed_data';
import 'dart:ui';

enum VisionCapability {
  templateMatch,
  ocr,
  objectDetect,
  colorMatch,
}

class VisionPluginInfo {
  final String id;
  final String name;
  final String description;
  final String version;
  final String author;
  final List<VisionCapability> capabilities;
  final bool isBuiltin;
  final bool requiresApiKey;
  final String? apiKeyLabel;

  const VisionPluginInfo({
    required this.id,
    required this.name,
    this.description = '',
    this.version = '1.0.0',
    this.author = '',
    required this.capabilities,
    this.isBuiltin = false,
    this.requiresApiKey = false,
    this.apiKeyLabel,
  });
}

class VisionMatchResult {
  final int x;
  final int y;
  final int width;
  final int height;
  final double score;
  final String? label;

  const VisionMatchResult({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.score,
    this.label,
  });

  int get centerX => x + width ~/ 2;
  int get centerY => y + height ~/ 2;
}

class VisionOcrResult {
  final String text;
  final List<OcrLine> lines;
  final int x;
  final int y;
  final int width;
  final int height;
  final String? error;

  const VisionOcrResult({
    required this.text,
    this.lines = const [],
    this.x = 0,
    this.y = 0,
    this.width = 0,
    this.height = 0,
    this.error,
  });

  bool get hasError => error != null;
  bool get hasText => text.isNotEmpty;
}

class OcrLine {
  final String text;
  final int x;
  final int y;
  final int width;
  final int height;

  const OcrLine({
    required this.text,
    this.x = 0,
    this.y = 0,
    this.width = 0,
    this.height = 0,
  });
}

abstract class VisionPlugin {
  VisionPluginInfo get info;

  bool get isAvailable;

  bool _enabled = true;
  bool get enabled => _enabled;
  set enabled(bool v) {
    _enabled = v;
    onEnabledChanged?.call(v);
  }

  void Function(bool)? onEnabledChanged;

  Future<bool> initialize();

  Future<void> dispose();


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
  }) async => [];


  Future<VisionOcrResult> recognizeText({
    required int x,
    required int y,
    required int w,
    required int h,
    String language = 'zh-Hans-CN',
  }) async => const VisionOcrResult(text: '');


  Future<List<VisionMatchResult>> detectObjects({
    required int regionX,
    required int regionY,
    required int regionW,
    required int regionH,
    String? targetLabel,
    double confidence = 0.5,
  }) async => [];


  Future<VisionMatchResult?> findColor({
    required int regionX,
    required int regionY,
    required int regionW,
    required int regionH,
    required Color targetColor,
    int tolerance = 10,
  }) async => null;

  Future<void> setApiKey(String key) async {}
}
