/// Vision plugin interface — defines the contract for all vision recognition plugins.
/// Each plugin implements specific recognition capabilities (template matching, OCR, AI, etc.)
library;

import 'dart:typed_data';
import 'dart:ui';

/// Capability flags for vision plugins
enum VisionCapability {
  templateMatch,  // Image template matching
  ocr,            // Optical character recognition
  objectDetect,   // Object detection (AI-based)
  colorMatch,     // Color matching
}

/// Metadata for a vision plugin
class VisionPluginInfo {
  final String id;           // Unique identifier, e.g. 'builtin_template'
  final String name;         // Display name, e.g. '模板匹配'
  final String description;  // Short description
  final String version;      // Plugin version
  final String author;       // Plugin author
  final List<VisionCapability> capabilities;
  final bool isBuiltin;      // Whether this is a built-in plugin
  final bool requiresApiKey; // Whether an API key is required
  final String? apiKeyLabel; // Label for API key field, e.g. 'API Key'

  const VisionPluginInfo({
    required this.id,
    required this.name,
    required this.description,
    this.version = '1.0.0',
    this.author = '',
    required this.capabilities,
    this.isBuiltin = false,
    this.requiresApiKey = false,
    this.apiKeyLabel,
  });
}

/// Result from a template match operation
class VisionMatchResult {
  final int x;
  final int y;
  final int width;
  final int height;
  final double score;
  final String? label;  // Optional label for AI-detected objects

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

/// Result from an OCR operation
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

/// A single line of OCR text with bounding box
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

/// Abstract interface for vision recognition plugins
///
/// Each plugin must implement:
/// - [info]: Plugin metadata
/// - [isAvailable]: Whether the plugin is ready to use
/// - [initialize]: Async initialization
/// - [dispose]: Cleanup resources
/// - Capability-specific methods (template match, OCR, etc.)
abstract class VisionPlugin {
  /// Plugin metadata
  VisionPluginInfo get info;

  /// Whether this plugin is currently available and ready to use
  bool get isAvailable;

  /// Whether this plugin is enabled by the user
  bool _enabled = true;
  bool get enabled => _enabled;
  set enabled(bool v) {
    _enabled = v;
    onEnabledChanged?.call(v);
  }

  /// Callback when enabled state changes
  void Function(bool)? onEnabledChanged;

  /// Initialize the plugin (load models, check dependencies, etc.)
  Future<bool> initialize();

  /// Dispose plugin resources
  Future<void> dispose();

  // ─── Template Matching ────────────────────────────────────

  /// Find a template image within a screen region.
  /// Returns list of matches sorted by score (best first).
  /// Only implemented if capability includes [VisionCapability.templateMatch].
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

  // ─── OCR ──────────────────────────────────────────────────

  /// Perform OCR on a screen region.
  /// Only implemented if capability includes [VisionCapability.ocr].
  Future<VisionOcrResult> recognizeText({
    required int x,
    required int y,
    required int w,
    required int h,
    String language = 'zh-Hans-CN',
  }) async => const VisionOcrResult(text: '');

  // ─── Object Detection ─────────────────────────────────────

  /// Detect objects in a screen region.
  /// Only implemented if capability includes [VisionCapability.objectDetect].
  Future<List<VisionMatchResult>> detectObjects({
    required int regionX,
    required int regionY,
    required int regionW,
    required int regionH,
    String? targetLabel,
    double confidence = 0.5,
  }) async => [];

  // ─── Color Matching ───────────────────────────────────────

  /// Find a color in a screen region.
  /// Only implemented if capability includes [VisionCapability.colorMatch].
  Future<VisionMatchResult?> findColor({
    required int regionX,
    required int regionY,
    required int regionW,
    required int regionH,
    required Color targetColor,
    int tolerance = 10,
  }) async => null;

  /// Set API key for plugins that require one
  Future<void> setApiKey(String key) async {}
}
