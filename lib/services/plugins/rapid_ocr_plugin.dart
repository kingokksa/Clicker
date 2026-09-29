import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../app_paths.dart';
import '../plugin/plugin_manager.dart';
import '../vision_plugin.dart';
import 'ai_tracker_plugin.dart';

class RapidOcrPlugin extends VisionPlugin {
  bool _available = false;

  static const String _detFile = 'ocr_det.onnx';
  static const String _recFile = 'ocr_rec.onnx';
  static const String _keysFile = 'ocr_keys.txt';
  static const double _detThreshold = 0.3;
  static const double _boxThreshold = 0.6;

  @override
  final VisionPluginInfo info = const VisionPluginInfo(
    id: 'rapid_ocr',
    name: 'RapidOCR 文字识别',
    description: '内置 PP-OCRv4 中英文识别，返回逐行文本与坐标',
    version: '1.0.0',
    author: 'Clicker',
    capabilities: [VisionCapability.ocr],
    isBuiltin: true,
  );

  @override
  bool get isAvailable => _available;

  @override
  Future<bool> initialize() async {
    if (!Platform.isWindows && !Platform.isLinux) {
      _available = false;
      return false;
    }

    final pm = PluginManager.instance;
    if (!pm.isEnabled('ai_tracker')) {
      await pm.enablePlugin('ai_tracker');
    }
    var aiDesc = pm.byId('ai_tracker');
    if (aiDesc != null && !aiDesc.isActive) {
      await pm.activatePlugin('ai_tracker');
      aiDesc = pm.byId('ai_tracker');
    }
    final aiPlugin = aiDesc?.dartInstance as AiTrackerPlugin?;
    if (aiPlugin == null) {
      debugPrint('[RapidOcrPlugin] AiTrackerPlugin 未安装或激活失败');
      _available = false;
      return false;
    }

    final modelsDir = await resolveModelsDir();
    if (modelsDir == null) {
      debugPrint('[RapidOcrPlugin] 内置 OCR 模型缺失，请确认安装包包含 models 目录');
      _available = false;
      return false;
    }

    if (!aiPlugin.nativeLoaded) {
      if (!await aiPlugin.loadNativeAsync()) {
        debugPrint('[RapidOcrPlugin] ai_tracker.dll 加载失败');
        _available = false;
        return false;
      }
    }

    final status = aiPlugin.executeAction('ocr_status', '{}', returnOnError: true);
    if (status != null && status.contains('"ocr_loaded":true')) {
      _available = true;
      return true;
    }

    if (!await loadModels(aiPlugin, modelsDir)) {
      _available = false;
      return false;
    }
    _available = true;
    return true;
  }

  Future<bool> loadModels(AiTrackerPlugin aiPlugin, String modelsDir) async {
    final sep = Platform.pathSeparator;
    final params = '{"det_path":"${_jsonPath('$modelsDir$sep$_detFile')}",'
        '"rec_path":"${_jsonPath('$modelsDir$sep$_recFile')}",'
        '"keys_path":"${_jsonPath('$modelsDir$sep$_keysFile')}",'
        '"box_threshold":$_boxThreshold}';
    final result = aiPlugin.executeAction('load_ocr_models', params, returnOnError: true);
    if (result == null || result.contains('"error"')) {
      debugPrint('[RapidOcrPlugin] OCR 模型加载失败: $result');
      return false;
    }
    debugPrint('[RapidOcrPlugin] OCR 模型加载成功: $modelsDir');
    return true;
  }

  static String _jsonPath(String path) => path.replaceAll('\\', '\\\\');

  static Future<String?> resolveModelsDir() async {
    final sep = Platform.pathSeparator;
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    final candidates = <String>[
      '$exeDir${sep}data${sep}plugins${sep}ai_tracker${sep}models',
      '$exeDir${sep}plugins${sep}ai_tracker${sep}models',
    ];
    try {
      candidates.add('${await AppPaths.getPluginDir('ai_tracker')}${sep}models');
    } catch (_) {}

    for (final dir in candidates) {
      final ok = await File('$dir$sep$_detFile').exists() &&
          await File('$dir$sep$_recFile').exists() &&
          await File('$dir$sep$_keysFile').exists();
      if (ok) return dir;
    }
    return null;
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
      return const VisionOcrResult(text: '', error: 'RapidOCR 不可用');
    }
    if (w <= 0 || h <= 0) {
      return const VisionOcrResult(text: '', error: '识别区域无效');
    }

