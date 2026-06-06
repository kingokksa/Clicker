library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:archive/archive.dart';
import '../vision_plugin.dart';
import '../plugins/ai_tracker_plugin.dart';
import '../plugin_registry.dart';
import '../app_paths.dart';
import 'package:http/http.dart' as http;

class YoloDetectPlugin extends VisionPlugin {
  bool _available = false;

  @override
  final VisionPluginInfo info = const VisionPluginInfo(
    id: 'yolo_detect',
    name: 'YOLO目标检测',
    description: '基于ONNX Runtime的YOLO11n目标检测，需下载模型',
    version: '1.0.0',
    author: 'Clicker',
    capabilities: [VisionCapability.objectDetect],
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

    final aiPlugin = _getAiTrackerPlugin();
    if (aiPlugin == null) {
      debugPrint('[YoloDetectPlugin] AiTrackerPlugin未注册到PluginRegistry');
      _available = false;
      return false;
    }

    // 在加载原生插件之前，确保 onnxruntime.dll 存在
    if (!await _ensureOnnxRuntimeDll()) {
      debugPrint('[YoloDetectPlugin] ONNX Runtime DLL 不可用且下载失败');
      _available = false;
      return false;
    }

    // 确保模型文件存在
    if (await _findModelPath() == null) {
      debugPrint('[YoloDetectPlugin] YOLO模型文件未找到且下载失败');
      _available = false;
      return false;
    }

    if (!aiPlugin.nativeLoaded) {
      final loaded = await aiPlugin.loadNativeAsync();
      if (!loaded) {
        debugPrint('[YoloDetectPlugin] 原生插件(ai_tracker.dll)加载失败，请确认DLL已部署到插件目录');
        _available = false;
        return false;
      }
    }

    var statusResult = aiPlugin.executeAction('get_status', '{}', returnOnError: true);
    if (statusResult == null || statusResult.contains('"available":false')) {
      // 检查是否是版本不匹配（ort_lib=true但ort_api=false）
      final versionMismatch = statusResult != null &&
          statusResult.contains('"ort_lib":true') &&
          statusResult.contains('"ort_api":false');

      if (versionMismatch) {
        debugPrint('[YoloDetectPlugin] ONNX Runtime 版本过旧（API不匹配），尝试下载新版本...');
        final downloaded = await _downloadOnnxRuntime();
        if (downloaded) {
          // 卸载旧插件并重新加载
          aiPlugin.unloadNative();
          final reloaded = await aiPlugin.loadNativeAsync();
          if (reloaded) {
            statusResult = aiPlugin.executeAction('get_status', '{}', returnOnError: true);
            if (statusResult != null && !statusResult.contains('"available":false')) {
              debugPrint('[YoloDetectPlugin] ONNX Runtime 新版本加载成功');
              // 继续往下执行
            } else {
              debugPrint('[YoloDetectPlugin] 新版本加载后仍不可用: $statusResult，请重启应用');
              _available = false;
              return false;
            }
          } else {
            debugPrint('[YoloDetectPlugin] 下载新版本后重新加载失败，请重启应用');
            _available = false;
            return false;
          }
        } else {
          debugPrint('[YoloDetectPlugin] ONNX Runtime 新版本下载失败');
          _available = false;
          return false;
        }
      } else {
        debugPrint('[YoloDetectPlugin] ONNX Runtime 不可用: $statusResult');
        _available = false;
        return false;
      }
    }

    final modelLoaded = statusResult!.contains('"model_loaded":true');
    if (!modelLoaded) {
      final modelPath = await _findModelPath();
      if (modelPath == null) {
        debugPrint('[YoloDetectPlugin] YOLO模型文件未找到');
        _available = false;
        return false;
      }

      final loadParams = '{"model_path":"${modelPath.replaceAll('\\', '\\\\')}"}';
      final loadResult = aiPlugin.executeAction('load_model', loadParams, returnOnError: true);
      if (loadResult == null || loadResult.contains('"error"')) {
        debugPrint('[YoloDetectPlugin] 模型加载失败: $loadResult');
        _available = false;
        return false;
      }
      debugPrint('[YoloDetectPlugin] 模型加载成功: $modelPath');
    }

    _available = true;
    return true;
  }

