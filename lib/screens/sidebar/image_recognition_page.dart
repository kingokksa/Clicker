/// Image recognition page — screen monitoring, image search, OCR, conditional triggers.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../services/local_storage.dart';
import 'package:http/http.dart' as http;
import 'package:archive/archive.dart';
import '../../services/app_state.dart';
import '../../services/macro_service.dart';
import '../../services/screen_monitor_service.dart';
import '../../services/vision_service.dart';
import '../../services/vision_plugin.dart';
import '../../services/vision_plugin_manager.dart';
import '../../services/platform/windows_input.dart';
import '../../services/app_paths.dart';
import '../../widgets/app_slider.dart';
import '../../services/screen_overlay_service.dart';

/// COCO 80 classes: Chinese name → English name
const _cocoClasses = <MapEntry<String, String>>[
  MapEntry('人物', 'person'),
  MapEntry('自行车', 'bicycle'),
  MapEntry('汽车', 'car'),
  MapEntry('摩托车', 'motorcycle'),
  MapEntry('飞机', 'airplane'),
  MapEntry('公交车', 'bus'),
  MapEntry('火车', 'train'),
  MapEntry('卡车', 'truck'),
  MapEntry('船', 'boat'),
  MapEntry('红绿灯', 'traffic light'),
  MapEntry('消防栓', 'fire hydrant'),
  MapEntry('停车牌', 'stop sign'),
  MapEntry('停车计时器', 'parking meter'),
  MapEntry('长椅', 'bench'),
  MapEntry('鸟', 'bird'),
  MapEntry('猫', 'cat'),
  MapEntry('狗', 'dog'),
  MapEntry('马', 'horse'),
  MapEntry('羊', 'sheep'),
  MapEntry('牛', 'cow'),
  MapEntry('大象', 'elephant'),
  MapEntry('熊', 'bear'),
  MapEntry('斑马', 'zebra'),
  MapEntry('长颈鹿', 'giraffe'),
  MapEntry('背包', 'backpack'),
  MapEntry('雨伞', 'umbrella'),
  MapEntry('手提包', 'handbag'),
  MapEntry('领带', 'tie'),
  MapEntry('行李箱', 'suitcase'),
  MapEntry('飞盘', 'frisbee'),
  MapEntry('滑雪板', 'skis'),
  MapEntry('单板滑雪', 'snowboard'),
  MapEntry('运动球', 'sports ball'),
  MapEntry('风筝', 'kite'),
  MapEntry('棒球棒', 'baseball bat'),
  MapEntry('棒球手套', 'baseball glove'),
  MapEntry('滑板', 'skateboard'),
  MapEntry('冲浪板', 'surfboard'),
  MapEntry('网球拍', 'tennis racket'),
  MapEntry('瓶子', 'bottle'),
  MapEntry('酒杯', 'wine glass'),
  MapEntry('杯子', 'cup'),
  MapEntry('叉子', 'fork'),
  MapEntry('刀', 'knife'),
  MapEntry('勺子', 'spoon'),
  MapEntry('碗', 'bowl'),
  MapEntry('香蕉', 'banana'),
  MapEntry('苹果', 'apple'),
  MapEntry('三明治', 'sandwich'),
  MapEntry('橙子', 'orange'),
  MapEntry('西兰花', 'broccoli'),
  MapEntry('胡萝卜', 'carrot'),
  MapEntry('热狗', 'hot dog'),
  MapEntry('披萨', 'pizza'),
  MapEntry('甜甜圈', 'donut'),
  MapEntry('蛋糕', 'cake'),
  MapEntry('椅子', 'chair'),
  MapEntry('沙发', 'couch'),
  MapEntry('盆栽', 'potted plant'),
  MapEntry('床', 'bed'),
  MapEntry('餐桌', 'dining table'),
  MapEntry('马桶', 'toilet'),
  MapEntry('电视', 'tv'),
  MapEntry('笔记本电脑', 'laptop'),
  MapEntry('鼠标', 'mouse'),
  MapEntry('遥控器', 'remote'),
  MapEntry('键盘', 'keyboard'),
  MapEntry('手机', 'cell phone'),
  MapEntry('微波炉', 'microwave'),
  MapEntry('烤箱', 'oven'),
  MapEntry('烤面包机', 'toaster'),
  MapEntry('水槽', 'sink'),
  MapEntry('冰箱', 'refrigerator'),
  MapEntry('书', 'book'),
  MapEntry('时钟', 'clock'),
  MapEntry('花瓶', 'vase'),
  MapEntry('剪刀', 'scissors'),
  MapEntry('泰迪熊', 'teddy bear'),
  MapEntry('吹风机', 'hair drier'),
  MapEntry('牙刷', 'toothbrush'),
];

String _cocoEnToZh(String en) {
  for (final e in _cocoClasses) {
    if (e.value == en) return e.key;
  }
  return en;
}

String _cocoZhToEn(String zh) {
  for (final e in _cocoClasses) {
    if (e.key == zh) return e.value;
  }
  return zh;
}

class ImageRecognitionPage extends StatefulWidget {
  const ImageRecognitionPage({super.key});

  @override
  State<ImageRecognitionPage> createState() => _ImageRecognitionPageState();
}

class _ImageRecognitionPageState extends State<ImageRecognitionPage> {
  int _selectedTab = 0;
  final ScreenMonitorService _monitor = ScreenMonitorService();
  final VisionService _vision = VisionService();

  int _checkIntervalMs = 500;

  // OCR state (used by trigger textMatch)
  String _ocrLanguage = 'zh-Hans-CN';

  // OCR tools install state
  bool _tesseractInstalled = false;
  bool _pythonInstalled = false;
  bool _checkingTools = true;
  bool _installingTool = false;
  // bool _paddleOcrInstalled = false;  // PaddleOCR 暂时禁用
  // bool _checkingPaddleOcr = true;
  // bool _installingPaddleOcr = false;
  bool _initialized = false;

  // Conditional triggers
  final List<_TriggerEntry> _triggers = [];
  Timer? _triggerCheckTimer;
  final Map<String, DateTime> _triggerLastFired = {};
  final Map<String, VisionMatchResult> _lastDetectionResults = {};
  String? _highlightedTriggerId;
  final Map<String, String> _triggerStatus = {}; // trigger id -> last check status text
  final Map<String, DateTime> _triggerLastCheck = {}; // trigger id -> last check time

  static const _platformChannel = MethodChannel('com.clicker.pro/platform');

  StreamSubscription? _emergencyStopSub;

