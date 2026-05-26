/// Image recognition page — screen monitoring, image search, OCR, conditional triggers.
library;

import 'dart:async';
import 'dart:convert';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/app_state.dart';
import '../../services/macro_service.dart';
import '../../services/screen_monitor_service.dart';
import '../../services/vision_service.dart';
import '../../services/vision_plugin.dart';
import '../../services/vision_plugin_manager.dart';
import '../../services/platform/windows_input.dart';

class ImageRecognitionPage extends StatefulWidget {
  const ImageRecognitionPage({super.key});

  @override
  State<ImageRecognitionPage> createState() => _ImageRecognitionPageState();
}

class _ImageRecognitionPageState extends State<ImageRecognitionPage> {
  int _selectedTab = 0;
  final ScreenMonitorService _monitor = ScreenMonitorService();
  final VisionService _vision = VisionService();

  // Region monitor entries
  final List<_RegionEntry> _regions = [];
  int _checkIntervalMs = 500;
  double _sensitivity = 0.5;

  // Image search state
  TemplateData? _template;
  String _templateInfo = '';
  int _searchAreaX = 0, _searchAreaY = 0, _searchAreaW = 1920, _searchAreaH = 1080;
  String _searchAreaInfo = '';
  bool _selectingSearchArea = false;
  bool _capturingTemplate = false;
  double _matchThreshold = 0.8;
  MatchResult? _lastMatch;
  bool _searching = false;
  String? _selectedMatchEngine; // plugin ID for template matching

  // OCR state
  int _ocrAreaX = 0, _ocrAreaY = 0, _ocrAreaW = 400, _ocrAreaH = 200;
  String _ocrAreaInfo = '';
  bool _selectingOcrArea = false;
  String _ocrLanguage = 'zh-Hans-CN';
  OcrResult? _lastOcrResult;
  bool _ocrRunning = false;
  String? _selectedOcrEngine; // plugin ID for OCR

  // OCR tools install state
  bool _tesseractInstalled = false;
  bool _pythonInstalled = false;
  bool _checkingTools = true;
  bool _installingTool = false;
  bool _initialized = false;

  // Conditional triggers
  final List<_TriggerEntry> _triggers = [];
  Timer? _triggerCheckTimer;
  final Map<String, DateTime> _triggerLastFired = {}; // debounce

  // Area selection state (shared by all overlay operations)
  Completer<(int, int, int, int)>? _areaSelectCompleter;
  // Click pick state
  Completer<(int, int)>? _pickCompleter;
  bool _overlayActive = false;

  // Platform channel for overlay
  static const _platformChannel = MethodChannel('com.clicker.pro/platform');

