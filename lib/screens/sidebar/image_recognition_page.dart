/// Image recognition page — screen monitoring, image search, OCR, conditional triggers.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
import '../../services/plugin_registry.dart';
import '../../services/plugin_system.dart';
import '../../services/plugins/ai_tracker_plugin.dart';
import '../../services/screen_overlay_service.dart';

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

  // OCR state (used by trigger textMatch)
  String _ocrLanguage = 'zh-Hans-CN';

  // OCR tools install state
  bool _tesseractInstalled = false;
  bool _pythonInstalled = false;
  bool _checkingTools = true;
  bool _installingTool = false;
  bool _initialized = false;

  // Conditional triggers
  final List<_TriggerEntry> _triggers = [];
  Timer? _triggerCheckTimer;
  final Map<String, DateTime> _triggerLastFired = {};

  static const _platformChannel = MethodChannel('com.clicker.pro/platform');

  @override
  void initState() {
    super.initState();
    _monitor.onLogEntry = (_) { if (mounted) setState(() {}); };
    _monitor.onMonitoringChanged = (_) { if (mounted) setState(() {}); };

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
    if (mounted) _checkOcrTools();
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
    _stopTriggerChecker();
    ScreenOverlayService.instance.stopOverlay();
    _monitor.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = FluentTheme.of(context).brightness == Brightness.dark;

    if (!_initialized) {
      // Use read() instead of watch() during loading to avoid unnecessary rebuilds
      final config = context.read<AppState>().clickerConfig;
      if (!config.imageRecognitionEnabled) {
        return ScaffoldPage(
          content: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(FluentIcons.image_pixel, size: 48, color: Colors.grey),
            const SizedBox(height: 12),
            const Text('图像识别未启用', style: TextStyle(fontSize: 16)),
          ])),
        );
      }
      return ScaffoldPage(
        content: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(width: 32, height: 32, child: ProgressRing()),
          const SizedBox(height: 16),
          Text('正在初始化图像识别...', style: TextStyle(fontSize: 14, color: isDark ? const Color(0xFF9090B0) : const Color(0xFF6A6A7A))),
        ])),
      );
    }

    final state = context.watch<AppState>();

    if (!state.clickerConfig.imageRecognitionEnabled) {
      return ScaffoldPage(
        content: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(FluentIcons.image_pixel, size: 48, color: Colors.grey),
          const SizedBox(height: 12),
          const Text('图像识别未启用', style: TextStyle(fontSize: 16)),
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
          _tabChip('条件触发', _selectedTab == 1, () => setState(() => _selectedTab = 1)),
          const SizedBox(width: 6),
          _tabChip('AI检测', _selectedTab == 2, () => setState(() => _selectedTab = 2)),
        ]),
        const SizedBox(height: 16),

        if (_selectedTab == 0) ..._buildRegionMonitor(isDark, state),
        if (_selectedTab == 1) ..._buildTriggers(isDark, state),
        if (_selectedTab == 2) _AiTrackerTab(onAreaSelect: _startAreaSelect),
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

class _AiTrackerTab extends StatefulWidget {
  final Future<(int, int, int, int)?> Function() onAreaSelect;
  const _AiTrackerTab({required this.onAreaSelect});

  @override
  State<_AiTrackerTab> createState() => _AiTrackerTabState();
}

class _AiTrackerTabState extends State<_AiTrackerTab> {
  bool _checking = true;
  bool _downloading = false;
  String _downloadStatus = '';
  double _downloadProgress = 0;
  String _downloadSize = '';
  String _errorMsg = '';
  String _currentSource = 'GitHub';

  bool _onnxExists = false;
  bool _modelExists = false;

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