  @override
  void initState() {
    super.initState();
    _emergencyStopSub = AppState.onEmergencyStopSignal.listen((_) {
      if (_triggerRunning && mounted) {
        setState(() {
          _triggerRunning = false;
          _stopTriggerChecker();
        });
        debugPrint('[条件触发] 紧急停止');
      }
    });
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) _initAndLoad();
    });
  }

  Future<void> _initAndLoad() async {
    await _initPlugins();
    await _loadPersistedData();
    if (mounted) setState(() => _initialized = true);
  }

  Future<void> _initPlugins() async {
    await VisionPluginManager.registerBuiltinPlugins();
    // Deploy native plugin DLL before initializing (needed for YOLO)
    await _deployNativePluginIfNeeded();
    await _vision.pluginManager.initializeAll();
    if (mounted) setState(() {});
  }

  Future<void> _deployNativePluginIfNeeded() async {
    if (!Platform.isWindows && !Platform.isLinux) return;
    final dir = await AppPaths.getPluginDir('ai_tracker');
    final sep = Platform.pathSeparator;

    String platformDir;
    String libName;
    String libExt;
    if (Platform.isWindows) {
      platformDir = 'windows';
      libExt = '.dll';
      libName = 'ai_tracker';
    } else if (Platform.isLinux) {
      platformDir = 'linux';
      libExt = '.so';
      libName = 'libai_tracker';
    } else {
      return;
    }

    final targetDir = Directory('$dir$sep$platformDir');
    if (!await targetDir.exists()) await targetDir.create(recursive: true);

    final libDest = File('$dir$sep$platformDir$sep$libName$libExt');
    final manifestDest = File('$dir$sep${'manifest.json'}');

    final exePath = Platform.resolvedExecutable;
    final exeDir = File(exePath).parent.path;

    final libSources = [
      '$exeDir$sep${'plugins'}$sep${'ai_tracker'}$sep$platformDir$sep$libName$libExt',
      '$exeDir$sep${'data'}$sep${'plugins'}$sep${'ai_tracker'}$sep$platformDir$sep$libName$libExt',
      '$dir$sep$platformDir$sep$libName$libExt',
    ];

    final manifestSources = [
      '$exeDir$sep${'plugins'}$sep${'ai_tracker'}$sep${'manifest.json'}',
      '$exeDir$sep${'data'}$sep${'plugins'}$sep${'ai_tracker'}$sep${'manifest.json'}',
      '$dir$sep${'manifest.json'}',
    ];

    bool libOk = await libDest.exists();
    bool manifestOk = await manifestDest.exists();

    if (!libOk) {
      for (final src in libSources) {
        final srcFile = File(src);
        if (await srcFile.exists()) {
          try {
            await srcFile.copy(libDest.path);
            libOk = true;
            break;
          } catch (_) {}
        }
      }
    }

    if (!manifestOk) {
      for (final src in manifestSources) {
        final srcFile = File(src);
        if (await srcFile.exists()) {
          try {
            await srcFile.copy(manifestDest.path);
            manifestOk = true;
            break;
          } catch (_) {}
        }
      }
    }
  }

  // ─── Persistence ──────────────────────────────────────────
  static const _kTriggersKey = 'img_rec_triggers';

  Future<void> _loadPersistedData() async {
    final prefs = LocalStorage.instance;

    // Load triggers
    final triggersJson = prefs.getString(_kTriggersKey);
    if (triggersJson != null) {
      try {
        final list = jsonDecode(triggersJson) as List;
        for (final m in list) {
          _triggers.add(_TriggerEntry(
            id: m['id'] ?? '',
            name: m['name'] ?? '',
            conditionType: _TriggerConditionType.values.firstWhere(
              (e) => e.name == m['conditionType'], orElse: () => _TriggerConditionType.colorMatch),
            actionType: _TriggerActionType.values.firstWhere(
              (e) => e.name == m['actionType'], orElse: () => _TriggerActionType.click),
            enabled: m['enabled'] ?? true,
            x: m['x'] ?? 0, y: m['y'] ?? 0, w: m['w'] ?? 100, h: m['h'] ?? 100,
            matchThreshold: (m['matchThreshold'] as num?)?.toDouble() ?? 0.8,
            targetText: m['targetText'] ?? '',
            textMatchMode: _TextMatchMode.values.firstWhere(
              (e) => e.name == m['textMatchMode'], orElse: () => _TextMatchMode.fuzzy),
            targetObjectClass: m['targetObjectClass'] ?? '',
            detectConfidence: (m['detectConfidence'] as num?)?.toDouble() ?? 0.5,
            actionX: m['actionX'] ?? 0, actionY: m['actionY'] ?? 0,
            actionKey: m['actionKey'] ?? '',
            macroId: m['macroId'] ?? '',
            intervalMs: m['intervalMs'] ?? 500,
            showTrackingBox: m['showTrackingBox'] ?? true,
            templateData: () {
              final td = m['templateData'];
              if (td == null) return null;
              try {
                return TemplateData(
                  width: td['width'] as int,
                  height: td['height'] as int,
                  pixels: base64Decode(td['pixels'] as String),
                );
              } catch (_) { return null; }
            }(),
          ));
        }
      } catch (_) {}
    }

    if (mounted) setState(() {});
    // checkOcrTools now runs on a background thread in C++, so it won't block the UI.
    if (mounted && Platform.isWindows) _checkOcrTools();
    // if (mounted && Platform.isWindows) _checkPaddleOcr();  // PaddleOCR 暂时禁用
  }

  Future<void> _checkOcrTools() async {
    setState(() => _checkingTools = true);
    try {
      final results = await _platformChannel.invokeMethod<Map>('checkOcrTools');
      if (results != null && mounted) {
        setState(() {
          _tesseractInstalled = results['tesseract'] == true;
          _pythonInstalled = results['python'] == true;
          _checkingTools = false;
        });
      }
    } on PlatformException {
      if (mounted) setState(() => _checkingTools = false);
    }
  }

  // PaddleOCR 暂时禁用
  // Future<void> _checkPaddleOcr() async {
  //   setState(() => _checkingPaddleOcr = true);
  //   try {
  //     final results = await _platformChannel.invokeMethod<Map>('checkPaddleOcr');
  //     if (results != null && mounted) {
  //       setState(() {
  //         _paddleOcrInstalled = results['available'] == true;
  //         _checkingPaddleOcr = false;
  //       });
  //     }
  //   } on PlatformException {
  //     if (mounted) setState(() => _checkingPaddleOcr = false);
  //   }
  // }

  // Future<void> _installPaddleOcr() async {
  //   setState(() => _installingPaddleOcr = true);
  //   try {
  //     await _platformChannel.invokeMethod<bool>('installPaddleOcr');
  //     await _checkPaddleOcr();
  //     final paddlePlugin = _vision.pluginManager.getPlugin('plugin_paddle_ocr');
  //     if (paddlePlugin != null) {
  //       await _vision.pluginManager.ensureInitialized('plugin_paddle_ocr');
  //     }
  //   } on PlatformException {
  //     // Installation failed
  //   }
  //   if (mounted) setState(() => _installingPaddleOcr = false);
  // }

  // Future<void> _uninstallPaddleOcr() async {
  //   try {
  //     await _platformChannel.invokeMethod<bool>('uninstallPaddleOcr');
  //     await _checkPaddleOcr();
  //   } on PlatformException {
  //     // ignore
  //   }
  // }

  Future<void> _saveTriggers() async {
    final prefs = LocalStorage.instance;
    final list = _triggers.map((t) => {
      'id': t.id, 'name': t.name,
      'conditionType': t.conditionType.name,
      'actionType': t.actionType.name,
      'enabled': t.enabled,
      'x': t.x, 'y': t.y, 'w': t.w, 'h': t.h,
      'matchThreshold': t.matchThreshold,
      'targetText': t.targetText,
      'textMatchMode': t.textMatchMode.name,
      'targetObjectClass': t.targetObjectClass,
      'detectConfidence': t.detectConfidence,
      'actionX': t.actionX, 'actionY': t.actionY,
      'actionKey': t.actionKey, 'macroId': t.macroId, 'intervalMs': t.intervalMs,
      'showTrackingBox': t.showTrackingBox,
      if (t.templateData != null) 'templateData': {
        'width': t.templateData!.width,
        'height': t.templateData!.height,
        'pixels': base64Encode(t.templateData!.pixels),
      },
    }).toList();
    await prefs.setString(_kTriggersKey, jsonEncode(list));
  }

  // ─── Trigger Execution ────────────────────────────────────
  bool _triggerRunning = false; // user must explicitly start

  void _startTriggerChecker() {
    _triggerCheckTimer?.cancel();
    final enabledTriggers = _triggers.where((t) => t.enabled).toList();
    if (enabledTriggers.isEmpty) return;

    // Use user-configured interval, but enforce minimum based on trigger types
    int interval = _checkIntervalMs;
    final hasExpensiveTriggers = enabledTriggers.any((t) =>
      t.conditionType == _TriggerConditionType.imageMatch ||
      t.conditionType == _TriggerConditionType.textMatch ||
      t.conditionType == _TriggerConditionType.objectDetect);
    if (hasExpensiveTriggers && interval < 1000) interval = 1000;

    debugPrint('[条件触发] 启动检测: interval=${interval}ms, triggers=${enabledTriggers.length}');
    _triggerCheckTimer = Timer.periodic(Duration(milliseconds: interval), (_) => _checkTriggers());
  }

  void _stopTriggerChecker() {
    _triggerCheckTimer?.cancel();
    _triggerCheckTimer = null;
    ScreenOverlayService.instance.hideDetectionBoxes();
  }

  bool _checkingTriggers = false;

  Future<void> _checkTriggers() async {
    if (!_triggerRunning || _checkingTriggers) return;
    _checkingTriggers = true;
    try {
    final now = DateTime.now();
    for (final trigger in List.of(_triggers)) {
      if (!trigger.enabled) continue;

      // Debounce: don't fire more often than the trigger's interval
      final lastFired = _triggerLastFired[trigger.id];
      if (lastFired != null && now.difference(lastFired).inMilliseconds < trigger.intervalMs) continue;

      bool conditionMet = false;
      String statusText = '';
      try {
        switch (trigger.conditionType) {
          case _TriggerConditionType.colorMatch:
            final color = await _monitor.getPixelColor(trigger.x + trigger.w ~/ 2, trigger.y + trigger.h ~/ 2);
            if (color == null) continue;
            if (trigger.targetColor != null) {
              final diff = _colorDiff(color, trigger.targetColor!);
              conditionMet = diff < 40; // close enough to target color
            } else {
              // No target color: detect any change from initial color
              final lastColor = _triggerLastColors[trigger.id];
              if (lastColor == null) {
                _triggerLastColors[trigger.id] = color; // record initial
              } else {
                conditionMet = _colorDiff(color, lastColor) > 30;
                if (conditionMet) _triggerLastColors[trigger.id] = color; // update after trigger
              }
            }
            break;
          case _TriggerConditionType.colorChange:
            final color = await _monitor.getPixelColor(trigger.x + trigger.w ~/ 2, trigger.y + trigger.h ~/ 2);
            if (color == null) continue;
            final lastColor = _triggerLastColors[trigger.id];
            if (lastColor == null) {
              _triggerLastColors[trigger.id] = color; // record initial
            } else {
              final diff = _colorDiff(color, lastColor);
              if (diff > 30) {
                conditionMet = true;
                _triggerLastColors[trigger.id] = color; // update after change
              }
            }
            break;
          case _TriggerConditionType.colorDisappear:
            final color = await _monitor.getPixelColor(trigger.x + trigger.w ~/ 2, trigger.y + trigger.h ~/ 2);
            if (color == null) continue;
            if (trigger.targetColor != null) {
              final diff = _colorDiff(color, trigger.targetColor!);
              conditionMet = diff > 60; // target color is no longer present
            } else {
              // No target color: detect if region becomes very dark/white (likely disappeared)
              final brightness = (color.r * 0.299 + color.g * 0.587 + color.b * 0.114);
              final lastColor = _triggerLastColors[trigger.id];
              if (lastColor != null) {
                final lastBrightness = (lastColor.r * 0.299 + lastColor.g * 0.587 + lastColor.b * 0.114);
                conditionMet = (brightness - lastBrightness).abs() > 0.3;
              }
              _triggerLastColors[trigger.id] = color;
            }
            break;
          case _TriggerConditionType.imageMatch:
            if (trigger.templateData != null) {
              debugPrint('[图像匹配] 开始: region=(${trigger.x},${trigger.y},${trigger.w},${trigger.h}) tpl=(${trigger.templateData!.width}x${trigger.templateData!.height}) pixels=${trigger.templateData!.pixels.length} threshold=${trigger.matchThreshold}');
              final result = await _vision.findImage(
                regionX: trigger.x, regionY: trigger.y, regionW: trigger.w, regionH: trigger.h,
                template: trigger.templateData!,
                threshold: trigger.matchThreshold,
              );
              conditionMet = result != null;
              statusText = conditionMet ? '匹配成功 score=${result!.score.toStringAsFixed(2)}' : '未找到匹配';
              debugPrint('[图像匹配] 结果: $statusText');

              if (conditionMet && result != null) {
                _lastDetectionResults[trigger.id] = VisionMatchResult(
                  x: result.x, y: result.y, width: result.width, height: result.height, score: result.score,
                );
              }
            } else {
              debugPrint('[图像匹配] templateData为null');
            }
            break;
          case _TriggerConditionType.textMatch:
            if (trigger.targetText.isNotEmpty) {
              final ocrResult = await _vision.ocrRegion(
                x: trigger.x, y: trigger.y, w: trigger.w, h: trigger.h,
                language: _ocrLanguage,
              );
              if (ocrResult == null) {
                statusText = 'OCR不可用(返回null)';
              } else if (ocrResult.hasError && !ocrResult.hasText) {
                statusText = 'OCR错误: ${ocrResult.error}';
              } else if (!ocrResult.hasText) {
                statusText = '未识别到文字';
              } else {
                conditionMet = _matchText(ocrResult.text, trigger.targetText, trigger.textMatchMode);
                statusText = conditionMet ? '匹配成功: "${ocrResult.text}"' : '不匹配: 识别到"${ocrResult.text}"';
                if (conditionMet) {
                  _lastDetectionResults[trigger.id] = VisionMatchResult(
                    x: ocrResult.x, y: ocrResult.y, width: ocrResult.width, height: ocrResult.height, score: 1.0,
                  );
                }
              }
            } else {
              statusText = '未设置目标文字';
            }
            break;
          case _TriggerConditionType.objectDetect:
            final pluginManager = VisionPluginManager.instance;
            final detector = pluginManager.getPluginForCapability(VisionCapability.objectDetect);
            if (detector == null) {
              statusText = '无检测插件(需安装ONNX Runtime+模型)';
            } else if (!detector.isAvailable) {
              // Try initializing the plugin first
              final ok = await pluginManager.ensureInitialized(detector.info.id);
              if (!ok || !detector.isAvailable) {
                statusText = '检测插件不可用: ${detector.info.name}（请检查ONNX Runtime和模型是否已安装）';
              } else {
                final detections = await detector.detectObjects(
                  regionX: trigger.x, regionY: trigger.y, regionW: trigger.w, regionH: trigger.h,
                  targetLabel: trigger.targetObjectClass.isNotEmpty ? trigger.targetObjectClass : null,
                  confidence: trigger.detectConfidence,
                );
                conditionMet = detections.isNotEmpty;
                statusText = conditionMet ? '检测到${detections.length}个目标' : '未检测到目标';
                debugPrint('[条件触发] 目标检测: trigger=${trigger.name} found=${detections.length} met=$conditionMet');
                if (conditionMet && detections.isNotEmpty) {
                  _lastDetectionResults[trigger.id] = detections.first;
                  if (trigger.showTrackingBox) {
                    final boxes = detections.map((d) => {
                      'x': trigger.x + d.x,
                      'y': trigger.y + d.y,
                      'w': d.width,
                      'h': d.height,
                      'confidence': d.score,
                      'class_name': d.label ?? '',
                    }).toList();
                    ScreenOverlayService.instance.showDetectionBoxes(boxes);
                  }
                } else if (trigger.showTrackingBox) {
                  ScreenOverlayService.instance.hideDetectionBoxes();
                }
              }
            } else {
              await pluginManager.ensureInitialized(detector.info.id);
              final detections = await detector.detectObjects(
                regionX: trigger.x, regionY: trigger.y, regionW: trigger.w, regionH: trigger.h,
                targetLabel: trigger.targetObjectClass.isNotEmpty ? trigger.targetObjectClass : null,
                confidence: trigger.detectConfidence,
              );
              conditionMet = detections.isNotEmpty;
              statusText = conditionMet ? '检测到${detections.length}个目标' : '未检测到目标';
              debugPrint('[条件触发] 目标检测: trigger=${trigger.name} found=${detections.length} met=$conditionMet');
              if (conditionMet && detections.isNotEmpty) {
                _lastDetectionResults[trigger.id] = detections.first;
                if (trigger.showTrackingBox) {
                  final boxes = detections.map((d) => {
                    'x': trigger.x + d.x,
                    'y': trigger.y + d.y,
                    'w': d.width,
                    'h': d.height,
                    'confidence': d.score,
                    'class_name': d.label ?? '',
                  }).toList();
                  ScreenOverlayService.instance.showDetectionBoxes(boxes);
                }
              } else if (trigger.showTrackingBox) {
                ScreenOverlayService.instance.hideDetectionBoxes();
              }
            }
            break;
        }
      } catch (e) {
        statusText = '异常: $e';
        debugPrint('[条件触发] 检测异常 trigger=${trigger.name} type=${trigger.conditionType.name}: $e');
      }

      _triggerStatus[trigger.id] = statusText;
      _triggerLastCheck[trigger.id] = now;

      if (conditionMet) {
        _triggerLastFired[trigger.id] = now;
        await _executeTriggerAction(trigger);
      }
    }
    if (mounted) setState(() {});
    } finally {
      _checkingTriggers = false;
    }
  }

  final Map<String, Color> _triggerLastColors = {};

  double _colorDiff(Color a, Color b) {
    final dr = ((a.r - b.r) * 255).round().abs();
    final dg = ((a.g - b.g) * 255).round().abs();
    final db = ((a.b - b.b) * 255).round().abs();
    return (dr + dg + db) / 3.0;
  }

  void _highlightTriggerRegion(_TriggerEntry t) {
    // 仅更新UI状态，不使用overlay（overlay会拦截鼠标事件导致无法操作）
    setState(() => _highlightedTriggerId = t.id);
  }

  void _clearHighlight() {
    if (_highlightedTriggerId != null) {
      setState(() => _highlightedTriggerId = null);
    }
  }

  /// Normalize text for fuzzy matching: remove spaces, punctuation, and convert to lowercase
  static String _normalizeText(String text) {
    return text
      .replaceAll(RegExp(r'[\s\u3000]+'), '') // remove spaces (including full-width)
      .replaceAll(RegExp(r'[^\w\u4e00-\u9fff\u3040-\u309f\u30a0-\u30ff]+'), '') // keep letters, digits, CJK, kana
      .toLowerCase();
  }

  bool _matchText(String ocrText, String target, _TextMatchMode mode) {
    switch (mode) {
      case _TextMatchMode.contains:
        return ocrText.contains(target);
      case _TextMatchMode.notContains:
        return !ocrText.contains(target);
      case _TextMatchMode.equals:
        return ocrText.trim() == target.trim();
      case _TextMatchMode.regex:
        try {
          return RegExp(target).hasMatch(ocrText);
        } catch (_) {
          return false; // invalid regex
        }
      case _TextMatchMode.fuzzy:
        // Normalize both texts: remove spaces, punctuation, lowercase
        final normOcr = _normalizeText(ocrText);
        final normTarget = _normalizeText(target);
        if (normTarget.isEmpty) return false;
        return normOcr.contains(normTarget);
    }
  }

  Future<void> _executeTriggerAction(_TriggerEntry trigger) async {
    switch (trigger.actionType) {
      case _TriggerActionType.click:
        await _platformChannel.invokeMethod('sendClick', [trigger.actionX, trigger.actionY, 0]);
        break;
      case _TriggerActionType.clickTargetCenter:
        final det = _lastDetectionResults[trigger.id];
        if (det != null) {
          final cx = trigger.x + det.centerX;
          final cy = trigger.y + det.centerY;
          await _platformChannel.invokeMethod('sendClick', [cx, cy, 0]);
        }
        break;
      case _TriggerActionType.keyPress:
        if (trigger.actionKey.isNotEmpty) {
          await _platformChannel.invokeMethod('sendKeyPress', trigger.actionKey);
        }
        break;
      case _TriggerActionType.startClicker:
      case _TriggerActionType.stopClicker:
        // These would integrate with the main clicker functionality
        break;
      case _TriggerActionType.runMacro:
        if (trigger.macroId.isNotEmpty) {
          final state = context.read<AppState>();
          final macro = state.macros.where((m) => m.id == trigger.macroId).firstOrNull;
          if (macro != null) {
            final macroService = MacroService(WindowsInput());
            macroService.playMacro(macro);
          }
        }
        break;
    }
  }

  Future<(int, int, int, int)?> _startAreaSelect() async {
    return ScreenOverlayService.instance.startAreaSelect();
  }

  Future<(int, int)?> _startPick() async {
    return ScreenOverlayService.instance.startPick();
  }

  Future<TemplateData?> _captureTemplate() async {
    final sel = await _startAreaSelect();
    if (sel == null) return null;
    final (x1, y1, x2, y2) = sel;
    final w = x2 - x1;
    final h = y2 - y1;
    if (w < 5 || h < 5) return null;
    try {
      return await _vision.captureTemplate(x1, y1, w, h);
    } catch (_) {
      return null;
    }
  }

  @override
  void dispose() {
    _emergencyStopSub?.cancel();
    _stopTriggerChecker();
    ScreenOverlayService.instance.stopOverlay();
    _monitor.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = FluentTheme.of(context).brightness == Brightness.dark;

    if (!_initialized) {
      return ScaffoldPage(
        content: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(width: 32, height: 32, child: ProgressRing()),
          const SizedBox(height: 16),
          Text('正在初始化图像识别...', style: TextStyle(fontSize: 14, color: isDark ? const Color(0xFF9090B0) : const Color(0xFF6A6A7A))),
        ])),
      );
    }

    final state = context.watch<AppState>();

    return ScaffoldPage.scrollable(
      padding: const EdgeInsets.all(20),
      children: [
        // Header
        Row(children: [
          Icon(FluentIcons.image_pixel, size: 20, color: state.accentColor),
          const SizedBox(width: 10),
          const Text('图像识别', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 16),

        // Tab selector
        Row(children: [
          _tabChip('条件触发', _selectedTab == 0, () => setState(() => _selectedTab = 0)),
          const SizedBox(width: 6),
          _tabChip('高级模型', _selectedTab == 1, () => setState(() => _selectedTab = 1)),
        ]),
        const SizedBox(height: 16),

        if (_selectedTab == 0) ..._buildTriggers(isDark, state),
        if (_selectedTab == 1) const _AdvancedModelsTab(),
      ],
    );
  }

  Widget _tabChip(String label, bool selected, VoidCallback onTap) {
    final isDark = FluentTheme.of(context).brightness == Brightness.dark;
    final accent = FluentTheme.of(context).accentColor;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? accent.withValues(alpha: 0.15) : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: selected ? accent : (isDark ? const Color(0xFF404060) : const Color(0xFFD0D0D8))),
          ),
          child: Text(label, style: TextStyle(
            fontSize: 13, fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
            color: selected ? accent : (isDark ? const Color(0xFFC0C0D8) : const Color(0xFF5A5A70)),
          )),
        ),
      ),
    );
  }

  // ─── Conditional Triggers ──────────────────────────────────

  List<Widget> _buildTriggers(bool isDark, AppState state) {
    final cardBg = isDark ? const Color(0xFF252540).withValues(alpha: 0.5) : const Color(0xFFF0F0FA).withValues(alpha: 0.5);
    final ocrPlugins = _vision.getPluginsFor(VisionCapability.ocr);
    return [
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: isDark ? const Color(0xFF303050) : const Color(0xFFD0D0E0)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(FluentIcons.process_meta_task, size: 16, color: state.accentColor),
            const SizedBox(width: 8),
            const Text('条件触发监控', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            const Spacer(),
            if (_triggerRunning)
              FilledButton(
                style: ButtonStyle(backgroundColor: WidgetStateProperty.all(Colors.red)),
                onPressed: () { setState(() { _triggerRunning = false; _stopTriggerChecker(); }); },
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(FluentIcons.stop, size: 12),
                  SizedBox(width: 4),
                  Text('停止'),
                ]),
              )
            else
              FilledButton(
                onPressed: _triggers.isEmpty ? null : () {
                  setState(() { _triggerRunning = true; });
                  _startTriggerChecker();
                },
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(FluentIcons.play, size: 12),
                  SizedBox(width: 4),
                  Text('启动'),
                ]),
              ),
            if (_triggerRunning) ...[
              const SizedBox(width: 8),
              Container(width: 8, height: 8, decoration: BoxDecoration(color: const Color(0xFF00E676), borderRadius: BorderRadius.circular(4))),
              const SizedBox(width: 4),
              Text('检测中', style: TextStyle(fontSize: 11, color: const Color(0xFF00E676))),
            ],
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Icon(FluentIcons.speed_high, size: 12, color: isDark ? const Color(0xFF9090B0) : const Color(0xFF8A8A9A)),
            const SizedBox(width: 4),
            const Text('间隔:', style: TextStyle(fontSize: 12)),
            const SizedBox(width: 4),
            ComboBox<String>(
              items: ['100ms', '200ms', '500ms', '1000ms', '2000ms'].map((l) => ComboBoxItem(value: l, child: Text(l))).toList(),
              value: ['100ms', '200ms', '500ms', '1000ms', '2000ms'].contains('${_checkIntervalMs}ms') ? '${_checkIntervalMs}ms' : '500ms',
              onChanged: (v) {
                if (v != null) {
                  setState(() => _checkIntervalMs = int.parse(v.replaceAll('ms', '')));
                  if (_triggerRunning) _startTriggerChecker();
                }
              },
            ),
            const Spacer(),
            ...ocrPlugins.map((p) => Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: p.isAvailable ? const Color(0xFF00E676).withValues(alpha: 0.12) : Colors.grey.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: p.isAvailable ? const Color(0xFF00E676).withValues(alpha: 0.3) : Colors.grey.withValues(alpha: 0.3)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(p.info.isBuiltin ? FluentIcons.puzzle : FluentIcons.download, size: 10,
                    color: p.isAvailable ? const Color(0xFF00E676) : Colors.grey),
                  const SizedBox(width: 3),
                  Text(p.info.name, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600,
                    color: p.isAvailable ? const Color(0xFF00E676) : Colors.grey)),
                ]),
              ),
            )),
          ]),
          // PaddleOCR 暂时禁用
          // if (Platform.isWindows && !_paddleOcrInstalled && !_checkingPaddleOcr) ...[
          //   const SizedBox(height: 8),
          //   Row(children: [
          //     const Icon(FluentIcons.info, size: 12, color: Color(0xFFFF9800)),
          //     const SizedBox(width: 4),
          //     Expanded(child: Text('安装 PaddleOCR 可提升中文识别精度，在「高级模型」中安装', style: const TextStyle(fontSize: 11, color: Color(0xFFFF9800)))),
          //   ]),
          // ] else if (Platform.isWindows && _paddleOcrInstalled) ...[
          //   const SizedBox(height: 8),
          //   Row(children: [
          //     const Icon(FluentIcons.completed, size: 12, color: Color(0xFF00E676)),
          //     const SizedBox(width: 4),
          //     const Expanded(child: Text('PaddleOCR 已就绪', style: TextStyle(fontSize: 11, color: Color(0xFF00E676)))),
          //   ]),
          // ] else if (Platform.isWindows && _checkingPaddleOcr) ...[
          //   const SizedBox(height: 8),
          //   const Row(children: [
          //     SizedBox(width: 12, height: 12, child: ProgressRing()),
          //     SizedBox(width: 4),
          //     Text('正在检测PaddleOCR...', style: TextStyle(fontSize: 11, color: Colors.grey)),
          //   ]),
          // ],
        ]),
      ),
      const SizedBox(height: 10),

      SizedBox(width: double.infinity, child: Button(onPressed: () => _addTrigger(isDark, state), child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Icon(FluentIcons.add, size: 14),
        const SizedBox(width: 6),
        const Text('添加触发条件'),
      ]))),
      const SizedBox(height: 10),

      if (_triggers.isEmpty)
        Center(child: Padding(padding: const EdgeInsets.all(40), child: Column(children: [
          Container(
            width: 64, height: 64,
            decoration: BoxDecoration(
              color: state.accentColor.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(FluentIcons.process_meta_task, size: 28, color: state.accentColor.withValues(alpha: 0.5)),
          ),
          const SizedBox(height: 16),
          const Text('暂无触发条件', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
          const SizedBox(height: 4),
          Text('点击上方按钮添加条件触发规则', style: TextStyle(fontSize: 12, color: isDark ? const Color(0xFF9090B0) : const Color(0xFF8A8A9A))),
        ])))
      else
        ..._triggers.map((t) {
          final condColor = _conditionColor(t.conditionType);
          final condIcon = _conditionIcon(t.conditionType);
          final isHighlighted = _highlightedTriggerId == t.id;
          return MouseRegion(
            onEnter: (_) => _highlightTriggerRegion(t),
            onExit: (_) => _clearHighlight(),
            child: Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Container(
                decoration: BoxDecoration(
                  color: isHighlighted ? condColor.withValues(alpha: 0.08) : cardBg,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: isHighlighted ? condColor : (isDark ? const Color(0xFF303050) : const Color(0xFFD0D0E0)), width: isHighlighted ? 1.5 : 1),
                ),
                child: IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        width: 4,
                        margin: const EdgeInsets.all(1),
                        decoration: BoxDecoration(
                          color: condColor,
                          borderRadius: const BorderRadius.horizontal(left: Radius.circular(7)),
                        ),
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(children: [
                                Icon(condIcon, size: 14, color: condColor),
                                const SizedBox(width: 6),
                                Expanded(child: Text(t.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                                ToggleSwitch(checked: t.enabled, onChanged: (v) { setState(() => t.enabled = v); _saveTriggers(); if (_triggerRunning) _startTriggerChecker(); }),
                                const SizedBox(width: 4),
                                IconButton(icon: Icon(FluentIcons.edit, size: 12, color: state.accentColor), onPressed: () async {
                                  final result = await showDialog<_TriggerConfig>(context: context, builder: (_) => _AddTriggerDialog(
                                    initialX: t.x, initialY: t.y, initialW: t.w, initialH: t.h,
                                    onPickActionPos: _startPick,
                                    onCaptureTemplate: _captureTemplate,
                                    initialTrigger: t,
                                  ));
                                  if (result != null) {
                                    setState(() {
                                      final idx = _triggers.indexOf(t);
                                      if (idx >= 0) {
                                        _triggers[idx] = _TriggerEntry(
                                          id: t.id,
                                          name: result.name,
                                          conditionType: result.conditionType,
                                          actionType: result.actionType,
                                          enabled: t.enabled,
                                          x: result.x, y: result.y, w: result.w, h: result.h,
                                          targetColor: result.targetColor,
                                          templateData: result.templateData,
                                          matchThreshold: result.matchThreshold,
                                          targetText: result.targetText,
                                          textMatchMode: result.textMatchMode,
                                          targetObjectClass: result.targetObjectClass,
                                          detectConfidence: result.detectConfidence,
                                          actionX: result.actionX, actionY: result.actionY,
                                          actionKey: result.actionKey,
                                          macroId: result.macroId,
                                          intervalMs: result.intervalMs,
                                          showTrackingBox: result.showTrackingBox,
                                        );
                                      }
                                    });
                                    _saveTriggers();
                                    if (_triggerRunning) _startTriggerChecker();
                                  }
                                }),
                                const SizedBox(width: 2),
                                IconButton(icon: Icon(FluentIcons.delete, size: 12, color: Colors.red.withValues(alpha: 0.7)), onPressed: () {
                                  setState(() => _triggers.remove(t));
                                  _saveTriggers();
                                  if (_triggerRunning) _startTriggerChecker();
                                }),
                              ]),
                              const SizedBox(height: 6),
                              Wrap(spacing: 8, runSpacing: 4, children: [
                                _conditionChip(t.conditionType.label, isDark, condColor),
                                _actionChip(t.actionType.label, isDark),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: (isDark ? const Color(0xFF9090B0) : const Color(0xFF8A8A9A)).withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text('(${t.x}, ${t.y}) ${t.w}x${t.h}', style: TextStyle(fontSize: 10, color: isDark ? const Color(0xFF9090B0) : const Color(0xFF8A8A9A))),
                                ),
                              ]),
                              if (t.targetColor != null) ...[
                                const SizedBox(height: 4),
                                Row(children: [
                                  const Text('目标色:', style: TextStyle(fontSize: 11)),
                                  const SizedBox(width: 4),
                                  Container(width: 14, height: 14, decoration: BoxDecoration(
                                    color: t.targetColor,
                                    borderRadius: BorderRadius.circular(3),
                                    border: Border.all(color: isDark ? const Color(0xFF404060) : const Color(0xFFD0D0D8)),
                                  )),
                                ]),
                              ],
                              if (t.conditionType == _TriggerConditionType.imageMatch) ...[
                                const SizedBox(height: 4),
                                Row(children: [
                                  const Text('模板:', style: TextStyle(fontSize: 11)),
                                  const SizedBox(width: 4),
                                  Icon(FluentIcons.image_pixel, size: 11, color: t.templateData != null ? const Color(0xFF00E676) : Colors.grey),
                                  const SizedBox(width: 3),
                                  Text(t.templateData != null ? '${t.templateData!.width}x${t.templateData!.height}' : '未设置',
                                    style: TextStyle(fontSize: 11, color: t.templateData != null ? const Color(0xFF00E676) : Colors.grey)),
                                  const SizedBox(width: 8),
                                  const Text('阈值:', style: TextStyle(fontSize: 11)),
                                  const SizedBox(width: 2),
                                  Text('${(t.matchThreshold * 100).toStringAsFixed(0)}%', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                                ]),
                              ],
                              if (t.conditionType == _TriggerConditionType.textMatch) ...[
                                const SizedBox(height: 4),
                                Row(children: [
                                  const Text('文字:', style: TextStyle(fontSize: 11)),
                                  const SizedBox(width: 4),
                                  Text(t.targetText.isNotEmpty ? '"${t.targetText}" [${t.textMatchMode.label}]' : '未设置',
                                    style: TextStyle(fontSize: 11, color: t.targetText.isNotEmpty ? const Color(0xFF00BCD4) : Colors.grey)),
                                ]),
                              ],
                              if (t.conditionType == _TriggerConditionType.objectDetect) ...[
                                const SizedBox(height: 4),
                                Row(children: [
                                  const Text('目标:', style: TextStyle(fontSize: 11)),
                                  const SizedBox(width: 4),
                                  Text(t.targetObjectClass.isNotEmpty ? _cocoEnToZh(t.targetObjectClass) : '所有目标',
                                    style: const TextStyle(fontSize: 11, color: Color(0xFFE040FB))),
                                  const SizedBox(width: 8),
                                  const Text('置信度:', style: TextStyle(fontSize: 11)),
                                  const SizedBox(width: 2),
                                  Text('${(t.detectConfidence * 100).toStringAsFixed(0)}%', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                                ]),
                              ],
                              if (t.actionType == _TriggerActionType.click)
                                Padding(padding: const EdgeInsets.only(top: 4), child: Text('→ 点击 (${t.actionX}, ${t.actionY})', style: TextStyle(fontSize: 11, color: isDark ? const Color(0xFF9090B0) : const Color(0xFF8A8A9A))))
                              else if (t.actionType == _TriggerActionType.clickTargetCenter)
                                const Padding(padding: EdgeInsets.only(top: 4), child: Text('→ 点击检测目标中心', style: TextStyle(fontSize: 11, color: Color(0xFFFF5252))))
                              else if (t.actionType == _TriggerActionType.keyPress)
                                Padding(padding: const EdgeInsets.only(top: 4), child: Text('→ 按键 ${t.actionKey}', style: TextStyle(fontSize: 11, color: isDark ? const Color(0xFF9090B0) : const Color(0xFF8A8A9A))))
                              else if (t.actionType == _TriggerActionType.runMacro)
                                Padding(padding: const EdgeInsets.only(top: 4), child: Builder(builder: (context) {
                                  final macro = context.read<AppState>().macros.where((m) => m.id == t.macroId).firstOrNull;
                                  return Text(macro != null ? '→ 宏: ${macro.name}' : '→ 宏未找到', style: TextStyle(fontSize: 11, color: isDark ? const Color(0xFF9090B0) : const Color(0xFF8A8A9A)));
                                }))
                              else if (t.actionType == _TriggerActionType.startClicker)
                                const Padding(padding: EdgeInsets.only(top: 4), child: Text('→ 启动连点', style: TextStyle(fontSize: 11)))
                              else if (t.actionType == _TriggerActionType.stopClicker)
                                const Padding(padding: EdgeInsets.only(top: 4), child: Text('→ 停止连点', style: TextStyle(fontSize: 11))),
                              const SizedBox(height: 4),
                              Row(children: [
                                const Text('间隔:', style: TextStyle(fontSize: 11)),
                                const SizedBox(width: 2),
                                Text('${t.intervalMs}ms', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                                const SizedBox(width: 4),
                                Expanded(child: AppSlider(
                                  value: t.intervalMs.toDouble(),
                                  min: 100, max: 5000, divisions: 49,
                                  label: '${t.intervalMs}ms',
                                  onChanged: (v) => setState(() => t.intervalMs = v.round()),
                                )),
                              ]),
                              if (_triggerRunning && _triggerStatus.containsKey(t.id)) ...[
                                const SizedBox(height: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: (isDark ? const Color(0xFF1A1A30) : const Color(0xFFF5F5FA)),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Row(children: [
                                    Icon(FluentIcons.info, size: 10, color: isDark ? const Color(0xFF9090B0) : const Color(0xFF8A8A9A)),
                                    const SizedBox(width: 4),
                                    Expanded(child: Text(_triggerStatus[t.id]!, style: TextStyle(fontSize: 10, color: isDark ? const Color(0xFF9090B0) : const Color(0xFF8A8A9A)))),
                                  ]),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }),
    ];
  }

  Color _conditionColor(_TriggerConditionType type) {
    switch (type) {
      case _TriggerConditionType.colorMatch: return const Color(0xFF00BCD4);
      case _TriggerConditionType.colorChange: return const Color(0xFFFFB300);
      case _TriggerConditionType.colorDisappear: return const Color(0xFFE040FB);
      case _TriggerConditionType.imageMatch: return const Color(0xFF00E676);
      case _TriggerConditionType.textMatch: return const Color(0xFF448AFF);
      case _TriggerConditionType.objectDetect: return const Color(0xFFFF5252);
    }
  }

  IconData _conditionIcon(_TriggerConditionType type) {
    switch (type) {
      case _TriggerConditionType.colorMatch: return FluentIcons.color;
      case _TriggerConditionType.colorChange: return FluentIcons.sync;
      case _TriggerConditionType.colorDisappear: return FluentIcons.hide;
      case _TriggerConditionType.imageMatch: return FluentIcons.image_pixel;
      case _TriggerConditionType.textMatch: return FluentIcons.font;
      case _TriggerConditionType.objectDetect: return FluentIcons.machine_learning;
    }
  }

  Widget _conditionChip(String label, bool isDark, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: color)),
    );
  }

  Widget _actionChip(String label, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFFFF9800).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: const Color(0xFFFF9800).withValues(alpha: 0.3)),
      ),
      child: Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Color(0xFFFF9800))),
    );
  }

  Widget _buildEngineSelector(VisionCapability capability, String? selectedId, ValueChanged<String?> onChanged) {
    final plugins = _vision.getPluginsFor(capability);
    if (plugins.isEmpty) {
      return const Text('无可用引擎', style: TextStyle(fontSize: 12, color: Colors.grey));
    }
    if (plugins.length == 1) {
      final p = plugins.first;
      return Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: const Color(0xFF00BCD4).withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(p.info.isBuiltin ? FluentIcons.puzzle : FluentIcons.download, size: 12, color: const Color(0xFF00BCD4)),
            const SizedBox(width: 4),
            Text(p.info.name, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF00BCD4))),
          ]),
        ),
      ]);
    }
    return ComboBox<String>(
      items: plugins.map((p) => ComboBoxItem<String>(
        value: p.info.id,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(p.info.isBuiltin ? FluentIcons.puzzle : FluentIcons.download, size: 12),
          const SizedBox(width: 4),
          Text(p.info.name),
          if (!p.isAvailable) ...[
            const SizedBox(width: 4),
            const Text('(不可用)', style: TextStyle(fontSize: 10, color: Colors.grey)),
          ],
        ]),
      )).toList(),
      value: selectedId ?? plugins.first.info.id,
      onChanged: onChanged,
    );
  }

  Widget _overlayHint(String text) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFD32F2F).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFFD32F2F).withValues(alpha: 0.3)),
      ),
      child: Row(children: [
        Icon(FluentIcons.info, size: 14, color: const Color(0xFFD32F2F)),
        const SizedBox(width: 8),
        Expanded(child: Text('$text，按 ESC 取消', style: const TextStyle(fontSize: 13, color: Color(0xFFD32F2F)))),
      ]),
    );
  }

  void _addTrigger(bool isDark, AppState state) async {
    final sel = await _startAreaSelect();
    if (sel == null) return; // cancelled
    final (selX, selY, selX2, selY2) = sel;
    final selW = selX2 - selX;
    final selH = selY2 - selY;

    final result = await showDialog<_TriggerConfig>(context: context, builder: (ctx) => _AddTriggerDialog(
      initialX: selX, initialY: selY,
      initialW: selW, initialH: selH,
      onPickActionPos: _startPick,
      onCaptureTemplate: _captureTemplate,
    ));
    if (result != null && mounted) {
      setState(() {
        _triggers.add(_TriggerEntry(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          name: result.name,
          conditionType: result.conditionType,
          actionType: result.actionType,
          x: result.x, y: result.y, w: result.w, h: result.h,
          targetColor: result.targetColor,
          templateData: result.templateData,
          matchThreshold: result.matchThreshold,
          targetText: result.targetText,
          textMatchMode: result.textMatchMode,
          targetObjectClass: result.targetObjectClass,
          detectConfidence: result.detectConfidence,
          actionX: result.actionX, actionY: result.actionY,
          actionKey: result.actionKey,
          macroId: result.macroId,
          intervalMs: result.intervalMs,
          showTrackingBox: result.showTrackingBox,
          enabled: true,
        ));
      });
      _saveTriggers();
      if (_triggerRunning) _startTriggerChecker();
    }
  }

}