  @override
  void initState() {
    super.initState();
    _monitor.onLogEntry = (_) { if (mounted) setState(() {}); };
    _monitor.onMonitoringChanged = (_) { if (mounted) setState(() {}); };

    // Single unified overlay handler (must be set before any async work)
    _platformChannel.setMethodCallHandler((call) async {
      if (!mounted) return;
      switch (call.method) {
        case 'onOverlayClick':
          final args = call.arguments as Map;
          final x = args['x'] as int;
          final y = args['y'] as int;
          await _handleOverlayClick(x, y);
          break;
        case 'onOverlayWindowPick':
          final args = call.arguments as Map;
          final x = args['x'] as int;
          final y = args['y'] as int;
          await _handleOverlayClick(x, y);
          break;
        case 'onOverlayAreaSelected':
          final args = call.arguments as Map;
          final x1 = args['x1'] as int;
          final y1 = args['y1'] as int;
          final x2 = args['x2'] as int;
          final y2 = args['y2'] as int;
          await _platformChannel.invokeMethod('stopOverlay');
          _overlayActive = false;
          if (_areaSelectCompleter != null && !_areaSelectCompleter!.isCompleted) {
            _areaSelectCompleter!.complete((x1, y1, x2, y2));
          }
          if (mounted) setState(() {
            _selectingSearchArea = false;
            _selectingOcrArea = false;
            _capturingTemplate = false;
          });
          break;
        case 'onOverlayCancelled':
          await _platformChannel.invokeMethod('stopOverlay');
          _overlayActive = false;
          if (_areaSelectCompleter != null && !_areaSelectCompleter!.isCompleted) {
            _areaSelectCompleter!.completeError('cancelled');
          }
          if (_pickCompleter != null && !_pickCompleter!.isCompleted) {
            _pickCompleter!.completeError('cancelled');
          }
          if (mounted) setState(() {
            _selectingSearchArea = false;
            _selectingOcrArea = false;
            _capturingTemplate = false;
          });
          break;
      }
    });

    // Defer all heavy initialization to avoid blocking page switch
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initAndLoad();
    });
  }

  Future<void> _initAndLoad() async {
    await _initPlugins();
    await _loadPersistedData();
    if (mounted) setState(() => _initialized = true);
  }

  Future<void> _initPlugins() async {
    await VisionPluginManager.registerBuiltinPlugins();
    await _vision.pluginManager.initializeAll();
    if (mounted) setState(() {});
  }

  // ─── Persistence ──────────────────────────────────────────
  static const _kRegionsKey = 'img_rec_regions';
  static const _kTriggersKey = 'img_rec_triggers';

  Future<void> _loadPersistedData() async {
    final prefs = await SharedPreferences.getInstance();

    // Load regions
    final regionsJson = prefs.getString(_kRegionsKey);
    if (regionsJson != null) {
      try {
        final list = jsonDecode(regionsJson) as List;
        for (final m in list) {
          final entry = _RegionEntry(
            id: m['id'] ?? '',
            name: m['name'] ?? '监控区域',
            threshold: (m['threshold'] as num?)?.toDouble() ?? 0.85,
            enabled: m['enabled'] ?? true,
            x: m['x'] ?? 0, y: m['y'] ?? 0,
            w: m['w'] ?? 100, h: m['h'] ?? 100,
          );
          _regions.add(entry);
          _monitor.addRegion(MonitorRegion(
            id: entry.id, name: entry.name,
            x: entry.x, y: entry.y, w: entry.w, h: entry.h,
            enabled: entry.enabled,
            onDetected: () { if (mounted) setState(() {}); },
            onChanged: () {
              final t = _regions.where((t) => t.id == entry.id).firstOrNull;
              if (t != null) {
                final region = _monitor.regions.where((r) => r.id == entry.id).firstOrNull;
                if (region != null && region.lastCenterColor != null) {
                  t.lastColor = region.lastCenterColor;
                }
              }
              if (mounted) setState(() {});
            },
          ));
        }
      } catch (_) {}
    }

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
            actionX: m['actionX'] ?? 0, actionY: m['actionY'] ?? 0,
            actionKey: m['actionKey'] ?? '',
            macroId: m['macroId'] ?? '',
            intervalMs: m['intervalMs'] ?? 500,
          ));
        }
      } catch (_) {}
    }

    if (mounted) setState(() {});
    // Delay heavy checks to avoid blocking page load
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted) _checkOcrTools();
    });
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

  Future<void> _saveRegions() async {
    final prefs = await SharedPreferences.getInstance();
    final list = _regions.map((r) => {
      'id': r.id, 'name': r.name, 'threshold': r.threshold,
      'enabled': r.enabled, 'x': r.x, 'y': r.y, 'w': r.w, 'h': r.h,
    }).toList();
    await prefs.setString(_kRegionsKey, jsonEncode(list));
  }

  Future<void> _saveTriggers() async {
    final prefs = await SharedPreferences.getInstance();
    final list = _triggers.map((t) => {
      'id': t.id, 'name': t.name,
      'conditionType': t.conditionType.name,
      'actionType': t.actionType.name,
      'enabled': t.enabled,
      'x': t.x, 'y': t.y, 'w': t.w, 'h': t.h,
      'matchThreshold': t.matchThreshold,
      'targetText': t.targetText,
      'textMatchMode': t.textMatchMode.name,
      'actionX': t.actionX, 'actionY': t.actionY,
      'actionKey': t.actionKey, 'macroId': t.macroId, 'intervalMs': t.intervalMs,
    }).toList();
    await prefs.setString(_kTriggersKey, jsonEncode(list));
  }

  // ─── Trigger Execution ────────────────────────────────────
  bool _triggerRunning = false; // user must explicitly start

  void _startTriggerChecker() {
    _triggerCheckTimer?.cancel();
    final enabledTriggers = _triggers.where((t) => t.enabled).toList();
    if (enabledTriggers.isEmpty) return;

    // Determine interval: at least 500ms, use trigger intervals as guide
    int minInterval = 500;
    // For expensive triggers (OCR/template), enforce at least 2s interval
    final hasExpensiveTriggers = enabledTriggers.any((t) =>
      t.conditionType == _TriggerConditionType.imageMatch ||
      t.conditionType == _TriggerConditionType.textMatch);
    if (hasExpensiveTriggers && minInterval < 2000) minInterval = 2000;

    _triggerCheckTimer = Timer.periodic(Duration(milliseconds: minInterval), (_) => _checkTriggers());
  }

  void _stopTriggerChecker() {
    _triggerCheckTimer?.cancel();
    _triggerCheckTimer = null;
  }

  Future<void> _checkTriggers() async {
    if (!_triggerRunning) return;
    final now = DateTime.now();
    for (final trigger in _triggers) {
      if (!trigger.enabled) continue;

      // Debounce: don't fire more often than the trigger's interval
      final lastFired = _triggerLastFired[trigger.id];
      if (lastFired != null && now.difference(lastFired).inMilliseconds < trigger.intervalMs) continue;

      bool conditionMet = false;
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
              final result = await _vision.findImage(
                regionX: trigger.x, regionY: trigger.y, regionW: trigger.w, regionH: trigger.h,
                template: trigger.templateData!,
                threshold: trigger.matchThreshold,
              );
              conditionMet = result != null;
            }
            break;
          case _TriggerConditionType.textMatch:
            if (trigger.targetText.isNotEmpty) {
              final ocrResult = await _vision.ocrRegion(
                x: trigger.x, y: trigger.y, w: trigger.w, h: trigger.h,
                language: _ocrLanguage,
              );
              if (ocrResult != null && ocrResult.hasText) {
                conditionMet = _matchText(ocrResult.text, trigger.targetText, trigger.textMatchMode);
              }
            }
            break;
        }
      } catch (_) {
        continue;
      }

      if (conditionMet) {
        _triggerLastFired[trigger.id] = now;
        await _executeTriggerAction(trigger);
      }
    }
  }

  final Map<String, Color> _triggerLastColors = {};

  double _colorDiff(Color a, Color b) {
    final dr = ((a.r - b.r) * 255).round().abs();
    final dg = ((a.g - b.g) * 255).round().abs();
    final db = ((a.b - b.b) * 255).round().abs();
    return (dr + dg + db) / 3.0;
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

  Future<void> _handleOverlayClick(int x, int y) async {
    try {
      await _platformChannel.invokeMethod('stopOverlay');
      _overlayActive = false;
      if (_pickCompleter != null && !_pickCompleter!.isCompleted) {
        _pickCompleter!.complete((x, y));
      }
    } on PlatformException {
      // ignore
    }
  }

  Future<(int, int, int, int)?> _startAreaSelect() async {
    _areaSelectCompleter = Completer<(int, int, int, int)>();
    _overlayActive = true;
    try {
      await _platformChannel.invokeMethod('startAreaSelectOverlay');
      // Wait for user to complete selection
      return await _areaSelectCompleter!.future;
    } on PlatformException {
      _overlayActive = false;
      _areaSelectCompleter = null;
      return null;
    } catch (e) {
      _overlayActive = false;
      _areaSelectCompleter = null;
      return null;
    }
  }

  Future<(int, int)?> _startPick() async {
    _pickCompleter = Completer<(int, int)>();
    _overlayActive = true;
    try {
      await _platformChannel.invokeMethod('startPickOverlay');
      return await _pickCompleter!.future;
    } on PlatformException {
      _overlayActive = false;
      _pickCompleter = null;
      return null;
    } catch (e) {
      _overlayActive = false;
      _pickCompleter = null;
      return null;
    }
  }

  @override
  void dispose() {
    _stopTriggerChecker();
    if (_overlayActive) {
      _platformChannel.invokeMethod('stopOverlay');
    }
    _platformChannel.setMethodCallHandler(null);
    _monitor.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final isDark = FluentTheme.of(context).brightness == Brightness.dark;

    if (!state.clickerConfig.imageRecognitionEnabled) {
      return ScaffoldPage(
        content: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(FluentIcons.image_pixel, size: 48, color: Colors.grey),
          const SizedBox(height: 12),
          const Text('图像识别未启用', style: TextStyle(fontSize: 16)),
        ])),
      );
    }

    // Show loading animation while initializing
    if (!_initialized) {
      return ScaffoldPage(
        content: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(width: 32, height: 32, child: ProgressRing()),
          const SizedBox(height: 16),
          Text('正在初始化图像识别...', style: TextStyle(fontSize: 14, color: isDark ? const Color(0xFF9090B0) : const Color(0xFF6A6A7A))),
        ])),
      );
    }

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
          _tabChip('区域监控', _selectedTab == 0, () => setState(() => _selectedTab = 0)),
          const SizedBox(width: 6),
          _tabChip('图像查找', _selectedTab == 1, () => setState(() => _selectedTab = 1)),
          const SizedBox(width: 6),
          _tabChip('文字识别', _selectedTab == 2, () => setState(() => _selectedTab = 2)),
          const SizedBox(width: 6),
          _tabChip('条件触发', _selectedTab == 3, () => setState(() => _selectedTab = 3)),
        ]),
        const SizedBox(height: 16),

        if (_selectedTab == 0) ..._buildRegionMonitor(isDark, state),
        if (_selectedTab == 1) ..._buildImageSearch(isDark, state),
        if (_selectedTab == 2) ..._buildOcrTab(isDark, state),
        if (_selectedTab == 3) ..._buildTriggers(isDark, state),
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
            color: selected ? accent.withValues(alpha:0.15) : Colors.transparent,
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

  // ─── Region Monitor ────────────────────────────────────────

  List<Widget> _buildRegionMonitor(bool isDark, AppState state) {
    final cardBg = isDark ? const Color(0xFF252540).withValues(alpha: 0.5) : const Color(0xFFF0F0FA).withValues(alpha: 0.5);
    final logs = _monitor.logs.reversed.take(30).toList();
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
            Icon(FluentIcons.devices2, size: 16, color: state.accentColor),
            const SizedBox(width: 8),
            const Text('屏幕区域监控', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            const Spacer(),
            FilledButton(
              onPressed: _monitor.isMonitoring ? _monitor.stopMonitoring : _monitor.startMonitoring,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(_monitor.isMonitoring ? FluentIcons.stop : FluentIcons.play, size: 12),
                const SizedBox(width: 4),
                Text(_monitor.isMonitoring ? '停止' : '开始'),
              ]),
            ),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            const Text('频率: ', style: TextStyle(fontSize: 13)),
            ComboBox<String>(
              items: ['100ms', '200ms', '500ms', '1000ms', '2000ms'].map((l) => ComboBoxItem(value: l, child: Text(l))).toList(),
              value: ['100ms', '200ms', '500ms', '1000ms', '2000ms'].contains('${_checkIntervalMs}ms') ? '${_checkIntervalMs}ms' : '500ms',
              onChanged: (v) {
                if (v != null) {
                  final ms = int.parse(v.replaceAll('ms', ''));
                  setState(() => _checkIntervalMs = ms);
                  _monitor.setCheckInterval(ms);
                }
              },
            ),
            const SizedBox(width: 16),
            const Text('灵敏度: ', style: TextStyle(fontSize: 13)),
            SizedBox(width: 120, child: Slider(value: _sensitivity, min: 0.1, max: 1.0, divisions: 9, onChanged: (v) {
              setState(() => _sensitivity = v);
              _monitor.setSensitivity(v);
            })),
            Text('${(_sensitivity * 100).toStringAsFixed(0)}%', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          ]),
        ]),
      ),
      const SizedBox(height: 12),

      SizedBox(width: double.infinity, child: Button(onPressed: () => _addRegion(isDark, state), child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Icon(FluentIcons.add, size: 14),
        const SizedBox(width: 6),
        const Text('添加监控区域'),
      ]))),
      const SizedBox(height: 12),

      if (_regions.isEmpty)
        Center(child: Padding(padding: const EdgeInsets.all(32), child: Column(children: [
          const Icon(FluentIcons.image_search, size: 48, color: Colors.grey),
          const SizedBox(height: 12),
          const Text('暂无监控区域', style: TextStyle(fontSize: 14)),
        ])))
      else
        ..._regions.map((t) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: isDark ? const Color(0xFF303050) : const Color(0xFFD0D0E0)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(FluentIcons.image_search, size: 16, color: state.accentColor),
                const SizedBox(width: 8),
                Expanded(child: Text(t.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14))),
                ToggleSwitch(checked: t.enabled, onChanged: (v) { setState(() => t.enabled = v); _saveRegions(); }),
                const SizedBox(width: 8),
                IconButton(icon: Icon(FluentIcons.delete, size: 14, color: Colors.red), onPressed: () {
                  setState(() { _regions.remove(t); _monitor.removeRegion(t.id); });
                  _saveRegions();
                }),
              ]),
              const SizedBox(height: 4),
              Text('区域: (${t.x}, ${t.y}) ${t.w}x${t.h}', style: TextStyle(fontSize: 12, color: isDark ? const Color(0xFF9090B0) : const Color(0xFF8A8A9A))),
              if (t.targetColor != null) ...[
                const SizedBox(height: 6),
                Row(children: [
                  const Text('目标: ', style: TextStyle(fontSize: 12)),
                  Container(width: 20, height: 20, decoration: BoxDecoration(
                    color: t.targetColor,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: isDark ? const Color(0xFF404060) : const Color(0xFFD0D0D8)),
                  )),
                  const SizedBox(width: 4),
                  Text('#${t.targetColor!.toARGB32().toRadixString(16).substring(2).toUpperCase()}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                ]),
              ],
              if (t.lastColor != null) ...[
                const SizedBox(height: 4),
                Row(children: [
                  const Text('当前: ', style: TextStyle(fontSize: 12)),
                  Container(width: 20, height: 20, decoration: BoxDecoration(
                    color: t.lastColor,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: isDark ? const Color(0xFF404060) : const Color(0xFFD0D0D8)),
                  )),
                  const SizedBox(width: 4),
                  Text('#${t.lastColor!.toARGB32().toRadixString(16).substring(2).toUpperCase()}', style: const TextStyle(fontSize: 12)),
                ]),
              ],
              const SizedBox(height: 6),
              Row(children: [
                const Text('阈值: ', style: TextStyle(fontSize: 12)),
                Text('${(t.threshold * 100).toStringAsFixed(0)}%', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                const SizedBox(width: 8),
                Expanded(child: Slider(
                  value: t.threshold,
                  min: 0.5, max: 1.0, divisions: 50,
                  onChanged: (v) => setState(() => t.threshold = v),
                )),
              ]),
            ]),
          ),
        )),

      // Log section
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: isDark ? const Color(0xFF303050) : const Color(0xFFD0D0E0)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(FluentIcons.history, size: 16, color: state.accentColor),
            const SizedBox(width: 8),
            const Text('监控日志', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            const Spacer(),
            HyperlinkButton(onPressed: () { _monitor.clearLogs(); setState(() {}); }, child: const Text('清空')),
          ]),
          const SizedBox(height: 8),
          if (logs.isEmpty)
            Center(child: Padding(
              padding: const EdgeInsets.all(20),
              child: Text('开始监控后将显示日志', style: TextStyle(fontSize: 12, color: isDark ? const Color(0xFF707090) : const Color(0xFF9A9AAA))),
            ))
          else
            ...logs.map((log) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(children: [
                Text('${log.time.hour.toString().padLeft(2, '0')}:${log.time.minute.toString().padLeft(2, '0')}:${log.time.second.toString().padLeft(2, '0')}',
                  style: TextStyle(fontSize: 11, fontFamily: 'monospace', color: isDark ? const Color(0xFF707090) : const Color(0xFF9A9AAA))),
                const SizedBox(width: 8),
                Icon(_logLevelIcon(log.level), size: 12, color: _logLevelColor(log.level)),
                const SizedBox(width: 4),
                Expanded(child: Text(log.message, style: TextStyle(fontSize: 12, color: _logLevelColor(log.level)))),
              ]),
            )),
        ]),
      ),
    ];
  }

  void _addRegion(bool isDark, AppState state) async {
    final sel = await _startAreaSelect();
    if (sel == null) return; // cancelled
    final (selX, selY, selX2, selY2) = sel;
    final selW = selX2 - selX;
    final selH = selY2 - selY;

    final result = await showDialog<_RegionConfig>(context: context, builder: (ctx) => _AddRegionDialog(
      initialX: selX, initialY: selY,
      initialW: selW, initialH: selH,
    ));
    if (result != null && mounted) {
      final entry = _RegionEntry(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: result.name,
        x: result.x, y: result.y, w: result.w, h: result.h,
        threshold: result.threshold,
        enabled: true,
        targetColor: result.targetColor,
      );
      setState(() => _regions.add(entry));

      _monitor.addRegion(MonitorRegion(
        id: entry.id,
        name: entry.name,
        x: entry.x, y: entry.y, w: entry.w, h: entry.h,
        targetColor: entry.targetColor,
        enabled: entry.enabled,
        onDetected: () { if (mounted) setState(() {}); },
        onChanged: () {
          final t = _regions.where((t) => t.id == entry.id).firstOrNull;
          if (t != null) {
            final region = _monitor.regions.where((r) => r.id == entry.id).firstOrNull;
            if (region != null && region.lastCenterColor != null) {
              t.lastColor = region.lastCenterColor;
            }
          }
          if (mounted) setState(() {});
        },
      ));
      _saveRegions();
    }
  }

  // ─── Image Search ──────────────────────────────────────────

  List<Widget> _buildImageSearch(bool isDark, AppState state) {
    final cardBg = isDark ? const Color(0xFF252540).withValues(alpha: 0.5) : const Color(0xFFF0F0FA).withValues(alpha: 0.5);
    return [
      // Template
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: isDark ? const Color(0xFF303050) : const Color(0xFFD0D0E0)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(FluentIcons.image_search, size: 16, color: state.accentColor),
            const SizedBox(width: 8),
            const Text('查找模板', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          ]),
          const SizedBox(height: 12),
          if (_capturingTemplate)
            _overlayHint('在屏幕上拖拽选择要查找的图像区域')
          else
            Row(children: [
              FilledButton(
                onPressed: () async {
                  setState(() => _capturingTemplate = true);
                  final sel = await _startAreaSelect();
                  if (sel == null) {
                    if (mounted) setState(() => _capturingTemplate = false);
                    return;
                  }
                  final (x1, y1, x2, y2) = sel;
                  final w = x2 - x1;
                  final h = y2 - y1;
                  if (w < 5 || h < 5) {
                    if (mounted) setState(() => _capturingTemplate = false);
                    return;
                  }
                  final tpl = await _vision.captureTemplate(x1, y1, w, h);
                  if (mounted) setState(() {
                    _template = tpl;
                    _templateInfo = '($x1, $y1) ${w}x$h';
                    _capturingTemplate = false;
                  });
                },
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(FluentIcons.camera, size: 14),
                  const SizedBox(width: 6),
                  const Text('截取模板'),
                ]),
              ),
              if (_template != null) ...[
                const SizedBox(width: 12),
                Icon(FluentIcons.completed, size: 16, color: const Color(0xFF00E676)),
                const SizedBox(width: 4),
                Text(_templateInfo, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                const SizedBox(width: 8),
                Button(onPressed: () => setState(() { _template = null; _templateInfo = ''; _lastMatch = null; }),
                  child: const Text('清除')),
              ],
            ]),
        ]),
      ),
      const SizedBox(height: 12),

      // Search area
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: isDark ? const Color(0xFF303050) : const Color(0xFFD0D0E0)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(FluentIcons.map_pin, size: 16, color: state.accentColor),
            const SizedBox(width: 8),
            const Text('搜索区域', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          ]),
          const SizedBox(height: 12),
          if (_selectingSearchArea)
            _overlayHint('在屏幕上拖拽选择搜索区域')
          else
            Row(children: [
              FilledButton(
                onPressed: () async {
                  setState(() => _selectingSearchArea = true);
                  final sel = await _startAreaSelect();
                  if (sel == null) {
                    if (mounted) setState(() => _selectingSearchArea = false);
                    return;
                  }
                  final (x1, y1, x2, y2) = sel;
                  setState(() {
                    _searchAreaX = x1;
                    _searchAreaY = y1;
                    _searchAreaW = x2 - x1;
                    _searchAreaH = y2 - y1;
                    _searchAreaInfo = '($x1, $y1) ${_searchAreaW}x$_searchAreaH';
                  });
                },
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(FluentIcons.checkbox_composite, size: 14),
                  const SizedBox(width: 6),
                  Text(_searchAreaInfo.isNotEmpty ? _searchAreaInfo : '选择搜索区域'),
                ]),
              ),
              const SizedBox(width: 8),
              SizedBox(width: 70, child: TextBox(placeholder: 'X', onChanged: (v) => _searchAreaX = int.tryParse(v) ?? 0)),
              const SizedBox(width: 6),
              SizedBox(width: 70, child: TextBox(placeholder: 'Y', onChanged: (v) => _searchAreaY = int.tryParse(v) ?? 0)),
              const SizedBox(width: 6),
              SizedBox(width: 70, child: TextBox(placeholder: '宽', onChanged: (v) => _searchAreaW = int.tryParse(v) ?? 1920)),
              const SizedBox(width: 6),
              SizedBox(width: 70, child: TextBox(placeholder: '高', onChanged: (v) => _searchAreaH = int.tryParse(v) ?? 1080)),
            ]),
        ]),
      ),
      const SizedBox(height: 12),

      // Threshold, engine & search button
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: isDark ? const Color(0xFF303050) : const Color(0xFFD0D0E0)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Text('匹配阈值: ', style: TextStyle(fontSize: 13)),
            SizedBox(width: 140, child: Slider(
              value: _matchThreshold,
              min: 0.5, max: 1.0, divisions: 50,
              onChanged: (v) => setState(() => _matchThreshold = v),
            )),
            Text('${(_matchThreshold * 100).toStringAsFixed(0)}%', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            const Text('识别引擎: ', style: TextStyle(fontSize: 13)),
            _buildEngineSelector(VisionCapability.templateMatch, _selectedMatchEngine, (id) => setState(() => _selectedMatchEngine = id)),
            const Spacer(),
            FilledButton(
              onPressed: _template != null && !_searching ? _doImageSearch : null,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                if (_searching)
                  const SizedBox(width: 12, height: 12, child: ProgressRing(strokeWidth: 2))
                else
                  const Icon(FluentIcons.search, size: 14),
                const SizedBox(width: 6),
                Text(_searching ? '搜索中...' : '查找'),
              ]),
            ),
          ]),
        ]),
      ),
      const SizedBox(height: 12),

      // Result
      if (_lastMatch != null)
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF00E676).withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFF00E676).withValues(alpha: 0.3)),
          ),
          child: Row(children: [
            Icon(FluentIcons.completed, size: 16, color: const Color(0xFF00E676)),
            const SizedBox(width: 8),
            Text('找到匹配', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Color(0xFF00E676))),
            const SizedBox(width: 16),
            Text('位置: (${_lastMatch!.x}, ${_lastMatch!.y})  大小: ${_lastMatch!.width}x${_lastMatch!.height}  匹配度: ${(_lastMatch!.score * 100).toStringAsFixed(1)}%',
              style: const TextStyle(fontSize: 12)),
            const Spacer(),
            Button(onPressed: () => setState(() => _lastMatch = null), child: const Text('清除')),
          ]),
        )
      else if (_searching)
        Center(child: Padding(padding: const EdgeInsets.all(20), child: Text('搜索中...', style: TextStyle(fontSize: 13, color: isDark ? const Color(0xFF9090B0) : const Color(0xFF8A8A9A)))))
      else if (_template == null)
        Center(child: Padding(padding: const EdgeInsets.all(32), child: Column(children: [
          const Icon(FluentIcons.image_search, size: 48, color: Colors.grey),
          const SizedBox(height: 12),
          const Text('先截取要查找的图像模板', style: TextStyle(fontSize: 14)),
        ]))),
    ];
  }

  Future<void> _doImageSearch() async {
    if (_template == null) return;
    setState(() => _searching = true);
    try {
      final match = await _vision.findImage(
        regionX: _searchAreaX,
        regionY: _searchAreaY,
        regionW: _searchAreaW,
        regionH: _searchAreaH,
        template: _template!,
        threshold: _matchThreshold,
        pluginId: _selectedMatchEngine,
      );
      if (mounted) setState(() {
        _lastMatch = match;
        _searching = false;
      });
    } catch (_) {
      if (mounted) setState(() => _searching = false);
    }
  }

  // ─── OCR Tab ──────────────────────────────────────────────

  List<Widget> _buildOcrTab(bool isDark, AppState state) {
    final cardBg = isDark ? const Color(0xFF252540).withValues(alpha: 0.5) : const Color(0xFFF0F0FA).withValues(alpha: 0.5);
    return [
      // Area selection
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: isDark ? const Color(0xFF303050) : const Color(0xFFD0D0E0)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(FluentIcons.font, size: 16, color: state.accentColor),
            const SizedBox(width: 8),
            const Text('识别区域', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          ]),
          const SizedBox(height: 12),
          if (_selectingOcrArea)
            _overlayHint('在屏幕上拖拽选择要识别文字的区域')
          else
            Row(children: [
              FilledButton(
                onPressed: () async {
                  setState(() => _selectingOcrArea = true);
                  final sel = await _startAreaSelect();
                  if (sel == null) {
                    if (mounted) setState(() => _selectingOcrArea = false);
                    return;
                  }
                  final (x1, y1, x2, y2) = sel;
                  setState(() {
                    _ocrAreaX = x1;
                    _ocrAreaY = y1;
                    _ocrAreaW = x2 - x1;
                    _ocrAreaH = y2 - y1;
                    _ocrAreaInfo = '($x1, $y1) ${_ocrAreaW}x$_ocrAreaH';
                  });
                },
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(FluentIcons.checkbox_composite, size: 14),
                  const SizedBox(width: 6),
                  Text(_ocrAreaInfo.isNotEmpty ? _ocrAreaInfo : '选择识别区域'),
                ]),
              ),
              const SizedBox(width: 8),
              SizedBox(width: 70, child: TextBox(placeholder: 'X', onChanged: (v) => _ocrAreaX = int.tryParse(v) ?? 0)),
              const SizedBox(width: 6),
              SizedBox(width: 70, child: TextBox(placeholder: 'Y', onChanged: (v) => _ocrAreaY = int.tryParse(v) ?? 0)),
              const SizedBox(width: 6),
              SizedBox(width: 70, child: TextBox(placeholder: '宽', onChanged: (v) => _ocrAreaW = int.tryParse(v) ?? 400)),
              const SizedBox(width: 6),
              SizedBox(width: 70, child: TextBox(placeholder: '高', onChanged: (v) => _ocrAreaH = int.tryParse(v) ?? 200)),
            ]),
          const SizedBox(height: 12),
          Row(children: [
            const Text('语言: ', style: TextStyle(fontSize: 13)),
            ComboBox<String>(
              items: const [
                ComboBoxItem(value: 'zh-Hans-CN', child: Text('简体中文')),
                ComboBoxItem(value: 'zh-Hant-CN', child: Text('繁体中文')),
                ComboBoxItem(value: 'en', child: Text('English')),
                ComboBoxItem(value: 'ja', child: Text('日本語')),
                ComboBoxItem(value: 'ko', child: Text('한국어')),
              ],
              value: _ocrLanguage,
              onChanged: (v) { if (v != null) setState(() => _ocrLanguage = v); },
            ),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            const Text('识别引擎: ', style: TextStyle(fontSize: 13)),
            _buildEngineSelector(VisionCapability.ocr, _selectedOcrEngine, (id) => setState(() => _selectedOcrEngine = id)),
          ]),
          const SizedBox(height: 8),
          // Tesseract OCR install / status
          _buildOcrToolsBar(isDark, state),
          const SizedBox(height: 10),
          Row(children: [
            const Spacer(),
            FilledButton(
              onPressed: !_ocrRunning ? _doOcr : null,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                if (_ocrRunning)
                  const SizedBox(width: 12, height: 12, child: ProgressRing(strokeWidth: 2))
                else
                  const Icon(FluentIcons.font, size: 14),
                const SizedBox(width: 6),
                Text(_ocrRunning ? '识别中...' : '识别文字'),
              ]),
            ),
          ]),
        ]),
      ),
      const SizedBox(height: 12),

      // OCR Result
      if (_lastOcrResult != null)
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _lastOcrResult!.hasError
              ? const Color(0xFFFF5252).withValues(alpha: 0.08)
              : const Color(0xFF00BCD4).withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _lastOcrResult!.hasError
              ? const Color(0xFFFF5252).withValues(alpha: 0.3)
              : const Color(0xFF00BCD4).withValues(alpha: 0.3)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(_lastOcrResult!.hasError ? FluentIcons.warning : FluentIcons.font, size: 16,
                color: _lastOcrResult!.hasError ? const Color(0xFFFF5252) : const Color(0xFF00BCD4)),
              const SizedBox(width: 8),
              Text(_lastOcrResult!.hasError ? '识别失败' : '识别结果',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14,
                  color: _lastOcrResult!.hasError ? const Color(0xFFFF5252) : const Color(0xFF00BCD4))),
              const Spacer(),
              if (_lastOcrResult!.hasText)
                HyperlinkButton(onPressed: () {
                  Clipboard.setData(ClipboardData(text: _lastOcrResult!.text));
                }, child: const Text('复制')),
              Button(onPressed: () => setState(() => _lastOcrResult = null), child: const Text('清除')),
            ]),
            const SizedBox(height: 8),
            if (_lastOcrResult!.hasError)
              Text(_lastOcrResult!.error!, style: const TextStyle(fontSize: 13, color: Color(0xFFFF5252)))
            else if (_lastOcrResult!.hasText)
              SelectableText(_lastOcrResult!.text, style: const TextStyle(fontSize: 14))
            else
              const Text('未识别到文字', style: TextStyle(fontSize: 13)),
          ]),
        )
      else if (!_ocrRunning)
        Center(child: Padding(padding: const EdgeInsets.all(32), child: Column(children: [
          const Icon(FluentIcons.font, size: 48, color: Colors.grey),
          const SizedBox(height: 12),
          const Text('选择区域后识别文字', style: TextStyle(fontSize: 14)),
        ]))),
    ];
  }

  Future<void> _doOcr() async {
    setState(() => _ocrRunning = true);
    try {
      final result = await _vision.ocrRegion(
        x: _ocrAreaX, y: _ocrAreaY, w: _ocrAreaW, h: _ocrAreaH,
        language: _ocrLanguage,
        pluginId: _selectedOcrEngine,
      );
      if (mounted) setState(() {
        _lastOcrResult = result;
        _ocrRunning = false;
      });
    } catch (_) {
      if (mounted) setState(() => _ocrRunning = false);
    }
  }

  // ─── OCR Tools Bar (install / uninstall Tesseract, Python) ──
  Widget _buildOcrToolsBar(bool isDark, AppState state) {
    if (_checkingTools) {
      return const Row(children: [
        SizedBox(width: 14, height: 14, child: ProgressRing(strokeWidth: 2)),
        SizedBox(width: 8),
        Text('检测OCR工具...', style: TextStyle(fontSize: 12)),
      ]);
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('备用OCR工具', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: isDark ? const Color(0xFF9090B0) : const Color(0xFF6A6A7A))),
      const SizedBox(height: 6),
      Wrap(spacing: 8, runSpacing: 6, children: [
        // Tesseract
        _toolChip(
          icon: FluentIcons.processing,
          label: 'Tesseract OCR',
          installed: _tesseractInstalled,
          installing: _installingTool,
          isDark: isDark,
          onInstall: () => _installTool('tesseract'),
          onUninstall: () => _uninstallTool('tesseract'),
        ),
        // Python + pytesseract
        _toolChip(
          icon: FluentIcons.code,
          label: 'Python + pytesseract',
          installed: _pythonInstalled,
          installing: _installingTool,
          isDark: isDark,
          onInstall: () => _installTool('python'),
          onUninstall: () => _uninstallTool('python'),
        ),
      ]),
    ]);
  }

  Widget _toolChip({
    required IconData icon,
    required String label,
    required bool installed,
    required bool installing,
    required bool isDark,
    required VoidCallback onInstall,
    required VoidCallback onUninstall,
  }) {
    final bgColor = installed
      ? const Color(0xFF00BCD4).withValues(alpha: 0.12)
      : isDark ? const Color(0xFF303050) : const Color(0xFFE0E0F0);
    final borderColor = installed
      ? const Color(0xFF00BCD4).withValues(alpha: 0.4)
      : isDark ? const Color(0xFF404060) : const Color(0xFFC0C0D0);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: borderColor),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 14, color: installed ? const Color(0xFF00BCD4) : (isDark ? const Color(0xFF9090B0) : const Color(0xFF6A6A7A))),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(fontSize: 12, color: installed ? const Color(0xFF00BCD4) : null)),
        const SizedBox(width: 8),
        if (installing)
          const SizedBox(width: 12, height: 12, child: ProgressRing(strokeWidth: 2))
        else if (installed)
          Button(
            style: ButtonStyle(padding: WidgetStateProperty.all(const EdgeInsets.symmetric(horizontal: 6, vertical: 2))),
            onPressed: onUninstall,
            child: const Text('卸载', style: TextStyle(fontSize: 11)),
          )
        else
          FilledButton(
            style: ButtonStyle(padding: WidgetStateProperty.all(const EdgeInsets.symmetric(horizontal: 6, vertical: 2))),
            onPressed: onInstall,
            child: const Text('安装', style: TextStyle(fontSize: 11)),
          ),
      ]),
    );
  }

  Future<void> _installTool(String tool) async {
    setState(() => _installingTool = true);
    try {
      await _platformChannel.invokeMethod('installOcrTool', tool);
      await _checkOcrTools();
    } on PlatformException catch (e) {
      if (mounted) {
        showDialog(context: context, builder: (_) => ContentDialog(
          title: const Text('安装失败'),
          content: Text(e.message ?? '未知错误'),
          actions: [Button(child: const Text('确定'), onPressed: () => Navigator.pop(context))],
        ));
      }
    } finally {
      if (mounted) setState(() => _installingTool = false);
    }
  }

  Future<void> _uninstallTool(String tool) async {
    setState(() => _installingTool = true);
    try {
      await _platformChannel.invokeMethod('uninstallOcrTool', tool);
      await _checkOcrTools();
    } on PlatformException {
      // ignore
    } finally {
      if (mounted) setState(() => _installingTool = false);
    }
  }

  // ─── Conditional Triggers ──────────────────────────────────

  List<Widget> _buildTriggers(bool isDark, AppState state) {
    final cardBg = isDark ? const Color(0xFF252540).withValues(alpha: 0.5) : const Color(0xFFF0F0FA).withValues(alpha: 0.5);
    return [
      Row(children: [
        Expanded(child: Button(onPressed: () => _addTrigger(isDark, state), child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(FluentIcons.add, size: 14),
          const SizedBox(width: 6),
          const Text('添加触发条件'),
        ]))),
        const SizedBox(width: 8),
        if (_triggerRunning)
          FilledButton(
            style: ButtonStyle(backgroundColor: WidgetStateProperty.all(Colors.red)),
            onPressed: () { setState(() { _triggerRunning = false; _stopTriggerChecker(); }); },
            child: const Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(FluentIcons.stop, size: 14),
              SizedBox(width: 6),
              Text('停止监控'),
            ]),
          )
        else
          FilledButton(
            onPressed: _triggers.isEmpty ? null : () {
              setState(() { _triggerRunning = true; });
              _startTriggerChecker();
            },
            child: const Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(FluentIcons.play, size: 14),
              SizedBox(width: 6),
              Text('启动监控'),
            ]),
          ),
      ]),
      const SizedBox(height: 12),

      if (_triggers.isEmpty)
        Center(child: Padding(padding: const EdgeInsets.all(32), child: Column(children: [
          const Icon(FluentIcons.process_meta_task, size: 48, color: Colors.grey),
          const SizedBox(height: 12),
          const Text('暂无触发条件', style: TextStyle(fontSize: 14)),
        ])))
      else
        ..._triggers.map((t) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Container(
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
                Expanded(child: Text(t.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14))),
                ToggleSwitch(checked: t.enabled, onChanged: (v) { setState(() => t.enabled = v); _saveTriggers(); if (_triggerRunning) _startTriggerChecker(); }),
                const SizedBox(width: 4),
                IconButton(icon: Icon(FluentIcons.edit, size: 14, color: state.accentColor), onPressed: () async {
                  final result = await showDialog<_TriggerConfig>(context: context, builder: (_) => _AddTriggerDialog(
                    initialX: t.x, initialY: t.y, initialW: t.w, initialH: t.h,
                    onPickActionPos: _startPick,
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
                          actionX: result.actionX, actionY: result.actionY,
                          actionKey: result.actionKey,
                          macroId: result.macroId,
                          intervalMs: result.intervalMs,
                        );
                      }
                    });
                    _saveTriggers();
                    if (_triggerRunning) _startTriggerChecker();
                  }
                }),
                const SizedBox(width: 4),
                IconButton(icon: Icon(FluentIcons.delete, size: 14, color: Colors.red), onPressed: () {
                  setState(() => _triggers.remove(t));
                  _saveTriggers();
                  if (_triggerRunning) _startTriggerChecker();
                }),
              ]),
              const SizedBox(height: 6),
              Row(children: [
                _conditionChip(t.conditionType.label, isDark),
                const SizedBox(width: 6),
                Text('区域: (${t.x}, ${t.y}) ${t.w}x${t.h}', style: TextStyle(fontSize: 12, color: isDark ? const Color(0xFF9090B0) : const Color(0xFF8A8A9A))),
              ]),
              if (t.targetColor != null) ...[
                const SizedBox(height: 4),
                Row(children: [
                  const Text('目标色: ', style: TextStyle(fontSize: 12)),
                  Container(width: 16, height: 16, decoration: BoxDecoration(
                    color: t.targetColor,
                    borderRadius: BorderRadius.circular(3),
                    border: Border.all(color: isDark ? const Color(0xFF404060) : const Color(0xFFD0D0D8)),
                  )),
                ]),
              ],
              if (t.conditionType == _TriggerConditionType.imageMatch) ...[
                const SizedBox(height: 4),
                Row(children: [
                  const Text('模板: ', style: TextStyle(fontSize: 12)),
                  Icon(FluentIcons.image_pixel, size: 12, color: t.templateData != null ? const Color(0xFF00E676) : Colors.grey),
                  const SizedBox(width: 4),
                  Text(t.templateData != null ? '${t.templateData!.width}x${t.templateData!.height}' : '未设置',
                    style: TextStyle(fontSize: 12, color: t.templateData != null ? const Color(0xFF00E676) : Colors.grey)),
                  const SizedBox(width: 8),
                  const Text('阈值: ', style: TextStyle(fontSize: 12)),
                  Text('${(t.matchThreshold * 100).toStringAsFixed(0)}%', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                ]),
              ],
              if (t.conditionType == _TriggerConditionType.textMatch) ...[
                const SizedBox(height: 4),
                Row(children: [
                  const Text('目标文字: ', style: TextStyle(fontSize: 12)),
                  Text(t.targetText.isNotEmpty ? '"${t.targetText}" [${t.textMatchMode.label}]' : '未设置',
                    style: TextStyle(fontSize: 12, color: t.targetText.isNotEmpty ? const Color(0xFF00BCD4) : Colors.grey)),
                ]),
              ],
              const SizedBox(height: 6),
              Row(children: [
                _actionChip(t.actionType.label, isDark),
                const SizedBox(width: 6),
                if (t.actionType == _TriggerActionType.click)
                  Text('点击 (${t.actionX}, ${t.actionY})', style: TextStyle(fontSize: 12, color: isDark ? const Color(0xFF9090B0) : const Color(0xFF8A8A9A)))
                else if (t.actionType == _TriggerActionType.keyPress)
                  Text('按键 ${t.actionKey}', style: TextStyle(fontSize: 12, color: isDark ? const Color(0xFF9090B0) : const Color(0xFF8A8A9A)))
                else if (t.actionType == _TriggerActionType.runMacro)
                  Builder(builder: (context) {
                    final macro = context.read<AppState>().macros.where((m) => m.id == t.macroId).firstOrNull;
                    return Text(macro != null ? '宏: ${macro.name}' : '宏未找到', style: TextStyle(fontSize: 12, color: isDark ? const Color(0xFF9090B0) : const Color(0xFF8A8A9A)));
                  })
                else if (t.actionType == _TriggerActionType.startClicker)
                  const Text('启动连点', style: TextStyle(fontSize: 12))
                else if (t.actionType == _TriggerActionType.stopClicker)
                  const Text('停止连点', style: TextStyle(fontSize: 12)),
              ]),
              const SizedBox(height: 6),
              Row(children: [
                const Text('检查间隔: ', style: TextStyle(fontSize: 12)),
                Text('${t.intervalMs}ms', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                const SizedBox(width: 8),
                Expanded(child: Slider(
                  value: t.intervalMs.toDouble(),
                  min: 100, max: 5000, divisions: 49,
                  onChanged: (v) => setState(() => t.intervalMs = v.round()),
                )),
              ]),
            ]),
          ),
        )),
    ];
  }

  Widget _conditionChip(String label, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFF00BCD4).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: const Color(0xFF00BCD4).withValues(alpha: 0.3)),
      ),
      child: Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF00BCD4))),
    );
  }

  Widget _actionChip(String label, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFFF9800).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: const Color(0xFFFF9800).withValues(alpha: 0.3)),
      ),
      child: Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFFFF9800))),
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
          actionX: result.actionX, actionY: result.actionY,
          actionKey: result.actionKey,
          macroId: result.macroId,
          intervalMs: result.intervalMs,
          enabled: true,
        ));
      });
      _saveTriggers();
      if (_triggerRunning) _startTriggerChecker();
    }
  }

  IconData _logLevelIcon(MonitorLogLevel level) {
    switch (level) {
      case MonitorLogLevel.info: return FluentIcons.info;
      case MonitorLogLevel.detected: return FluentIcons.completed;
      case MonitorLogLevel.changed: return FluentIcons.sync;
      case MonitorLogLevel.error: return FluentIcons.warning;
    }
  }

  Color _logLevelColor(MonitorLogLevel level) {
    switch (level) {
      case MonitorLogLevel.info: return const Color(0xFF9090B0);
      case MonitorLogLevel.detected: return const Color(0xFF00E676);
      case MonitorLogLevel.changed: return const Color(0xFFFFB300);
      case MonitorLogLevel.error: return Colors.red;
    }
  }
}