  static const _cocoClasses = [
    'person', 'bicycle', 'car', 'motorcycle', 'airplane', 'bus', 'train', 'truck', 'boat',
    'traffic light', 'fire hydrant', 'stop sign', 'parking meter', 'bench', 'bird', 'cat',
    'dog', 'horse', 'sheep', 'cow', 'elephant', 'bear', 'zebra', 'giraffe', 'backpack',
    'umbrella', 'handbag', 'tie', 'suitcase', 'frisbee', 'skis', 'snowboard', 'sports ball',
    'kite', 'baseball bat', 'baseball glove', 'skateboard', 'surfboard', 'tennis racket',
    'bottle', 'wine glass', 'cup', 'fork', 'knife', 'spoon', 'bowl', 'banana', 'apple',
    'sandwich', 'orange', 'broccoli', 'carrot', 'hot dog', 'pizza', 'donut', 'cake', 'chair',
    'couch', 'potted plant', 'bed', 'dining table', 'toilet', 'tv', 'laptop', 'mouse',
    'remote', 'keyboard', 'cell phone', 'microwave', 'oven', 'toaster', 'sink', 'refrigerator',
    'book', 'clock', 'vase', 'scissors', 'teddy bear', 'hair drier', 'toothbrush',
  ];

  static const _cocoClassZh = <String, String>{
    'person': '人', 'bicycle': '自行车', 'car': '汽车', 'motorcycle': '摩托车',
    'airplane': '飞机', 'bus': '公交车', 'train': '火车', 'truck': '卡车', 'boat': '船',
    'traffic light': '红绿灯', 'fire hydrant': '消防栓', 'stop sign': '停车标志',
    'parking meter': '停车计时器', 'bench': '长椅', 'bird': '鸟', 'cat': '猫',
    'dog': '狗', 'horse': '马', 'sheep': '羊', 'cow': '牛', 'elephant': '大象',
    'bear': '熊', 'zebra': '斑马', 'giraffe': '长颈鹿', 'backpack': '背包',
    'umbrella': '雨伞', 'handbag': '手提包', 'tie': '领带', 'suitcase': '行李箱',
    'frisbee': '飞盘', 'skis': '滑雪板', 'snowboard': '单板', 'sports ball': '球',
    'kite': '风筝', 'baseball bat': '棒球棒', 'baseball glove': '棒球手套',
    'skateboard': '滑板', 'surfboard': '冲浪板', 'tennis racket': '网球拍',
    'bottle': '瓶子', 'wine glass': '酒杯', 'cup': '杯子', 'fork': '叉子',
    'knife': '刀', 'spoon': '勺子', 'bowl': '碗', 'banana': '香蕉', 'apple': '苹果',
    'sandwich': '三明治', 'orange': '橙子', 'broccoli': '西兰花', 'carrot': '胡萝卜',
    'hot dog': '热狗', 'pizza': '披萨', 'donut': '甜甜圈', 'cake': '蛋糕', 'chair': '椅子',
    'couch': '沙发', 'potted plant': '盆栽', 'bed': '床', 'dining table': '餐桌',
    'toilet': '马桶', 'tv': '电视', 'laptop': '笔记本电脑', 'mouse': '鼠标',
    'remote': '遥控器', 'keyboard': '键盘', 'cell phone': '手机', 'microwave': '微波炉',
    'oven': '烤箱', 'toaster': '烤面包机', 'sink': '水槽', 'refrigerator': '冰箱',
    'book': '书', 'clock': '时钟', 'vase': '花瓶', 'scissors': '剪刀',
    'teddy bear': '泰迪熊', 'hair drier': '吹风机', 'toothbrush': '牙刷',
  };

  final List<String> _targetClasses = [];
  double _confidence = 0.5;
  int _checkIntervalMs = 500;
  bool _autoClick = true;
  bool _showTrackBox = false;
  bool _detecting = false;
  Timer? _detectTimer;
  int _detectRegionX = 0;
  int _detectRegionY = 0;
  int _detectRegionW = 0;
  int _detectRegionH = 0;
  bool _hasRegion = false;
  final List<_DetectionResult> _lastResults = [];
  int _detectionCount = 0;
  int _clickCount = 0;

  static const _platformChannel = MethodChannel('com.clicker.pro/platform');