class _AdvancedModelsTab extends StatefulWidget {
  const _AdvancedModelsTab();

  @override
  State<_AdvancedModelsTab> createState() => _AdvancedModelsTabState();
}

class _AdvancedModelsTabState extends State<_AdvancedModelsTab> {
  bool _checking = true;
  bool _downloading = false;
  String _downloadStatus = '';
  double _downloadProgress = 0;
  String _downloadSize = '';
  String _errorMsg = '';
  String _currentSource = 'GitHub';

  bool _onnxExists = false;
  bool _modelExists = false;
  // bool _paddleOcrExists = false;  // PaddleOCR 暂时禁用

  String _pluginDir = '';

  static const _ortVersion = '1.21.0';
  static const _ortGithubUrl =
      'https://github.com/microsoft/onnxruntime/releases/download/v$_ortVersion/onnxruntime-win-x64-$_ortVersion.zip';
  static const _modelGithubUrl =
      'https://github.com/ultralytics/assets/releases/download/v8.4.0/yolo11n.onnx';
  static const _mirrors = <String, String>{
    'GitHub': '',
    'ghfast.top': 'https://ghfast.top/',
    'gh-proxy.com': 'https://gh-proxy.com/',
    'ghproxy.net': 'https://ghproxy.net/',
  };

  String _selectedMirror = 'GitHub';