// ─── Data Classes ────────────────────────────────────────────

class _RegionEntry {
  final String id;
  String name;
  double threshold;
  bool enabled;
  final int x, y, w, h;
  final Color? targetColor;
  Color? lastColor;

  _RegionEntry({
    required this.id, required this.name, required this.threshold,
    required this.enabled, this.x = 0, this.y = 0, this.w = 100, this.h = 100,
    this.targetColor,
  });
}

class _RegionConfig {
  final String name;
  final int x, y, w, h;
  final double threshold;
  final Color? targetColor;
  _RegionConfig({required this.name, required this.x, required this.y, required this.w, required this.h, required this.threshold, this.targetColor});
}

enum _TriggerConditionType { colorMatch, colorChange, colorDisappear, imageMatch, textMatch }
extension on _TriggerConditionType {
  String get label {
    switch (this) {
      case _TriggerConditionType.colorMatch: return '颜色匹配';
      case _TriggerConditionType.colorChange: return '颜色变化';
      case _TriggerConditionType.colorDisappear: return '颜色消失';
      case _TriggerConditionType.imageMatch: return '图像匹配';
      case _TriggerConditionType.textMatch: return '文字匹配';
    }
  }
}

enum _TriggerActionType { click, keyPress, startClicker, stopClicker, runMacro }
extension on _TriggerActionType {
  String get label {
    switch (this) {
      case _TriggerActionType.click: return '点击';
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
  final int actionX, actionY;
  final String actionKey;
  final String macroId;
  int intervalMs;

  _TriggerEntry({
    required this.id, required this.name, required this.conditionType,
    required this.actionType, required this.enabled,
    this.x = 0, this.y = 0, this.w = 100, this.h = 100,
    this.targetColor, this.templateData, this.matchThreshold = 0.8,
    this.targetText = '',
    this.textMatchMode = _TextMatchMode.fuzzy,
    this.actionX = 0, this.actionY = 0,
    this.actionKey = '', this.macroId = '',
    this.intervalMs = 500,
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
  final int actionX, actionY;
  final String actionKey;
  final String macroId;
  final int intervalMs;
  _TriggerConfig({
    required this.name, required this.conditionType, required this.actionType,
    required this.x, required this.y, required this.w, required this.h,
    this.targetColor, this.templateData, this.matchThreshold = 0.8,
    this.targetText = '',
    this.textMatchMode = _TextMatchMode.fuzzy,
    this.actionX = 0, this.actionY = 0,
    this.actionKey = '', this.macroId = '',
    this.intervalMs = 500,
  });
}

// ─── Add Region Dialog ──────────────────────────────────────

class _AddRegionDialog extends StatefulWidget {
  final int initialX, initialY, initialW, initialH;
  const _AddRegionDialog({
    this.initialX = 0, this.initialY = 0,
    this.initialW = 100, this.initialH = 100,
  });
  @override
  State<_AddRegionDialog> createState() => _AddRegionDialogState();
}

class _AddRegionDialogState extends State<_AddRegionDialog> {
  late int _x, _y, _w, _h;
  double _threshold = 0.85;
  Color? _targetColor;
  String _colorInfo = '';

  @override
  void initState() {
    super.initState();
    _x = widget.initialX;
    _y = widget.initialY;
    _w = widget.initialW;
    _h = widget.initialH;
  }

  @override
  void dispose() {
    // Don't set handler here — main page owns it
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ContentDialog(
      title: const Text('添加监控区域'),
      content: SizedBox(width: 380, child: Column(mainAxisSize: MainAxisSize.min, children: [
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
        const SizedBox(height: 12),
        Row(children: [
          SizedBox(width: 70, child: TextBox(placeholder: 'X', onChanged: (v) => _x = int.tryParse(v) ?? _x)),
          const SizedBox(width: 6),
          SizedBox(width: 70, child: TextBox(placeholder: 'Y', onChanged: (v) => _y = int.tryParse(v) ?? _y)),
          const SizedBox(width: 6),
          SizedBox(width: 70, child: TextBox(placeholder: '宽', onChanged: (v) => _w = int.tryParse(v) ?? _w)),
          const SizedBox(width: 6),
          SizedBox(width: 70, child: TextBox(placeholder: '高', onChanged: (v) => _h = int.tryParse(v) ?? _h)),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          const Text('阈值: ', style: TextStyle(fontSize: 13)),
          Expanded(child: Slider(value: _threshold, min: 0.5, max: 1.0, divisions: 50, onChanged: (v) => setState(() => _threshold = v))),
          const SizedBox(width: 8),
          Text('${(_threshold * 100).toStringAsFixed(0)}%', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        ]),
      ])),
      actions: [
        Button(onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton(onPressed: () => Navigator.pop(context, _RegionConfig(
          name: '监控区域', x: _x, y: _y, w: _w, h: _h,
          threshold: _threshold, targetColor: _targetColor,
        )), child: const Text('添加')),
      ],
    );
  }
}

// ─── Add Trigger Dialog ─────────────────────────────────────

class _AddTriggerDialog extends StatefulWidget {
  final int initialX, initialY, initialW, initialH;
  final Future<(int, int)?> Function()? onPickActionPos;
  final _TriggerEntry? initialTrigger; // null = add mode, non-null = edit mode
  const _AddTriggerDialog({
    this.initialX = 0, this.initialY = 0,
    this.initialW = 100, this.initialH = 100,
    this.onPickActionPos,
    this.initialTrigger,
  });
  @override
  State<_AddTriggerDialog> createState() => _AddTriggerDialogState();
}

class _AddTriggerDialogState extends State<_AddTriggerDialog> {
  _TriggerConditionType _conditionType = _TriggerConditionType.colorMatch;
  _TriggerActionType _actionType = _TriggerActionType.click;
  late int _x, _y, _w, _h;
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
      _actionX = t.actionX; _actionY = t.actionY;
      _actionKey = t.actionKey;
      _macroId = t.macroId;
      _intervalMs = t.intervalMs;
    } else {
      _x = widget.initialX;
      _y = widget.initialY;
      _w = widget.initialW;
      _h = widget.initialH;
    }
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
          onChanged: (v) { if (v != null) setState(() => _conditionType = v); },
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
          SizedBox(width: 70, child: TextBox(placeholder: 'X', onChanged: (v) => _x = int.tryParse(v) ?? _x)),
          const SizedBox(width: 6),
          SizedBox(width: 70, child: TextBox(placeholder: 'Y', onChanged: (v) => _y = int.tryParse(v) ?? _y)),
          const SizedBox(width: 6),
          SizedBox(width: 70, child: TextBox(placeholder: '宽', onChanged: (v) => _w = int.tryParse(v) ?? _w)),
          const SizedBox(width: 6),
          SizedBox(width: 70, child: TextBox(placeholder: '高', onChanged: (v) => _h = int.tryParse(v) ?? _h)),
        ]),

        // Image match specific: threshold
        if (_conditionType == _TriggerConditionType.imageMatch) ...[
          const SizedBox(height: 8),
          Row(children: [
            const Text('匹配阈值: ', style: TextStyle(fontSize: 13)),
            Expanded(child: Slider(value: _matchThreshold, min: 0.5, max: 1.0, divisions: 50, onChanged: (v) => setState(() => _matchThreshold = v))),
            const SizedBox(width: 8),
            Text('${(_matchThreshold * 100).toStringAsFixed(0)}%', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          ]),
          const SizedBox(height: 4),
          Text('保存触发条件后，将在监控区域内查找匹配的图像模板', style: const TextStyle(fontSize: 11, color: Color(0xFF9090B0))),
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
          Expanded(child: Slider(value: _intervalMs.toDouble(), min: 100, max: 5000, divisions: 49, onChanged: (v) => setState(() => _intervalMs = v.round()))),
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
          matchThreshold: _matchThreshold,
          targetText: _targetText,
          textMatchMode: _textMatchMode,
          actionX: _actionX, actionY: _actionY,
          actionKey: _actionKey,
          macroId: _macroId,
          intervalMs: _intervalMs,
        )), child: Text(_isEditing ? '保存' : '添加')),
      ],
    );
  }
}