    final aiPlugin = AiTrackerPlugin.activeInstance();
    if (aiPlugin == null || !aiPlugin.nativeLoaded) {
      return const VisionOcrResult(text: '', error: 'ai_tracker 原生库未加载');
    }

    final pixels = await _captureScreenRect(x, y, w, h);
    if (pixels == null || pixels.length < 4) {
      return const VisionOcrResult(text: '', error: '截图失败');
    }

    final size = _resolvePixelSize(pixels.length, w, h);
    final pixelPtr = malloc<Uint8>(pixels.length);
    try {
      pixelPtr.asTypedList(pixels.length).setAll(0, pixels);
      final params = '{"region_w":${size.$1},'
          '"region_h":${size.$2},'
          '"threshold":$_detThreshold,'
          '"box_threshold":$_boxThreshold,'
          '"pixel_data_ptr":"${pixelPtr.address.toRadixString(16)}"}';
      final resultJson = aiPlugin.executeAction('ocr_region', params, returnOnError: true);
      if (resultJson == null) {
        return const VisionOcrResult(text: '', error: 'OCR 调用失败');
      }
      if (resultJson.contains('"error"')) {
        final detail = resultJson.contains('result_too_large')
            ? '识别区域文本过多，请缩小范围'
            : resultJson;
        return VisionOcrResult(text: '', error: detail);
      }
      return _parseResult(resultJson, x, y, w, h);
    } finally {
      malloc.free(pixelPtr);
    }
  }

  static (int, int) _resolvePixelSize(int byteLength, int w, int h) {
    final pixelCount = byteLength ~/ 4;
    if (pixelCount == w * h) return (w, h);
    for (var tryW = w - 200; tryW <= w + 200; tryW++) {
      if (tryW <= 0 || pixelCount % tryW != 0) continue;
      final tryH = pixelCount ~/ tryW;
      if (tryH > 0 && (tryH / tryW - h / w).abs() < 0.05) return (tryW, tryH);
    }
    return (w, h);
  }

  VisionOcrResult _parseResult(String jsonStr, int regionX, int regionY, int regionW, int regionH) {
    try {
      final decoded = jsonDecode(jsonStr);
      if (decoded is! Map) {
        return const VisionOcrResult(text: '', error: 'OCR 结果格式异常');
      }
      final lines = <OcrLine>[];
      final rawLines = decoded['lines'];
      if (rawLines is List) {
        for (final item in rawLines) {
          if (item is! Map) continue;
          final text = item['text'] as String? ?? '';
          if (text.isEmpty) continue;
          lines.add(OcrLine(
            text: text,
            x: (item['x'] as num?)?.toInt() ?? 0,
            y: (item['y'] as num?)?.toInt() ?? 0,
            width: (item['width'] as num?)?.toInt() ?? 0,
            height: (item['height'] as num?)?.toInt() ?? 0,
          ));
        }
      }
      final fullText = decoded['text'] as String? ??
          lines.map((l) => l.text).join('\n');
      return VisionOcrResult(
        text: fullText,
        lines: lines,
        x: regionX,
        y: regionY,
        width: regionW,
        height: regionH,
      );
    } catch (e) {
      return VisionOcrResult(text: '', error: 'OCR 结果解析失败: $e');
    }
  }

  Future<Uint8List?> _captureScreenRect(int x, int y, int w, int h) async {
    const channel = MethodChannel('com.clicker.pro/platform');
    try {
      final result = await channel.invokeMethod<dynamic>('captureScreenRect', [x, y, w, h]);
      if (result is Uint8List) return result;
      if (result is List) return Uint8List.fromList(result.cast<int>());
      debugPrint('[RapidOcrPlugin] captureScreenRect 返回异常: ${result?.runtimeType}');
      return null;
    } catch (e) {
      debugPrint('[RapidOcrPlugin] captureScreenRect 失败: $e');
      return null;
    }
  }

  @override
  Future<void> dispose() async {
    _available = false;
  }
}