  @override
  void initState() {
    super.initState();
    _checkDependencies();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<String> _getPluginDir() async {
    final path = await AppPaths.getPluginDir('ai_tracker');
    final dir = Directory(path);
    if (!await dir.exists()) await dir.create(recursive: true);
    return path;
  }

  bool _dllDeployed = false;

  Future<void> _checkDependencies() async {
    if (!mounted) return;
    setState(() => _checking = true);
    final dir = await _getPluginDir();
    _pluginDir = dir;

    _onnxExists = await File('$dir\\onnxruntime.dll').exists();
    _modelExists = await File('$dir\\models\\yolo11n.onnx').exists();
    // _paddleOcrExists = await _checkPaddleOcrInstalled();  // PaddleOCR 暂时禁用
    _dllDeployed = await _deployNativePlugin();

    // 不自动下载，只检查状态，由用户手动触发下载

    if (mounted) setState(() => _checking = false);
  }

  // PaddleOCR 暂时禁用
  // Future<bool> _checkPaddleOcrInstalled() async {
  //   if (!Platform.isWindows) return false;
  //   try {
  //     const channel = MethodChannel('com.clicker.pro/platform');
  //     final result = await channel.invokeMethod<Map>('checkPaddleOcr');
  //     return result != null && result['available'] == true;
  //   } catch (_) {
  //     return false;
  //   }
  // }

  Future<bool> _deployNativePlugin() async {
    final dir = _pluginDir;
    final sep = Platform.pathSeparator;

    String platformDir;
    String libName;
    String libExt;
    if (Platform.isWindows) {
      platformDir = 'windows';
      libExt = '.dll';
      libName = 'ai_tracker';
    } else if (Platform.isLinux) {
      platformDir = 'linux';
      libExt = '.so';
      libName = 'libai_tracker';
    } else if (Platform.isAndroid) {
      platformDir = 'android';
      libExt = '.so';
      libName = 'libai_tracker';
    } else {
      return false;
    }

    final targetDir = Directory('$dir$sep$platformDir');
    if (!await targetDir.exists()) await targetDir.create(recursive: true);

    final exePath = Platform.resolvedExecutable;
    final exeDir = File(exePath).parent.path;

    final pluginDir = await AppPaths.getPluginDir('ai_tracker');

    final libDest = File('$dir$sep$platformDir$sep$libName$libExt');
    final manifestDest = File('$dir$sep${'manifest.json'}');

    final libSources = [
      '$exeDir$sep${'plugins'}$sep${'ai_tracker'}$sep$platformDir$sep$libName$libExt',
      '$exeDir$sep${'data'}$sep${'plugins'}$sep${'ai_tracker'}$sep$platformDir$sep$libName$libExt',
      '$pluginDir$sep$platformDir$sep$libName$libExt',
    ];

    final manifestSources = [
      '$exeDir$sep${'plugins'}$sep${'ai_tracker'}$sep${'manifest.json'}',
      '$exeDir$sep${'data'}$sep${'plugins'}$sep${'ai_tracker'}$sep${'manifest.json'}',
      '$pluginDir$sep${'manifest.json'}',
    ];

    bool libOk = await libDest.exists();
    bool manifestOk = await manifestDest.exists();

    if (!libOk) {
      for (final src in libSources) {
        final srcFile = File(src);
        if (await srcFile.exists()) {
          try {
            await srcFile.copy(libDest.path);
            libOk = true;
            break;
          } catch (_) {}
        }
      }
    }

    if (!manifestOk) {
      for (final src in manifestSources) {
        final srcFile = File(src);
        if (await srcFile.exists()) {
          try {
            await srcFile.copy(manifestDest.path);
            manifestOk = true;
            break;
          } catch (_) {}
        }
      }
    }

    return libOk && manifestOk;
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Future<String> _resolveUrl(String url) async {
    if (_selectedMirror != 'GitHub') return url;

    final client = http.Client();
    try {
      final request = http.Request('GET', Uri.parse(url));
      request.followRedirects = false;
      final response = await client.send(request);

      if (response.statusCode == 302 || response.statusCode == 301) {
        final location = response.headers['location'];
        if (location != null) return location;
      }

      return url;
    } finally {
      client.close();
    }
  }

  Future<void> _downloadWithProgress({
    required String url,
    required String savePath,
    required String label,
  }) async {
    final client = http.Client();
    try {
      final request = http.Request('GET', Uri.parse(url));
      request.followRedirects = true;
      final response = await client.send(request);

      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}');
      }

      final total = response.contentLength ?? 0;
      int received = 0;
      final sink = File(savePath).openWrite();

      await response.stream.forEach((chunk) {
        sink.add(chunk);
        received += chunk.length;
        if (!mounted) return;
        if (total > 0) {
          final progress = received / total;
          setState(() {
            _downloadProgress = progress;
            _downloadSize = '${_formatBytes(received)} / ${_formatBytes(total)}';
            _downloadStatus = '$label ${_formatBytes(received)} / ${_formatBytes(total)}';
          });
        } else {
          setState(() {
            _downloadSize = _formatBytes(received);
            _downloadStatus = '$label ${_formatBytes(received)}';
          });
        }
      });

      await sink.close();

      final file = File(savePath);
      if (!await file.exists()) throw Exception('文件保存失败');
      final fileSize = await file.length();
      if (fileSize < 1024) {
        try {
          final content = await file.readAsString();
          if (content.contains('<!DOCTYPE') || content.contains('<html')) {
            await file.delete();
            throw Exception('下载到的是网页而非文件，可能链接已失效');
          }
        } catch (e) {
          if (e.toString().contains('网页而非文件')) rethrow;
        }
        throw Exception('文件过小(${_formatBytes(fileSize)})，下载可能不完整');
      }
    } finally {
      client.close();
    }
  }