  @override
  void initState() {
    super.initState();
    _checkDependencies();
  }

  @override
  void dispose() {
    _stopDetection();
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
    setState(() => _checking = true);
    final dir = await _getPluginDir();
    _pluginDir = dir;

    _onnxExists = await File('$dir\\onnxruntime.dll').exists();
    _modelExists = await File('$dir\\models\\yolo11n.onnx').exists();
    _dllDeployed = await _deployNativePlugin();

    setState(() => _checking = false);
  }

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
        setState(() => _selectedMirror = mirror);
        return mirror;
      } catch (e) {
        lastError = e.toString().replaceFirst('Exception: ', '');
        final file = File(savePath);
        if (await file.exists()) {
          try { await file.delete(); } catch (_) {}
        }
        if (mirror != order.last) {
          setState(() {
            _downloadStatus = '源 $mirror 失败，尝试下一个镜像...';
          });
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
    } catch (e) {
      _errorMsg = e.toString().replaceFirst('Exception: ', '');
      _downloadStatus = '安装失败';
    }

    setState(() => _downloading = false);
  }

  Future<void> _downloadModel() async {
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
    } catch (e) {
      _errorMsg = e.toString().replaceFirst('Exception: ', '');
      _downloadStatus = '下载失败';
    }

    setState(() => _downloading = false);
  }

  Future<void> _downloadAll() async {
    if (!_onnxExists) await _downloadOnnxRuntime();
    if (!_modelExists && _errorMsg.isEmpty) await _downloadModel();
    setState(() {});
  }

  Future<void> _uninstallAll() async {
    _stopDetection();

    final aiPlugin = _getAiTrackerPlugin();
    if (aiPlugin != null) {
      aiPlugin.unloadNative();
    }

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
      _modelLoaded = false;
      _dllDeployed = false;
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

  Future<void> _selectDetectRegion() async {
    final sel = await widget.onAreaSelect();
    if (sel == null) return;
    final (x1, y1, x2, y2) = sel;
    setState(() {
      _detectRegionX = x1;
      _detectRegionY = y1;
      _detectRegionW = x2 - x1;
      _detectRegionH = y2 - y1;
      _hasRegion = true;
    });
  }

  void _useFullScreen() async {
    try {
      final result = await _platformChannel.invokeMethod<Map>('getScreenSize');
      if (result != null) {
        setState(() {
          _detectRegionX = 0;
          _detectRegionY = 0;
          _detectRegionW = result['width'] as int;
          _detectRegionH = result['height'] as int;
          _hasRegion = true;
        });
      }
    } on PlatformException {}
  }

  bool _modelLoaded = false;

  void _startDetection() {
    if (!_hasRegion) return;
    setState(() {
      _detecting = true;
      _detectionCount = 0;
      _clickCount = 0;
      _lastResults.clear();
    });

    _ensureModelLoaded().then((_) {
      _detectTimer = Timer.periodic(Duration(milliseconds: _checkIntervalMs), (_) {
        _runDetection();
      });
    });
  }

  AiTrackerPlugin? _getAiTrackerPlugin() {
    final registry = PluginRegistry.instance;
    final plugin = registry.getPlugin('ai_tracker');
    if (plugin is AiTrackerPlugin) return plugin;
    return null;
  }

  Future<void> _ensureModelLoaded() async {
    if (_modelLoaded) return;
    if (!_onnxExists || !_modelExists) {
      debugPrint('[AI] 组件未就绪: onnx=$_onnxExists model=$_modelExists');
      return;
    }

    final aiPlugin = _getAiTrackerPlugin();
    if (aiPlugin == null) {
      debugPrint('[AI] 插件未注册');
      return;
    }

    if (!aiPlugin.nativeLoaded) {
      debugPrint('[AI] 尝试加载原生插件...');
      final loaded = aiPlugin.loadNative();
      debugPrint('[AI] 原生插件加载: $loaded');
      if (!loaded) {
        debugPrint('[AI] 原生DLL加载失败，请确认 ai_tracker.dll 已部署到 data/plugins/ai_tracker/windows/');
        debugPrint('[AI] _pluginDir=$_pluginDir');
        return;
      }
    }

    final statusResult = aiPlugin.executeAction('get_status', '{}', returnOnError: true);
    debugPrint('[AI] 插件状态: $statusResult');

    if (statusResult == null) {
      debugPrint('[AI] 无法获取插件状态，原生调用失败');
      return;
    }

    if (statusResult.contains('"available":false')) {
      debugPrint('[AI] ONNX Runtime 未加载，尝试重新初始化');
      aiPlugin.unloadNative();
      if (!aiPlugin.loadNative()) {
        debugPrint('[AI] 重新加载失败');
        return;
      }
      final retryStatus = aiPlugin.executeAction('get_status', '{}', returnOnError: true);
      debugPrint('[AI] 重试状态: $retryStatus');
      if (retryStatus == null || retryStatus.contains('"available":false')) {
        debugPrint('[AI] ONNX Runtime 仍不可用');
        return;
      }
    }

    final modelFile = File('$_pluginDir${Platform.pathSeparator}models${Platform.pathSeparator}yolo11n.onnx');
    if (!await modelFile.exists()) {
      debugPrint('[AI] 模型文件不存在: ${modelFile.path}');
      return;
    }

    final modelPath = modelFile.path;
    debugPrint('[AI] 加载模型: $modelPath');
    final result = aiPlugin.executeAction('load_model', '{"model_path":"${modelPath.replaceAll('\\', '\\\\')}"}', returnOnError: true);
    debugPrint('[AI] 模型加载结果: $result');
    if (result != null && result.contains('"success":true')) {
      _modelLoaded = true;
    }
  }

  void _stopDetection() {
    _detectTimer?.cancel();
    _detectTimer = null;
    ScreenOverlayService.instance.stopOverlay();
    if (mounted) {
      setState(() => _detecting = false);
    }
  }

  Future<void> _runDetection() async {
    if (!_hasRegion || !mounted) return;

    try {
      final pixels = await _platformChannel.invokeMethod<Uint8List>(
        'captureScreenRect',
        [_detectRegionX, _detectRegionY, _detectRegionW, _detectRegionH],
      );
      if (pixels == null) {
        debugPrint('[AI] 截图失败: 返回null');
        return;
      }
      if (pixels.length < 4) {
        debugPrint('[AI] 截图数据异常: length=${pixels.length}');
        return;
      }

      List<_DetectionResult> nativeResults = [];

      if (_modelLoaded && _onnxExists && _modelExists) {
        nativeResults = await _runNativeDetection(pixels);
      } else {
        debugPrint('[AI] 原生检测不可用: modelLoaded=$_modelLoaded onnx=$_onnxExists model=$_modelExists');
      }

      if (nativeResults.isEmpty) {
        final pluginManager = VisionPluginManager.instance;
        final detector = pluginManager.getPluginForCapability(VisionCapability.objectDetect);
        if (detector != null) {
          await pluginManager.ensureInitialized(detector.info.id);
          for (final targetLabel in _targetClasses) {
            final det = await detector.detectObjects(
              regionX: _detectRegionX,
              regionY: _detectRegionY,
              regionW: _detectRegionW,
              regionH: _detectRegionH,
              targetLabel: targetLabel,
              confidence: _confidence,
            );
            for (final r in det) {
              nativeResults.add(_DetectionResult(
                x: r.x + _detectRegionX,
                y: r.y + _detectRegionY,
                width: r.width,
                height: r.height,
                score: r.score,
                label: r.label ?? 'object',
              ));
            }
          }
        }
      }

      setState(() {
        _lastResults.clear();
        _lastResults.addAll(nativeResults);
        _detectionCount++;
      });

      if (_showTrackBox && _lastResults.isNotEmpty) {
        final boxes = _lastResults.map((r) => <String, dynamic>{
          'x': r.x,
          'y': r.y,
          'w': r.width,
          'h': r.height,
          'confidence': r.score,
          'class_id': r.classId,
          'class_name': _cocoClassZh[r.label] ?? r.label,
        }).toList();
        if (ScreenOverlayService.instance.overlayActive) {
          ScreenOverlayService.instance.updateDetectionBoxes(boxes);
        } else {
          ScreenOverlayService.instance.showDetectionBoxes(boxes);
        }
      } else if (_showTrackBox && _lastResults.isEmpty) {
        ScreenOverlayService.instance.stopOverlay();
      }

      if (_autoClick && _lastResults.isNotEmpty) {
        final best = _lastResults.first;
        final clickX = best.x + best.width ~/ 2;
        final clickY = best.y + best.height ~/ 2;
        await _platformChannel.invokeMethod('sendClick', [clickX, clickY, 0]);
        setState(() => _clickCount++);
      }
    } catch (e) {
      debugPrint('[AI] _runDetection异常: $e');
    }
  }

  Future<List<_DetectionResult>> _runNativeDetection(Uint8List pixels) async {
    final aiPlugin = _getAiTrackerPlugin();
    if (aiPlugin == null) {
      debugPrint('[AI] 检测失败: 插件未注册');
      return [];
    }
    if (!aiPlugin.nativeLoaded) {
      debugPrint('[AI] 检测失败: 原生插件未加载');
      return [];
    }

    final expectedLen = _detectRegionW * _detectRegionH * 4;
    if (pixels.length != expectedLen) {
      debugPrint('[AI] 像素数据大小不匹配: got=${pixels.length} expected=$expectedLen (${_detectRegionW}x$_detectRegionH*4)');
      return [];
    }

    final pixelPtr = malloc<Uint8>(pixels.length);
    try {
      pixelPtr.asTypedList(pixels.length).setAll(0, pixels);

      final ptrHex = pixelPtr.address.toRadixString(16);
      final targetClass = '';

      final params = '{"region_w":$_detectRegionW,'
          '"region_h":$_detectRegionH,'
          '"confidence":$_confidence,'
          '"pixel_data_ptr":"$ptrHex",'
          '"target_class":"$targetClass"}';

      debugPrint('[AI] 检测参数: region=${_detectRegionW}x$_detectRegionH conf=$_confidence target=$targetClass ptr=$ptrHex pixels=${pixels.length} expected=${_detectRegionW * _detectRegionH * 4}');

      final resultJson = aiPlugin.executeAction('detect_objects', params, returnOnError: true);
      debugPrint('[AI] 检测结果: $resultJson');

      if (resultJson == null) {
        debugPrint('[AI] 检测返回null');
        return [];
      }

      if (resultJson.contains('"error"')) {
        debugPrint('[AI] 检测错误: $resultJson');
        return [];
      }

      return _parseDetectionResults(resultJson);
    } catch (e) {
      debugPrint('[AI] 检测异常: $e');
      return [];
    } finally {
      malloc.free(pixelPtr);
    }
  }

  List<_DetectionResult> _parseDetectionResults(String jsonStr) {
    final results = <_DetectionResult>[];
    try {
      final decoded = jsonDecode(jsonStr);
      if (decoded is! Map) return results;
      final detections = decoded['detections'];
      if (detections is! List) return results;

      for (final det in detections) {
        if (det is! Map) continue;
        final className = det['class_name'] as String? ?? '';
        if (_targetClasses.isNotEmpty && !_targetClasses.contains(className)) continue;

        results.add(_DetectionResult(
          x: (det['x'] as num).toInt() + _detectRegionX,
          y: (det['y'] as num).toInt() + _detectRegionY,
          width: (det['w'] as num).toInt(),
          height: (det['h'] as num).toInt(),
          score: (det['confidence'] as num).toDouble(),
          label: className,
          classId: (det['class_id'] as num?)?.toInt() ?? 0,
        ));
      }
    } catch (e) {
      debugPrint('[AI] 解析检测结果异常: $e');
    }
    return results;
  }

  void _addClass(String cls) {
    if (!_targetClasses.contains(cls)) {
      setState(() => _targetClasses.add(cls));
    }
  }

  void _removeClass(String cls) {
    setState(() => _targetClasses.remove(cls));
  }

  @override
  Widget build(BuildContext context) {
    final isDark = FluentTheme.of(context).brightness == Brightness.dark;
    final accent = FluentTheme.of(context).accentColor;
    final allReady = _onnxExists && _modelExists;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (_checking)
        const Center(child: ProgressRing())
      else if (!allReady) ...[
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
          _buildDepCard(
            icon: FluentIcons.processing,
            name: 'ONNX Runtime v$_ortVersion',
            desc: 'Microsoft 推理引擎 · ~200MB',
            installed: _onnxExists,
            isDark: isDark,
            accent: accent,
            onInstall: _downloading ? null : _downloadOnnxRuntime,
          ),
          _buildDepCard(
            icon: FluentIcons.machine_learning,
            name: 'YOLO11n 模型',
            desc: 'Ultralytics 目标检测模型 · ~6MB',
            installed: _modelExists,
            isDark: isDark,
            accent: accent,
            onInstall: _downloading ? null : _downloadModel,
          ),
        ]),

        const SizedBox(height: 16),

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

        const SizedBox(height: 20),

        _buildSection('插件目录', isDark, [
          Button(
            onPressed: _openPluginDir,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(FluentIcons.folder_open, size: 12, color: accent),
              const SizedBox(width: 6),
              Text('打开目录', style: TextStyle(fontSize: 12, color: accent)),
            ]),
          ),
          const SizedBox(height: 6),
          Text(_pluginDir, style: TextStyle(fontSize: 11, color: isDark ? const Color(0xFF707090) : const Color(0xFFA0A0B0))),
        ]),
      ] else ...[
        _buildSection('检测区域', isDark, [
          Row(children: [
            Button(
              onPressed: _detecting ? null : _selectDetectRegion,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(FluentIcons.crop, size: 12, color: accent),
                const SizedBox(width: 6),
                Text('框选区域', style: TextStyle(fontSize: 12, color: accent)),
              ]),
            ),
            const SizedBox(width: 8),
            Button(
              onPressed: _detecting ? null : _useFullScreen,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(FluentIcons.full_screen, size: 12, color: accent),
                const SizedBox(width: 6),
                Text('全屏', style: TextStyle(fontSize: 12, color: accent)),
              ]),
            ),
          ]),
          if (_hasRegion) ...[
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: isDark ? const Color(0x80252540) : const Color(0x80F0F0FA),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: isDark ? const Color(0xFF303050) : const Color(0xFFD0D0E0)),
              ),
              child: Text(
                '区域: ($_detectRegionX, $_detectRegionY) ${_detectRegionW}×$_detectRegionH',
                style: TextStyle(fontSize: 12, color: isDark ? const Color(0xFF9090B0) : const Color(0xFF8A8A9A)),
              ),
            ),
          ],
        ]),

        _buildSection('目标类别', isDark, [
          Wrap(spacing: 4, runSpacing: 4, children: [
            ..._targetClasses.map((cls) => Button(
              onPressed: () => _removeClass(cls),
              style: ButtonStyle(
                backgroundColor: WidgetStatePropertyAll(accent.withValues(alpha: 0.15)),
                padding: WidgetStatePropertyAll(const EdgeInsets.symmetric(horizontal: 8, vertical: 2)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(_cocoClassZh[cls] ?? cls, style: TextStyle(fontSize: 11, color: accent, fontWeight: FontWeight.w600)),
                const SizedBox(width: 4),
                Icon(FluentIcons.cancel, size: 8, color: accent),
              ]),
            )),
            Button(
              onPressed: _detecting ? null : () => _showClassPicker(context, isDark, accent),
              style: ButtonStyle(
                padding: WidgetStatePropertyAll(const EdgeInsets.symmetric(horizontal: 8, vertical: 4)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(FluentIcons.add, size: 10, color: accent),
                const SizedBox(width: 4),
                Text('添加', style: TextStyle(fontSize: 11, color: accent)),
              ]),
            ),
          ]),
        ]),

        _buildSection('参数设置', isDark, [
          Row(children: [
            const Text('置信度: ', style: TextStyle(fontSize: 12)),
            Expanded(child: Slider(
              value: _confidence,
              min: 0.1, max: 0.95, divisions: 17,
              onChanged: _detecting ? null : (v) => setState(() => _confidence = v),
            )),
            const SizedBox(width: 8),
            Text(_confidence.toStringAsFixed(2), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            const Text('检查间隔: ', style: TextStyle(fontSize: 12)),
            Expanded(child: Slider(
              value: _checkIntervalMs.toDouble(),
              min: 100, max: 3000, divisions: 29,
              onChanged: _detecting ? null : (v) => setState(() => _checkIntervalMs = v.round()),
            )),
            const SizedBox(width: 8),
            Text('$_checkIntervalMs ms', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Checkbox(
              checked: _autoClick,
              onChanged: _detecting ? null : (v) => setState(() => _autoClick = v ?? true),
            ),
            const SizedBox(width: 8),
            const Text('检测到目标后自动点击', style: TextStyle(fontSize: 12)),
          ]),
          const SizedBox(height: 4),
          Row(children: [
            Checkbox(
              checked: _showTrackBox,
              onChanged: (v) {
                setState(() => _showTrackBox = v ?? false);
                if (!_showTrackBox || !_detecting) {
                  ScreenOverlayService.instance.stopOverlay();
                }
              },
            ),
            const SizedBox(width: 8),
            const Text('显示追踪框', style: TextStyle(fontSize: 12)),
          ]),
        ]),

        const SizedBox(height: 16),

        Row(children: [
          if (!_detecting)
            FilledButton(
              onPressed: _hasRegion ? _startDetection : null,
              style: ButtonStyle(
                backgroundColor: WidgetStatePropertyAll(accent.withValues(alpha: 0.15)),
                padding: WidgetStatePropertyAll(const EdgeInsets.symmetric(horizontal: 20, vertical: 10)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(FluentIcons.play, size: 14, color: accent),
                const SizedBox(width: 8),
                Text('开始检测', style: TextStyle(color: accent, fontSize: 13, fontWeight: FontWeight.w600)),
              ]),
            ),
          if (_detecting)
            FilledButton(
              onPressed: _stopDetection,
              style: ButtonStyle(
                backgroundColor: const WidgetStatePropertyAll(Color(0x1FFF0000)),
                padding: WidgetStatePropertyAll(const EdgeInsets.symmetric(horizontal: 20, vertical: 10)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(FluentIcons.stop, size: 14, color: const Color(0xCCFF0000)),
                const SizedBox(width: 8),
                Text('停止检测', style: const TextStyle(color: Color(0xCCFF0000), fontSize: 13, fontWeight: FontWeight.w600)),
              ]),
            ),
          const SizedBox(width: 12),
          if (_detecting)
            Container(
              width: 8, height: 8,
              decoration: BoxDecoration(
                color: const Color(0xFF00E676),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          if (_detecting) ...[
            const SizedBox(width: 6),
            Text('检测中...', style: TextStyle(fontSize: 12, color: isDark ? const Color(0xFF9090B0) : const Color(0xFF8A8A9A))),
          ],
        ]),

        if (_detectionCount > 0 || _lastResults.isNotEmpty) ...[
          const SizedBox(height: 16),
          _buildSection('检测结果', isDark, [
            Row(children: [
              _statChip('检测次数', '$_detectionCount', isDark),
              const SizedBox(width: 8),
              _statChip('当前目标', '${_lastResults.length}', isDark),
              const SizedBox(width: 8),
              _statChip('点击次数', '$_clickCount', isDark),
            ]),
            if (_lastResults.isNotEmpty) ...[
              const SizedBox(height: 8),
              ..._lastResults.take(5).map((r) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0x80252540) : const Color(0x80F0F0FA),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: isDark ? const Color(0xFF303050) : const Color(0xFFD0D0E0)),
                  ),
                  child: Row(children: [
                    Icon(FluentIcons.bullseye, size: 12, color: accent),
                    const SizedBox(width: 8),
                    Text(_cocoClassZh[r.label] ?? r.label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                    const SizedBox(width: 8),
                    Text('(${r.x}, ${r.y}) ${r.width}×${r.height}', style: TextStyle(fontSize: 11, color: isDark ? const Color(0xFF9090B0) : const Color(0xFF8A8A9A))),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: const Color(0x1F00E676),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text('${(r.score * 100).toStringAsFixed(0)}%', style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: Color(0xFF00E676))),
                    ),
                  ]),
                ),
              )),
              if (_lastResults.length > 5)
                Text('...还有 ${_lastResults.length - 5} 个结果', style: TextStyle(fontSize: 11, color: isDark ? const Color(0xFF707090) : const Color(0xFFA0A0B0))),
            ] else if (_detectionCount > 0) ...[
              const SizedBox(height: 4),
              Text('未检测到目标', style: TextStyle(fontSize: 12, color: isDark ? const Color(0xFF707090) : const Color(0xFFA0A0B0))),
            ],
          ]),
        ],

        const SizedBox(height: 20),

        _buildSection('管理', isDark, [
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
              onPressed: _detecting ? null : _uninstallAll,
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
        ]),
      ],
    ]);
  }

  void _showClassPicker(BuildContext context, bool isDark, Color accent) {
    final filtered = _cocoClasses.where((c) => !_targetClasses.contains(c)).toList();
    showDialog(
      context: context,
      builder: (ctx) => ContentDialog(
        title: const Text('选择目标类别'),
        constraints: const BoxConstraints(maxWidth: 400, maxHeight: 500),
        content: SizedBox(
          width: 360,
          height: 400,
          child: ListView.builder(
            itemCount: filtered.length,
            itemBuilder: (_, i) {
              final cls = filtered[i];
              final zh = _cocoClassZh[cls] ?? cls;
              return ListTile(
                leading: Icon(FluentIcons.bullseye, size: 14, color: accent),
                title: Text(zh, style: const TextStyle(fontSize: 13)),
                subtitle: Text(cls, style: TextStyle(fontSize: 10, color: isDark ? const Color(0xFF707090) : const Color(0xFF909090))),
                onPressed: () {
                  _addClass(cls);
                  Navigator.pop(ctx);
                },
              );
            },
          ),
        ),
        actions: [
          Button(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
        ],
      ),
    );
  }

  Widget _statChip(String label, String value, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isDark ? const Color(0x80252540) : const Color(0x80F0F0FA),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(label, style: TextStyle(fontSize: 10, color: isDark ? const Color(0xFF9090B0) : const Color(0xFF8A8A9A))),
        const SizedBox(width: 4),
        Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
      ]),
    );
  }

  Widget _buildSection(String title, bool isDark, List<Widget> children) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700,
        color: isDark ? const Color(0xFFC0C0E8) : const Color(0xFF5A5A80))),
      const SizedBox(height: 8),
      ...children,
      const SizedBox(height: 8),
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

class _DetectionResult {
  final int x;
  final int y;
  final int width;
  final int height;
  final double score;
  final String label;
  final int classId;

  _DetectionResult({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.score,
    required this.label,
    this.classId = 0,
  });
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
            Expanded(child: Slider(value: _matchThreshold, min: 0.5, max: 1.0, divisions: 50, onChanged: (v) => setState(() => _matchThreshold = v))),
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
          templateData: _templateData,
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