  Future<String?> _findModelPath() async {
    final pluginDir = await AppPaths.getPluginDir('ai_tracker');
    final modelFile = File('$pluginDir${Platform.pathSeparator}models${Platform.pathSeparator}yolo11n.onnx');
    if (await modelFile.exists()) return modelFile.path;

    final exePath = Platform.resolvedExecutable;
    final exeDir = File(exePath).parent.path;
    final altModel = File('$exeDir${Platform.pathSeparator}data${Platform.pathSeparator}plugins${Platform.pathSeparator}ai_tracker${Platform.pathSeparator}models${Platform.pathSeparator}yolo11n.onnx');
    if (await altModel.exists()) return altModel.path;

    // 自动下载模型
    debugPrint('[YoloDetectPlugin] 模型文件未找到，尝试自动下载...');
    try {
      final modelsDir = Directory('$pluginDir${Platform.pathSeparator}models');
      if (!await modelsDir.exists()) await modelsDir.create(recursive: true);

      const modelUrl = 'https://github.com/ultralytics/assets/releases/download/v8.4.0/yolo11n.onnx';
      const mirrors = [
        '', // GitHub direct
        'https://ghfast.top/',
        'https://gh-proxy.com/',
        'https://ghproxy.net/',
      ];

      for (final mirror in mirrors) {
        try {
          final url = '${mirror}$modelUrl';
          debugPrint('[YoloDetectPlugin] 尝试从 $url 下载模型...');
          final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 60));
          if (response.statusCode == 200 && response.bodyBytes.length > 1000000) {
            await modelFile.writeAsBytes(response.bodyBytes);
            debugPrint('[YoloDetectPlugin] 模型下载成功: ${response.bodyBytes.length} bytes');
            return modelFile.path;
          }
        } catch (_) {}
      }
      debugPrint('[YoloDetectPlugin] 所有镜像源均下载失败');
    } catch (e) {
      debugPrint('[YoloDetectPlugin] 自动下载模型异常: $e');
    }

    return null;
  }

  Future<bool> _ensureOnnxRuntimeDll() async {
    // 检查多个可能的位置
    final pluginDir = await AppPaths.getPluginDir('ai_tracker');
    final sep = Platform.pathSeparator;

    final candidates = [
      '$pluginDir${sep}onnxruntime.dll',
    ];

    // 添加 exe 目录下的搜索路径
    final exePath = Platform.resolvedExecutable;
    final exeDir = File(exePath).parent.path;
    candidates.addAll([
      '$exeDir${sep}onnxruntime.dll',
      '$exeDir${sep}data${sep}plugins${sep}ai_tracker${sep}onnxruntime.dll',
    ]);

    for (final path in candidates) {
      if (await File(path).exists()) return true;
    }

    // 不存在则自动下载
    return await _downloadOnnxRuntime();
  }

  Future<bool> _downloadOnnxRuntime() async {
    try {
      final pluginDir = await AppPaths.getPluginDir('ai_tracker');
      const ortVersion = '1.21.0';
      const ortUrl = 'https://github.com/microsoft/onnxruntime/releases/download/v$ortVersion/onnxruntime-win-x64-$ortVersion.zip';
      const mirrors = [
        '', // GitHub direct
        'https://ghfast.top/',
        'https://gh-proxy.com/',
        'https://ghproxy.net/',
      ];

      for (final mirror in mirrors) {
        try {
          final url = '${mirror}$ortUrl';
          debugPrint('[YoloDetectPlugin] 尝试从 $url 下载 ONNX Runtime...');
          final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 120));
          if (response.statusCode == 200 && response.bodyBytes.length > 1000000) {
            // 解压zip找到onnxruntime.dll
            final archive = ZipDecoder().decodeBytes(response.bodyBytes);
            for (final file in archive) {
              if (file.isFile && file.name.endsWith('onnxruntime.dll')) {
                final data = file.content as List<int>;
                final dllPath = '$pluginDir${Platform.pathSeparator}onnxruntime.dll';
                await File(dllPath).writeAsBytes(data);
                debugPrint('[YoloDetectPlugin] ONNX Runtime 下载并解压成功: ${data.length} bytes');
                return true;
              }
            }
          }
        } catch (_) {}
      }
      debugPrint('[YoloDetectPlugin] 所有镜像源均下载ONNX Runtime失败');
    } catch (e) {
      debugPrint('[YoloDetectPlugin] 下载ONNX Runtime异常: $e');
    }
    return false;
  }

  @override
  Future<void> dispose() async {
    _available = false;
  }

  @override
  Future<List<VisionMatchResult>> detectObjects({
    required int regionX,
    required int regionY,
    required int regionW,
    required int regionH,
    String? targetLabel,
    double confidence = 0.5,
  }) async {
    if (!_available) return [];

    final aiPlugin = _getAiTrackerPlugin();
    if (aiPlugin == null || !aiPlugin.nativeLoaded) return [];

    try {
      final pixels = await _captureScreenRect(regionX, regionY, regionW, regionH);
      if (pixels == null || pixels.length < 4) {
        debugPrint('[YoloDetectPlugin] 截图失败: pixels=${pixels?.length ?? 0}');
        return [];
      }

      // captureScreenRect returns logical pixel data (DPI-adjusted), size = regionW * regionH * 4
      final expectedLen = regionW * regionH * 4;
      if (pixels.length != expectedLen) {
        debugPrint('[YoloDetectPlugin] 像素数据大小不匹配: got=${pixels.length} expected=$expectedLen');
        return [];
      }

      final pixelPtr = malloc<Uint8>(pixels.length);
      try {
        pixelPtr.asTypedList(pixels.length).setAll(0, pixels);

        final ptrHex = pixelPtr.address.toRadixString(16);
        final params = '{"region_w":$regionW,'
            '"region_h":$regionH,'
            '"confidence":$confidence,'
            '"pixel_data_ptr":"$ptrHex",'
            '"target_class":"${targetLabel ?? ''}"}';

        final resultJson = aiPlugin.executeAction('detect_objects', params, returnOnError: true);
        if (resultJson == null || resultJson.contains('"error"')) {
          debugPrint('[YoloDetectPlugin] detect_objects返回错误: $resultJson');
          return [];
        }

        return _parseResults(resultJson);
      } finally {
        malloc.free(pixelPtr);
      }
    } catch (e) {
      debugPrint('[YoloDetectPlugin] detectObjects异常: $e');
      return [];
    }
  }

  Future<Uint8List?> _captureScreenRect(int x, int y, int w, int h) async {
    const channel = MethodChannel('com.clicker.pro/platform');
    try {
      final result = await channel.invokeMethod<dynamic>('captureScreenRect', [x, y, w, h]);
      if (result == null) {
        debugPrint('[YoloDetectPlugin] captureScreenRect返回null, args=[$x,$y,$w,$h]');
        return null;
      }
      if (result is Uint8List) {
        debugPrint('[YoloDetectPlugin] captureScreenRect返回Uint8List len=${result.length}');
        return result;
      }
      if (result is List) {
        debugPrint('[YoloDetectPlugin] captureScreenRect返回List len=${result.length}');
        return Uint8List.fromList(result.cast<int>());
      }
      debugPrint('[YoloDetectPlugin] captureScreenRect返回类型异常: ${result.runtimeType}');
      return null;
    } catch (e) {
      debugPrint('[YoloDetectPlugin] captureScreenRect失败: $e');
      return null;
    }
  }

  List<VisionMatchResult> _parseResults(String jsonStr) {
    final results = <VisionMatchResult>[];
    try {
      final decoded = jsonDecode(jsonStr);
      if (decoded is! Map) return results;
      final detections = decoded['detections'];
      if (detections is! List) return results;

      for (final det in detections) {
        if (det is! Map) continue;
        results.add(VisionMatchResult(
          x: (det['x'] as num).toInt(),
          y: (det['y'] as num).toInt(),
          width: (det['w'] as num).toInt(),
          height: (det['h'] as num).toInt(),
          score: (det['confidence'] as num).toDouble(),
          label: det['class_name'] as String? ?? '',
        ));
      }
    } catch (_) {}
    return results;
  }

  AiTrackerPlugin? _getAiTrackerPlugin() {
    final registry = PluginRegistry.instance;
    final plugin = registry.getPlugin('ai_tracker');
    if (plugin is AiTrackerPlugin) return plugin;
    return null;
  }
}