  Future<String> _tryDownloadWithFallback({
    required String githubUrl,
    required String savePath,
    required String label,
  }) async {
    final mirrors = _mirrors.keys.toList();
    final startIndex = mirrors.indexOf(_selectedMirror);
    final order = startIndex >= 0
        ? [...mirrors.sublist(startIndex), ...mirrors.sublist(0, startIndex)]
        : mirrors;

    String? lastError;

    for (final mirror in order) {
      if (!mounted) throw Exception('Widget已销毁');
      final prefix = _mirrors[mirror] ?? '';
      final url = prefix.isEmpty ? githubUrl : '$prefix$githubUrl';

      setState(() {
        _currentSource = mirror;
        _downloadStatus = '$label [源: $mirror]';
      });

      try {
        final realUrl = await _resolveUrl(url);
        await _downloadWithProgress(
          url: realUrl,
          savePath: savePath,
          label: '$label [源: $mirror]',
        );
        if (mounted) setState(() => _selectedMirror = mirror);
        return mirror;
      } catch (e) {
        lastError = e.toString().replaceFirst('Exception: ', '');
        final file = File(savePath);
        if (await file.exists()) {
          try { await file.delete(); } catch (_) {}
        }
        if (mirror != order.last) {
          if (mounted) {
            setState(() {
              _downloadStatus = '源 $mirror 失败，尝试下一个镜像...';
            });
          }
          await Future.delayed(const Duration(milliseconds: 500));
        }
      }
    }

    throw Exception('所有下载源均失败，最后一个错误: $lastError');
  }

  Future<void> _extractZip(String zipPath, String destDir) async {
    final bytes = await File(zipPath).readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);

    for (final file in archive) {
      final filePath = '$destDir\\${file.name}';
      if (file.isFile) {
        final outFile = File(filePath);
        await outFile.parent.create(recursive: true);
        await outFile.writeAsBytes(file.content as List<int>);
      } else {
        await Directory(filePath).create(recursive: true);
      }
    }
  }

  Future<File?> _findFileRecursive(Directory dir, String fileName) async {
    if (!await dir.exists()) return null;
    try {
      await for (final entity in dir.list(recursive: true)) {
        if (entity is File && entity.path.endsWith('\\$fileName')) {
          return entity;
        }
      }
    } catch (_) {}
    return null;
  }

  Future<void> _downloadOnnxRuntime() async {
    if (!mounted) return;
    setState(() {
      _downloading = true;
      _downloadProgress = 0;
      _downloadSize = '';
      _errorMsg = '';
    });

    try {
      final dir = await _getPluginDir();
      final tempDir = await AppPaths.getTempDir();
      final zipPath = '$tempDir\\onnxruntime.zip';

      await _tryDownloadWithFallback(
        githubUrl: _ortGithubUrl,
        savePath: zipPath,
        label: '正在下载 ONNX Runtime v$_ortVersion',
      );

      if (!mounted) return;
      setState(() {
        _downloadStatus = '正在解压 ONNX Runtime...';
        _downloadProgress = 0;
      });

      final extractDir = '$tempDir\\ort_extract';
      await _extractZip(zipPath, extractDir);

      final dllFile = await _findFileRecursive(Directory(extractDir), 'onnxruntime.dll');
      if (dllFile == null) {
        throw Exception('onnxruntime.dll 未找到，解压目录中无此文件');
      }

      await dllFile.copy('$dir\\onnxruntime.dll');
      _onnxExists = true;

      try { await File(zipPath).delete(); } catch (_) {}
      try { await Directory(extractDir).delete(recursive: true); } catch (_) {}

      _downloadStatus = 'ONNX Runtime 安装完成';
      // 重新初始化YOLO插件
      await _reinitYoloPlugin();
    } catch (e) {
      _errorMsg = e.toString().replaceFirst('Exception: ', '');
      _downloadStatus = '安装失败';
    }

    if (mounted) setState(() => _downloading = false);
  }

  Future<void> _downloadModel() async {
    if (!mounted) return;
    setState(() {
      _downloading = true;
      _downloadProgress = 0;
      _downloadSize = '';
      _errorMsg = '';
    });

    try {
      final dir = await _getPluginDir();
      final modelsDir = Directory('$dir\\models');
      if (!await modelsDir.exists()) await modelsDir.create(recursive: true);

      await _tryDownloadWithFallback(
        githubUrl: _modelGithubUrl,
        savePath: '$dir\\models\\yolo11n.onnx',
        label: '正在下载 YOLO11n 模型',
      );
      _modelExists = true;
      _downloadStatus = 'YOLO11n 模型下载完成';
      // 重新初始化YOLO插件以加载模型
      await _reinitYoloPlugin();
    } catch (e) {
      _errorMsg = e.toString().replaceFirst('Exception: ', '');
      _downloadStatus = '下载失败';
    }

    if (mounted) setState(() => _downloading = false);
  }

  static const _pipMirrors = <String, String>{
    '默认源': '',
    '清华源': 'https://pypi.tuna.tsinghua.edu.cn/simple',
    '阿里源': 'https://mirrors.aliyun.com/pypi/simple/',
    '腾讯源': 'https://mirrors.cloud.tencent.com/pypi/simple',
  };

  String _selectedPipMirror = '清华源';

  // PaddleOCR 暂时禁用
  // Future<void> _downloadPaddleOcr() async {
  //   setState(() {
  //     _downloading = true;
  //     _downloadProgress = 0;
  //     _downloadSize = '';
  //     _errorMsg = '';
  //     _downloadStatus = '正在通过 pip 安装 PaddleOCR...';
  //   });
  //
  //   try {
  //     const channel = MethodChannel('com.clicker.pro/platform');
  //     final mirrorUrl = _pipMirrors[_selectedPipMirror] ?? '';
  //     final args = mirrorUrl.isEmpty ? <String, dynamic>{} : <String, dynamic>{'mirror': mirrorUrl};
  //     await channel.invokeMethod<bool>('installPaddleOcr', args);
  //
  //     _paddleOcrExists = true;
  //     _downloadStatus = 'PaddleOCR 安装完成';
  //     // 重新初始化PaddleOCR插件
  //     await _reinitPaddleOcrPlugin();
  //   } catch (e) {
  //     _paddleOcrExists = false;
  //     _errorMsg = 'pip 安装失败，请手动执行: pip install paddlepaddle paddleocr';
  //     _downloadStatus = '安装失败';
  //   }
  //
  //   setState(() => _downloading = false);
  // }

  Future<void> _downloadAll() async {
    if (!_onnxExists) await _downloadOnnxRuntime();
    if (!_modelExists && _errorMsg.isEmpty) await _downloadModel();
    // if (!_paddleOcrExists && _errorMsg.isEmpty && Platform.isWindows) await _downloadPaddleOcr();  // PaddleOCR 暂时禁用
    setState(() {});
  }

  Future<void> _reinitYoloPlugin() async {
    final mgr = VisionPluginManager.instance;
    mgr.resetInitialized('yolo_detect');
    final plugin = mgr.getPlugin('yolo_detect');
    if (plugin != null) {
      final ok = await plugin.initialize();
      debugPrint('[图像识别] YOLO插件重新初始化: $ok, available=${plugin.isAvailable}');
    }
  }

  // PaddleOCR 暂时禁用
  // Future<void> _reinitPaddleOcrPlugin() async {
  //   final mgr = VisionPluginManager.instance;
  //   mgr.resetInitialized('plugin_paddle_ocr');
  //   final plugin = mgr.getPlugin('plugin_paddle_ocr');
  //   if (plugin != null) {
  //     final ok = await plugin.initialize();
  //     debugPrint('[图像识别] PaddleOCR插件重新初始化: $ok, available=${plugin.isAvailable}');
  //   }
  // }

  Future<void> _uninstallAll() async {
    setState(() {
      _downloading = true;
      _downloadStatus = '正在卸载...';
      _errorMsg = '';
    });

    try {
      final dir = Directory(_pluginDir);
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
      _onnxExists = false;
      _modelExists = false;
      _dllDeployed = false;

      if (Platform.isWindows) {
        // PaddleOCR 暂时禁用
        // try {
        //   const channel = MethodChannel('com.clicker.pro/platform');
        //   await channel.invokeMethod<bool>('uninstallPaddleOcr');
        // } catch (_) {}
      }
      // _paddleOcrExists = false;  // PaddleOCR 暂时禁用
      _downloadStatus = '已卸载全部组件';
    } catch (e) {
      _errorMsg = e.toString().replaceFirst('Exception: ', '');
      _downloadStatus = '卸载失败';
    }

    setState(() => _downloading = false);
  }

  Future<void> _openPluginDir() async {
    final dir = Directory(_pluginDir);
    if (!await dir.exists()) await dir.create(recursive: true);
    await Process.run('explorer', [_pluginDir]);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = FluentTheme.of(context).brightness == Brightness.dark;
    final accent = FluentTheme.of(context).accentColor;

    return SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (_checking)
        const Center(child: ProgressRing())
      else ...[
        _buildSection('下载源', isDark, [
          Row(children: [
            Text('当前源: ', style: TextStyle(fontSize: 12, color: isDark ? const Color(0xFF9090B0) : const Color(0xFF8A8A9A))),
            ..._mirrors.keys.map((name) {
              final isSelected = _selectedMirror == name;
              final bgColor = isSelected
                ? accent.withValues(alpha: 0.15)
                : Colors.transparent;
              final textColor = isSelected
                ? accent
                : (isDark ? const Color(0xFF9090B0) : const Color(0xFF8A8A9A));
              return Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Button(
                  onPressed: _downloading ? null : () => setState(() => _selectedMirror = name),
                  style: ButtonStyle(
                    backgroundColor: WidgetStatePropertyAll(bgColor),
                    padding: WidgetStatePropertyAll(const EdgeInsets.symmetric(horizontal: 10, vertical: 4)),
                  ),
                  child: Text(name, style: TextStyle(
                    fontSize: 11,
                    color: textColor,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  )),
                ),
              );
            }),
          ]),
          const SizedBox(height: 4),
          Text(
            _selectedMirror == 'GitHub'
              ? '直连 GitHub，海外网络推荐'
              : '通过国内镜像加速，国内网络推荐',
            style: TextStyle(fontSize: 10, color: isDark ? const Color(0xFF707090) : const Color(0xFFA0A0B0)),
          ),
        ]),

        _buildSection('依赖项', isDark, [
          if (Platform.isWindows) ...[
            _buildDepCard(
              icon: FluentIcons.processing,
              name: 'ONNX Runtime v$_ortVersion',
              desc: 'Microsoft 推理引擎 · YOLO目标检测必需 · ~200MB',
              installed: _onnxExists,
              isDark: isDark,
              accent: accent,
              onInstall: _downloading ? null : _downloadOnnxRuntime,
            ),
            _buildDepCard(
              icon: FluentIcons.machine_learning,
              name: 'YOLO11n 模型',
              desc: 'Ultralytics 目标检测模型 · 条件触发-目标检测必需 · ~6MB',
              installed: _modelExists,
              isDark: isDark,
              accent: accent,
              onInstall: _downloading ? null : _downloadModel,
            ),
            // PaddleOCR 暂时禁用
            // _buildDepCard(
            //   icon: FluentIcons.text_document,
            //   name: 'PaddleOCR',
            //   desc: '百度文字识别引擎 · 通过 pip 安装 · 需 Python 环境',
            //   installed: _paddleOcrExists,
            //   isDark: isDark,
            //   accent: accent,
            //   onInstall: _downloading ? null : _downloadPaddleOcr,
            // ),
            // if (!_paddleOcrExists) Padding(
            //   padding: const EdgeInsets.only(top: 4, left: 4),
            //   child: Row(children: [
            //     Text('pip源: ', style: TextStyle(fontSize: 11, color: isDark ? const Color(0xFF9090B0) : const Color(0xFF8A8A9A))),
            //     ..._pipMirrors.keys.map((name) {
            //       final isSelected = _selectedPipMirror == name;
            //       return Padding(
            //         padding: const EdgeInsets.only(right: 4),
            //         child: Button(
            //           style: ButtonStyle(
            //             padding: WidgetStateProperty.all(const EdgeInsets.symmetric(horizontal: 8, vertical: 2)),
            //             backgroundColor: WidgetStateProperty.all(isSelected
            //               ? accent.withValues(alpha: 0.15)
            //               : isDark ? const Color(0xFF1E1E36) : const Color(0xFFE8E8F4)),
            //           ),
            //           onPressed: _downloading ? null : () => setState(() => _selectedPipMirror = name),
            //           child: Text(name, style: TextStyle(fontSize: 10, color: isSelected ? accent : (isDark ? const Color(0xFF9090B0) : const Color(0xFF6A6A80)))),
            //         ),
            //       );
            //     }),
            //   ]),
            // ),
          ],
          if (Platform.isAndroid) ...[
            _buildDepCard(
              icon: FluentIcons.text_document,
              name: 'ML Kit OCR',
              desc: 'Google 文字识别 · 内置 · 无需下载',
              installed: true,
              isDark: isDark,
              accent: accent,
              onInstall: null,
            ),
          ],
        ]),

        Row(children: [
          FilledButton(
            onPressed: _downloading ? null : _downloadAll,
            style: ButtonStyle(
              backgroundColor: WidgetStatePropertyAll(accent.withValues(alpha: 0.15)),
              padding: WidgetStatePropertyAll(const EdgeInsets.symmetric(horizontal: 20, vertical: 10)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(FluentIcons.download, size: 14, color: accent),
              const SizedBox(width: 8),
              Text('一键安装全部', style: TextStyle(color: accent, fontSize: 13, fontWeight: FontWeight.w600)),
            ]),
          ),
        ]),

        if (_downloading || _downloadStatus.isNotEmpty) ...[
          const SizedBox(height: 16),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_downloadStatus, style: TextStyle(fontSize: 12, color: isDark ? const Color(0xFF9090B0) : const Color(0xFF8A8A9A))),
            if (_downloading) ...[
              const SizedBox(height: 6),
              ProgressBar(value: _downloadProgress * 100),
              if (_downloadSize.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(_downloadSize, style: TextStyle(fontSize: 10, color: isDark ? const Color(0xFF707090) : const Color(0xFFA0A0B0))),
                ),
            ],
            if (_errorMsg.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0x14FF0000),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0x4DFF0000)),
                ),
                child: Text(_errorMsg, style: const TextStyle(fontSize: 11, color: Color(0xFFFF0000))),
              ),
            ],
          ]),
        ],

        const SizedBox(height: 12),

        Row(children: [
          Button(
            onPressed: _openPluginDir,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(FluentIcons.folder_open, size: 12, color: accent),
              const SizedBox(width: 6),
              Text('打开目录', style: TextStyle(fontSize: 12, color: accent)),
            ]),
          ),
          const SizedBox(width: 8),
          Button(
            onPressed: _downloading ? null : _uninstallAll,
            style: ButtonStyle(
              padding: WidgetStatePropertyAll(const EdgeInsets.symmetric(horizontal: 10, vertical: 4)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(FluentIcons.delete, size: 10, color: const Color(0xFFFF0000)),
              const SizedBox(width: 4),
              Text('卸载', style: const TextStyle(fontSize: 11, color: Color(0xFFFF0000))),
            ]),
          ),
        ]),

        const Divider(style: DividerThemeData(horizontalMargin: EdgeInsets.zero)),

        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0x1F4FC3F7),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0x4D4FC3F7)),
          ),
          child: Row(children: [
            Icon(FluentIcons.info, size: 14, color: const Color(0xFF4FC3F7)),
            const SizedBox(width: 8),
            Expanded(child: Text(
              '安装依赖后，可在「条件触发」中使用「目标检测」条件类型。\n目标检测功能已整合到条件触发系统中。',
              style: const TextStyle(fontSize: 12, color: Color(0xFF4FC3F7)),
            )),
          ]),
        ),
      ],
    ]));
  }

  Widget _buildSection(String title, bool isDark, List<Widget> children) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(padding: const EdgeInsets.only(bottom: 8), child: Row(children: [
        Container(width: 3, height: 14, decoration: BoxDecoration(
          color: FluentTheme.of(context).accentColor,
          borderRadius: BorderRadius.circular(2),
        )),
        const SizedBox(width: 8),
        Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700,
          color: isDark ? const Color(0xFFC0C0E8) : const Color(0xFF5A5A80))),
      ])),
      ...children,
      const SizedBox(height: 12),
    ]);
  }

  Widget _buildDepCard({
    required IconData icon,
    required String name,
    required String desc,
    required bool installed,
    required bool isDark,
    required Color accent,
    required VoidCallback? onInstall,
  }) {
    final cardBg = isDark ? const Color(0x80252540) : const Color(0x80F0F0FA);
    final activeColor = installed ? accent : (isDark ? const Color(0xFF606080) : const Color(0xFFB0B0C0));

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: isDark ? const Color(0xFF303050) : const Color(0xFFD0D0E0)),
        ),
        child: Row(children: [
          Container(
            width: 32, height: 32,
            decoration: BoxDecoration(
              color: activeColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(icon, size: 14, color: activeColor),
          ),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(name, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13,
                color: installed ? null : (isDark ? const Color(0xFF606080) : const Color(0xFFB0B0C0)))),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: installed
                    ? const Color(0x1F00E676)
                    : const Color(0x1FFF9800),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(installed ? '已安装' : '未安装',
                  style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600,
                    color: installed ? const Color(0xFF00E676) : const Color(0xFFFF9800))),
              ),
            ]),
            const SizedBox(height: 2),
            Text(desc, style: TextStyle(fontSize: 11, color: isDark ? const Color(0xFF9090B0) : const Color(0xFF8A8A9A))),
          ])),
          if (!installed)
            Button(
              onPressed: onInstall,
              style: ButtonStyle(
                padding: WidgetStatePropertyAll(const EdgeInsets.symmetric(horizontal: 10, vertical: 4)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(FluentIcons.download, size: 10, color: accent),
                const SizedBox(width: 4),
                Text('下载', style: TextStyle(fontSize: 11, color: accent)),
              ]),
            ),
        ]),
      ),
    );
  }
}

// ─── Data Classes ────────────────────────────────────────────

enum _TriggerConditionType { colorMatch, colorChange, colorDisappear, imageMatch, textMatch, objectDetect }
extension on _TriggerConditionType {
  String get label {
    switch (this) {
      case _TriggerConditionType.colorMatch: return '颜色匹配';
      case _TriggerConditionType.colorChange: return '颜色变化';
      case _TriggerConditionType.colorDisappear: return '颜色消失';
      case _TriggerConditionType.imageMatch: return '图像匹配';
      case _TriggerConditionType.textMatch: return '文字匹配';
      case _TriggerConditionType.objectDetect: return '目标检测';
    }
  }
}

enum _TriggerActionType { click, clickTargetCenter, keyPress, startClicker, stopClicker, runMacro }
extension on _TriggerActionType {
  String get label {
    switch (this) {
      case _TriggerActionType.click: return '点击';
      case _TriggerActionType.clickTargetCenter: return '点击目标中心';
      case _TriggerActionType.keyPress: return '按键';
      case _TriggerActionType.startClicker: return '启动连点';
      case _TriggerActionType.stopClicker: return '停止连点';
      case _TriggerActionType.runMacro: return '执行宏';
    }
  }
}

enum _TextMatchMode { contains, notContains, equals, regex, fuzzy }
extension on _TextMatchMode {
  String get label {
    switch (this) {
      case _TextMatchMode.contains: return '包含';
      case _TextMatchMode.notContains: return '不包含';
      case _TextMatchMode.equals: return '等于';
      case _TextMatchMode.regex: return '正则匹配';
      case _TextMatchMode.fuzzy: return '模糊匹配';
    }
  }
  String get hint {
    switch (this) {
      case _TextMatchMode.contains: return 'OCR文本中包含指定文字时触发';
      case _TextMatchMode.notContains: return 'OCR文本中不包含指定文字时触发';
      case _TextMatchMode.equals: return 'OCR文本完全等于指定文字时触发';
      case _TextMatchMode.regex: return 'OCR文本匹配正则表达式时触发';
      case _TextMatchMode.fuzzy: return '忽略空格和标点，模糊匹配文字';
    }
  }
}

class _TriggerEntry {
  final String id;
  String name;
  _TriggerConditionType conditionType;
  _TriggerActionType actionType;
  bool enabled;
  final int x, y, w, h;
  final Color? targetColor;
  final TemplateData? templateData;
  final double matchThreshold;
  final String targetText;
  final _TextMatchMode textMatchMode;
  final String targetObjectClass;
  final double detectConfidence;
  final int actionX, actionY;
  final String actionKey;
  final String macroId;
  int intervalMs;
  bool showTrackingBox;

  _TriggerEntry({
    required this.id, required this.name, required this.conditionType,
    required this.actionType, required this.enabled,
    this.x = 0, this.y = 0, this.w = 100, this.h = 100,
    this.targetColor, this.templateData, this.matchThreshold = 0.8,
    this.targetText = '',
    this.textMatchMode = _TextMatchMode.fuzzy,
    this.targetObjectClass = '',
    this.detectConfidence = 0.5,
    this.actionX = 0, this.actionY = 0,
    this.actionKey = '', this.macroId = '',
    this.intervalMs = 500,
    this.showTrackingBox = true,
  });
}

class _TriggerConfig {
  final String name;
  final _TriggerConditionType conditionType;
  final _TriggerActionType actionType;
  final int x, y, w, h;
  final Color? targetColor;
  final TemplateData? templateData;
  final double matchThreshold;
  final String targetText;
  final _TextMatchMode textMatchMode;
  final String targetObjectClass;
  final double detectConfidence;
  final int actionX, actionY;
  final String actionKey;
  final String macroId;
  final int intervalMs;
  final bool showTrackingBox;
  _TriggerConfig({
    required this.name, required this.conditionType, required this.actionType,
    required this.x, required this.y, required this.w, required this.h,
    this.targetColor, this.templateData, this.matchThreshold = 0.8,
    this.targetText = '',
    this.textMatchMode = _TextMatchMode.fuzzy,
    this.targetObjectClass = '',
    this.detectConfidence = 0.5,
    this.actionX = 0, this.actionY = 0,
    this.actionKey = '', this.macroId = '',
    this.intervalMs = 500,
    this.showTrackingBox = true,
  });
}

// ─── Add Region Dialog ──────────────────────────────────────

// ─── Add Trigger Dialog ─────────────────────────────────────

class _AddTriggerDialog extends StatefulWidget {
  final int initialX, initialY, initialW, initialH;
  final Future<(int, int)?> Function()? onPickActionPos;
  final Future<TemplateData?> Function()? onCaptureTemplate;
  final _TriggerEntry? initialTrigger; // null = add mode, non-null = edit mode
  const _AddTriggerDialog({
    this.initialX = 0, this.initialY = 0,
    this.initialW = 100, this.initialH = 100,
    this.onPickActionPos,
    this.onCaptureTemplate,
    this.initialTrigger,
  });
  @override
  State<_AddTriggerDialog> createState() => _AddTriggerDialogState();
}

class _AddTriggerDialogState extends State<_AddTriggerDialog> {
  _TriggerConditionType _conditionType = _TriggerConditionType.colorMatch;
  _TriggerActionType _actionType = _TriggerActionType.click;
  late int _x, _y, _w, _h;
  late final TextEditingController _xCtrl, _yCtrl, _wCtrl, _hCtrl;
  Color? _targetColor;
  int _actionX = 0, _actionY = 0;
  String _actionKey = '';
  String _macroId = '';
  int _intervalMs = 500;
  String _colorInfo = '';
  String _actionPosInfo = '';
  double _matchThreshold = 0.8;
  String _targetText = '';
  _TextMatchMode _textMatchMode = _TextMatchMode.fuzzy;
  TemplateData? _templateData;
  String _templateInfo = '';
  String _targetObjectClass = '';
  double _detectConfidence = 0.5;
  bool _showTrackingBox = true;

  @override
  void initState() {
    super.initState();
    final t = widget.initialTrigger;
    if (t != null) {
      // Edit mode: populate from existing trigger
      _conditionType = t.conditionType;
      _actionType = t.actionType;
      _x = t.x; _y = t.y; _w = t.w; _h = t.h;
      _targetColor = t.targetColor;
      _matchThreshold = t.matchThreshold;
      _targetText = t.targetText;
      _textMatchMode = t.textMatchMode;
      _targetObjectClass = t.targetObjectClass;
      _detectConfidence = t.detectConfidence;
      _actionX = t.actionX; _actionY = t.actionY;
      _actionKey = t.actionKey;
      _macroId = t.macroId;
      _intervalMs = t.intervalMs;
      _showTrackingBox = t.showTrackingBox;
      _templateData = t.templateData;
      if (t.templateData != null) {
        _templateInfo = '${t.templateData!.width}x${t.templateData!.height}';
      }
    } else {
      _x = widget.initialX;
      _y = widget.initialY;
      _w = widget.initialW;
      _h = widget.initialH;
    }
    _xCtrl = TextEditingController(text: _x.toString());
    _yCtrl = TextEditingController(text: _y.toString());
    _wCtrl = TextEditingController(text: _w.toString());
    _hCtrl = TextEditingController(text: _h.toString());
  }

  @override
  void dispose() {
    _xCtrl.dispose();
    _yCtrl.dispose();
    _wCtrl.dispose();
    _hCtrl.dispose();
    super.dispose();
  }

  bool get _isEditing => widget.initialTrigger != null;

  @override
  Widget build(BuildContext context) {
    return ContentDialog(
      title: Text(_isEditing ? '编辑触发条件' : '添加触发条件'),
      content: SizedBox(width: 400, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('条件类型:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        ComboBox<_TriggerConditionType>(
          value: _conditionType,
          items: _TriggerConditionType.values.map((t) => ComboBoxItem<_TriggerConditionType>(
            value: t,
            child: Text(t.label),
          )).toList(),
          onChanged: (v) {
            if (v != null) {
              setState(() {
                _conditionType = v;
                if (v == _TriggerConditionType.objectDetect && _actionType != _TriggerActionType.clickTargetCenter && _actionType != _TriggerActionType.keyPress) {
                  _actionType = _TriggerActionType.clickTargetCenter;
                }
              });
            }
          },
        ),

        const SizedBox(height: 8),
        const Text('监控区域:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.green.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
          ),
          child: Row(children: [
            Icon(FluentIcons.checkbox_composite, size: 14, color: Colors.green),
            const SizedBox(width: 6),
            Text('已选区域: ($_x, $_y) ${_w}x$_h', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          ]),
        ),
        const SizedBox(height: 8),
        Row(children: [
          SizedBox(width: 60, child: TextBox(controller: _xCtrl, placeholder: 'X', onChanged: (v) => _x = int.tryParse(v) ?? _x)),
          const SizedBox(width: 4),
          SizedBox(width: 60, child: TextBox(controller: _yCtrl, placeholder: 'Y', onChanged: (v) => _y = int.tryParse(v) ?? _y)),
          const SizedBox(width: 4),
          SizedBox(width: 60, child: TextBox(controller: _wCtrl, placeholder: '宽', onChanged: (v) => _w = int.tryParse(v) ?? _w)),
          const SizedBox(width: 4),
          SizedBox(width: 60, child: TextBox(controller: _hCtrl, placeholder: '高', onChanged: (v) => _h = int.tryParse(v) ?? _h)),
          const SizedBox(width: 4),
          Expanded(child: Button(
            onPressed: () async {
              final sel = await ScreenOverlayService.instance.startAreaSelect();
              if (sel != null && mounted) {
                final (sx, sy, sx2, sy2) = sel;
                setState(() {
                  _x = sx; _y = sy; _w = sx2 - sx; _h = sy2 - sy;
                  _xCtrl.text = _x.toString();
                  _yCtrl.text = _y.toString();
                  _wCtrl.text = _w.toString();
                  _hCtrl.text = _h.toString();
                });
              }
            },
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(FluentIcons.edit, size: 12),
              const SizedBox(width: 4),
              const Text('重选'),
            ]),
          )),
        ]),

        // Image match specific: capture template + threshold
        if (_conditionType == _TriggerConditionType.imageMatch) ...[
          const SizedBox(height: 8),
          Row(children: [
            FilledButton(
              onPressed: widget.onCaptureTemplate != null ? () async {
                final tpl = await widget.onCaptureTemplate!();
                if (tpl != null && mounted) {
                  setState(() {
                    _templateData = tpl;
                    _templateInfo = '${tpl.width}x${tpl.height}';
                  });
                }
              } : null,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(FluentIcons.camera, size: 14),
                const SizedBox(width: 6),
                const Text('截取模板'),
              ]),
            ),
            if (_templateData != null) ...[
              const SizedBox(width: 12),
              Icon(FluentIcons.completed, size: 16, color: const Color(0xFF00E676)),
              const SizedBox(width: 4),
              Text(_templateInfo, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              const SizedBox(width: 8),
              Button(onPressed: () => setState(() { _templateData = null; _templateInfo = ''; }),
                child: const Text('清除')),
            ],
          ]),
          const SizedBox(height: 8),
          Row(children: [
            const Text('匹配阈值: ', style: TextStyle(fontSize: 13)),
            Expanded(child: AppSlider(value: _matchThreshold, min: 0.5, max: 1.0, divisions: 50, label: '${(_matchThreshold * 100).toStringAsFixed(0)}%', onChanged: (v) => setState(() => _matchThreshold = v))),
            const SizedBox(width: 8),
            Text('${(_matchThreshold * 100).toStringAsFixed(0)}%', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          ]),
        ],

        // Text match specific: target text
        if (_conditionType == _TriggerConditionType.textMatch) ...[
          const SizedBox(height: 8),
          TextBox(placeholder: '输入要匹配的文字', onChanged: (v) => _targetText = v),
          const SizedBox(height: 6),
          const Text('匹配模式:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          ComboBox<_TextMatchMode>(
            value: _textMatchMode,
            items: _TextMatchMode.values.map((m) => ComboBoxItem<_TextMatchMode>(
              value: m,
              child: Text(m.label),
            )).toList(),
            onChanged: (v) { if (v != null) setState(() => _textMatchMode = v); },
          ),
          const SizedBox(height: 4),
          Text(_textMatchMode.hint, style: const TextStyle(fontSize: 11, color: Color(0xFF9090B0))),
          if (Platform.isWindows) const SizedBox(height: 6),
          if (Platform.isWindows) Container(
            width: double.infinity,
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: const Color(0x1FFFF9800),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: const Color(0x4DFF9800)),
            ),
            child: Row(children: [
              Icon(FluentIcons.info, size: 12, color: const Color(0xFFFF9800)),
              const SizedBox(width: 4),
              Expanded(child: Text(
                'Windows OCR 已就绪，支持中英文识别',  // PaddleOCR 暂时禁用
                style: const TextStyle(fontSize: 10, color: Color(0xFF00E676)),
              )),
            ]),
          ),
        ],

        if (_conditionType == _TriggerConditionType.objectDetect) ...[
          const SizedBox(height: 8),
          Row(children: [
            const Text('目标类别: ', style: TextStyle(fontSize: 13)),
            const SizedBox(width: 4),
            Expanded(child: ComboBox<String>(
              value: _targetObjectClass.isEmpty ? '' : _cocoEnToZh(_targetObjectClass),
              items: [
                ComboBoxItem<String>(value: '', child: Text('所有目标', style: TextStyle(fontSize: 12, color: FluentTheme.of(context).brightness == Brightness.dark ? const Color(0xFF8080A0) : const Color(0xFF8A8AA0)))),
                ..._cocoClasses.map((e) => ComboBoxItem<String>(value: e.key, child: Text('${e.key} (${e.value})', style: const TextStyle(fontSize: 12)))),
              ],
              onChanged: (v) => setState(() => _targetObjectClass = v == null || v.isEmpty ? '' : _cocoZhToEn(v)),
              isExpanded: true,
            )),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            const Text('置信度: ', style: TextStyle(fontSize: 13)),
            Expanded(child: AppSlider(value: _detectConfidence, min: 0.1, max: 0.95, divisions: 17, label: '${(_detectConfidence * 100).toStringAsFixed(0)}%', onChanged: (v) => setState(() => _detectConfidence = v))),
            const SizedBox(width: 8),
            Text('${(_detectConfidence * 100).toStringAsFixed(0)}%', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          ]),
          const SizedBox(height: 4),
          const Text('需要先在「高级模型」中下载 ONNX Runtime 和 YOLO 模型', style: TextStyle(fontSize: 11, color: Color(0xFFFF9800))),
          const SizedBox(height: 6),
          Row(children: [
            Checkbox(
              checked: _showTrackingBox,
              onChanged: (v) => setState(() => _showTrackingBox = v ?? true),
            ),
            const SizedBox(width: 4),
            const Text('显示追踪框', style: TextStyle(fontSize: 13)),
          ]),
        ],

        const SizedBox(height: 12),
        const Text('执行动作:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        ComboBox<_TriggerActionType>(
          value: _actionType,
          items: _TriggerActionType.values.map((t) => ComboBoxItem<_TriggerActionType>(
            value: t,
            child: Text(t.label),
          )).toList(),
          onChanged: (v) { if (v != null) setState(() => _actionType = v); },
        ),

        if (_actionType == _TriggerActionType.click) ...[
          const SizedBox(height: 4),
          Row(children: [
            if (widget.onPickActionPos != null)
              Button(
                onPressed: () async {
                  final pos = await widget.onPickActionPos!();
                  if (pos != null) {
                    setState(() {
                      _actionX = pos.$1;
                      _actionY = pos.$2;
                      _actionPosInfo = '(${pos.$1}, ${pos.$2})';
                    });
                  }
                },
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(FluentIcons.map_pin, size: 12),
                  const SizedBox(width: 4),
                  Text(_actionPosInfo.isNotEmpty ? _actionPosInfo : '选取坐标'),
                ]),
              ),
            if (widget.onPickActionPos != null) const SizedBox(width: 8),
            SizedBox(width: 70, child: TextBox(placeholder: 'X', onChanged: (v) => _actionX = int.tryParse(v) ?? _actionX)),
            const SizedBox(width: 6),
            SizedBox(width: 70, child: TextBox(placeholder: 'Y', onChanged: (v) => _actionY = int.tryParse(v) ?? _actionY)),
          ]),
        ] else if (_actionType == _TriggerActionType.clickTargetCenter) ...[
          const SizedBox(height: 4),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFFF5252).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0xFFFF5252).withValues(alpha: 0.2)),
            ),
            child: Row(children: [
              const Icon(FluentIcons.machine_learning, size: 14, color: Color(0xFFFF5252)),
              const SizedBox(width: 6),
              Expanded(child: Text(
                '检测到目标后，自动点击目标中心位置',
                style: const TextStyle(fontSize: 11, color: Color(0xFFFF5252)),
              )),
            ]),
          ),
        ] else if (_actionType == _TriggerActionType.keyPress) ...[
          const SizedBox(height: 4),
          SizedBox(width: 120, child: TextBox(placeholder: '按键 (如 A, Enter)', onChanged: (v) => _actionKey = v)),
        ] else if (_actionType == _TriggerActionType.runMacro) ...[
          const SizedBox(height: 4),
          Builder(builder: (context) {
            final macros = context.read<AppState>().macros;
            if (macros.isEmpty) {
              return const Text('暂无已保存的宏，请先录制宏', style: TextStyle(fontSize: 12, color: Colors.grey));
            }
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('选择宏:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              ComboBox<String>(
                value: _macroId.isNotEmpty && macros.any((m) => m.id == _macroId) ? _macroId : macros.first.id,
                items: macros.map((m) => ComboBoxItem<String>(
                  value: m.id,
                  child: Text('${m.name} (${m.events.length}步)'),
                )).toList(),
                onChanged: (v) { if (v != null) setState(() => _macroId = v); },
              ),
            ]);
          }),
        ],

        const SizedBox(height: 8),
        Row(children: [
          const Text('检查间隔: ', style: TextStyle(fontSize: 13)),
          Expanded(child: AppSlider(value: _intervalMs.toDouble(), min: 100, max: 5000, divisions: 49, label: '${_intervalMs}ms', onChanged: (v) => setState(() => _intervalMs = v.round()))),
          const SizedBox(width: 8),
          Text('$_intervalMs ms', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        ]),
      ]))),
      actions: [
        Button(onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton(onPressed: () => Navigator.pop(context, _TriggerConfig(
          name: '${_conditionType.label} → ${_actionType.label}',
          conditionType: _conditionType,
          actionType: _actionType,
          x: _x, y: _y, w: _w, h: _h,
          targetColor: _targetColor,
          templateData: _templateData,
          matchThreshold: _matchThreshold,
          targetText: _targetText,
          textMatchMode: _textMatchMode,
          targetObjectClass: _targetObjectClass,
          detectConfidence: _detectConfidence,
          actionX: _actionX, actionY: _actionY,
          actionKey: _actionKey,
          macroId: _macroId,
          intervalMs: _intervalMs,
          showTrackingBox: _showTrackingBox,
        )), child: Text(_isEditing ? '保存' : '添加')),
      ],
    );
  }
}
