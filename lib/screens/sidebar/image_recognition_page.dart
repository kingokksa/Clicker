/// Image recognition page — screen monitoring, color/image search, conditional triggers.
library;

import 'dart:async';
import 'dart:ffi';
import 'dart:typed_data';
import 'dart:ui';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../services/app_state.dart';
import '../../services/screen_monitor_service.dart';

// FFI binding for GetAsyncKeyState
final _user32 = DynamicLibrary.open('user32.dll');
final _getAsyncKeyState = _user32.lookupFunction<Int16 Function(Int32), int Function(int)>('GetAsyncKeyState');

class ImageRecognitionPage extends StatefulWidget {
  const ImageRecognitionPage({super.key});

  @override
  State<ImageRecognitionPage> createState() => _ImageRecognitionPageState();
}

class _ImageRecognitionPageState extends State<ImageRecognitionPage> {
  int _selectedTab = 0;
  final ScreenMonitorService _monitor = ScreenMonitorService();

  // Region monitor entries
  final List<_RegionEntry> _regions = [];
  int _checkIntervalMs = 500;
  double _sensitivity = 0.5;

  // Color search state
  Color? _searchColor;
  String _searchColorInfo = '';
  bool _searchingColor = false;
  List<_FoundPoint> _foundPoints = [];
  int _searchAreaX = 0, _searchAreaY = 0, _searchAreaW = 1920, _searchAreaH = 1080;
  String _searchAreaInfo = '';
  bool _selectingSearchArea = false;
  double _colorTolerance = 0.1;

  // Conditional triggers
  final List<_TriggerEntry> _triggers = [];

  // Area selection state
  bool _selectingArea = false;
  Function(int x1, int y1, int x2, int y2)? _areaSelectCallback;

  // Platform channel for overlay
  static const _platformChannel = MethodChannel('com.clicker.pro/platform');

  @override
  void initState() {
    super.initState();
    _monitor.onLogEntry = (_) { if (mounted) setState(() {}); };
    _monitor.onMonitoringChanged = (_) { if (mounted) setState(() {}); };

    _platformChannel.setMethodCallHandler((call) async {
      if (!mounted) return;
      switch (call.method) {
        case 'onOverlayClick':
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
          if (_areaSelectCallback != null) {
            _areaSelectCallback!(x1, y1, x2, y2);
            _areaSelectCallback = null;
          }
          if (mounted) setState(() { _selectingArea = false; _selectingSearchArea = false; });
          break;
        case 'onOverlayCancelled':
          await _platformChannel.invokeMethod('stopOverlay');
          if (mounted) {
            setState(() {
            _selectingArea = false;
            _searchingColor = false;
            _selectingSearchArea = false;
          });
          }
          _areaSelectCallback = null;
          break;
      }
    });
  }

  Future<void> _handleOverlayClick(int x, int y) async {
    try {
      await _platformChannel.invokeMethod('stopOverlay');
      await Future.delayed(const Duration(milliseconds: 50));
      final colorResult = await _platformChannel.invokeMethod<Map>('getPixelColor', [x, y]);
      if (colorResult != null && mounted) {
        final r = colorResult['r'] as int;
        final g = colorResult['g'] as int;
        final b = colorResult['b'] as int;
        setState(() {
          _searchColor = Color.fromARGB(255, r, g, b);
          _searchColorInfo = 'RGB($r,$g,$b) #${Color.fromARGB(255, r, g, b).toARGB32().toRadixString(16).substring(2).toUpperCase()} @ ($x,$y)';
          _searchingColor = false;
        });
      }
    } on PlatformException {
      if (mounted) setState(() => _searchingColor = false);
    }
  }

  @override
  void dispose() {
    _platformChannel.invokeMethod('stopOverlay');
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
          const SizedBox(height: 8),
          Text('请在功能管理中启用图像识别', style: TextStyle(fontSize: 13, color: isDark ? const Color(0xFF9090B0) : const Color(0xFF8A8A9A))),
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
          _tabChip('图色查找', _selectedTab == 1, () => setState(() => _selectedTab = 1)),
          const SizedBox(width: 6),
          _tabChip('条件触发', _selectedTab == 2, () => setState(() => _selectedTab = 2)),
        ]),
        const SizedBox(height: 16),

        if (_selectedTab == 0) ..._buildRegionMonitor(isDark, state),
        if (_selectedTab == 1) ..._buildColorSearch(isDark, state),
        if (_selectedTab == 2) ..._buildTriggers(isDark, state),
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
            color: selected ? accent.withOpacity(0.15) : Colors.transparent,
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
      // Controls
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

      // Add region button
      SizedBox(width: double.infinity, child: Button(onPressed: () => _addRegion(isDark, state), child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Icon(FluentIcons.add, size: 14),
        const SizedBox(width: 6),
        const Text('添加监控区域'),
      ]))),
      const SizedBox(height: 12),

      // Region list
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
                ToggleSwitch(checked: t.enabled, onChanged: (v) => setState(() => t.enabled = v)),
                const SizedBox(width: 8),
                IconButton(icon: Icon(FluentIcons.delete, size: 14, color: Colors.red), onPressed: () {
                  setState(() { _regions.remove(t); _monitor.removeRegion(t.id); });
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
    final result = await showDialog<_RegionConfig>(context: context, builder: (ctx) => _AddRegionDialog());
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
    }
  }

  // ─── Color Search ──────────────────────────────────────────

  List<Widget> _buildColorSearch(bool isDark, AppState state) {
    final cardBg = isDark ? const Color(0xFF252540).withValues(alpha: 0.5) : const Color(0xFFF0F0FA).withValues(alpha: 0.5);
    return [
      // Target color
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: isDark ? const Color(0xFF303050) : const Color(0xFFD0D0E0)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(FluentIcons.color, size: 16, color: state.accentColor),
            const SizedBox(width: 8),
            const Text('目标颜色', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          ]),
          const SizedBox(height: 12),
          if (_searchingColor)
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFD32F2F).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFFD32F2F).withValues(alpha: 0.3)),
              ),
              child: Row(children: [
                Icon(FluentIcons.color, size: 14, color: const Color(0xFFD32F2F)),
                const SizedBox(width: 8),
                Text('在屏幕上点击拾取颜色，按 ESC 取消', style: TextStyle(fontSize: 13, color: const Color(0xFFD32F2F))),
              ]),
            )
          else
            Row(children: [
              FilledButton(
                onPressed: () async {
                  setState(() => _searchingColor = true);
                  try {
                    await _platformChannel.invokeMethod('startPickOverlay');
                  } on PlatformException {
                    if (mounted) setState(() => _searchingColor = false);
                  }
                },
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(FluentIcons.color, size: 14),
                  const SizedBox(width: 6),
                  const Text('拾取颜色'),
                ]),
              ),
              if (_searchColor != null) ...[
                const SizedBox(width: 12),
                Container(width: 32, height: 32, decoration: BoxDecoration(
                  color: _searchColor,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: isDark ? const Color(0xFF404060) : const Color(0xFFD0D0D8)),
                )),
                const SizedBox(width: 8),
                Expanded(child: Text(_searchColorInfo, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
              ],
            ]),
          const SizedBox(height: 12),
          Row(children: [
            const Text('容差: ', style: TextStyle(fontSize: 13)),
            SizedBox(width: 160, child: Slider(
              value: _colorTolerance,
              min: 0.0, max: 0.5, divisions: 50,
              onChanged: (v) => setState(() => _colorTolerance = v),
            )),
            Text('${(_colorTolerance * 100).toStringAsFixed(0)}%', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
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
            Icon(FluentIcons.checkbox_composite, size: 16, color: state.accentColor),
            const SizedBox(width: 8),
            const Text('搜索范围', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          ]),
          const SizedBox(height: 12),
          if (_selectingSearchArea)
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFD32F2F).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFFD32F2F).withValues(alpha: 0.3)),
              ),
              child: Row(children: [
                Icon(FluentIcons.checkbox_composite, size: 14, color: const Color(0xFFD32F2F)),
                const SizedBox(width: 8),
                Text('在屏幕上拖拽选择区域，按 ESC 取消', style: TextStyle(fontSize: 12, color: const Color(0xFFD32F2F))),
              ]),
            )
          else
            Row(children: [
              FilledButton(
                onPressed: _startSearchAreaSelect,
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(FluentIcons.checkbox_composite, size: 14),
                  const SizedBox(width: 6),
                  Text(_searchAreaInfo.isNotEmpty ? _searchAreaInfo : '选择区域'),
                ]),
              ),
              const SizedBox(width: 8),
              Expanded(child: Text('默认全屏', style: TextStyle(fontSize: 12, color: isDark ? const Color(0xFF9090B0) : const Color(0xFF8A8A9A)))),
            ]),
        ]),
      ),
      const SizedBox(height: 12),

      // Search button
      SizedBox(width: double.infinity, child: FilledButton(
        onPressed: _searchColor != null ? _doColorSearch : null,
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(FluentIcons.search, size: 14),
          const SizedBox(width: 6),
          const Text('查找颜色'),
        ]),
      )),
      const SizedBox(height: 12),

      // Results
      if (_foundPoints.isNotEmpty) ...[
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
              Text('找到 ${_foundPoints.length} 个匹配点', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
              const Spacer(),
              HyperlinkButton(onPressed: () => setState(() => _foundPoints.clear()), child: const Text('清空')),
            ]),
            const SizedBox(height: 8),
            ..._foundPoints.take(20).map((p) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(children: [
                Container(width: 14, height: 14, decoration: BoxDecoration(
                  color: p.color,
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(color: isDark ? const Color(0xFF404060) : const Color(0xFFD0D0D8)),
                )),
                const SizedBox(width: 6),
                Text('(${p.x}, ${p.y})  RGB(${p.color.red}, ${p.color.green}, ${p.color.blue})',
                  style: TextStyle(fontSize: 12, fontFamily: 'monospace', color: isDark ? const Color(0xFFC0C0D8) : const Color(0xFF5A5A70))),
              ]),
            )),
            if (_foundPoints.length > 20)
              Padding(padding: const EdgeInsets.only(top: 4), child: Text('... 还有 ${_foundPoints.length - 20} 个结果',
                style: TextStyle(fontSize: 12, color: isDark ? const Color(0xFF9090B0) : const Color(0xFF8A8A9A)))),
          ]),
        ),
      ],
    ];
  }

  void _startSearchAreaSelect() async {
    setState(() => _selectingSearchArea = true);
    _areaSelectCallback = (x1, y1, x2, y2) {
      setState(() {
        _searchAreaX = x1;
        _searchAreaY = y1;
        _searchAreaW = x2 - x1;
        _searchAreaH = y2 - y1;
        _searchAreaInfo = '($x1, $y1) ${_searchAreaW}x$_searchAreaH';
      });
    };
    try {
      await _platformChannel.invokeMethod('startAreaSelectOverlay');
    } on PlatformException {
      if (mounted) setState(() => _selectingSearchArea = false);
    }
  }

  Future<void> _doColorSearch() async {
    if (_searchColor == null) return;
    final targetR = _searchColor!.red;
    final targetG = _searchColor!.green;
    final targetB = _searchColor!.blue;
    final tolerance = (_colorTolerance * 255).round();

    try {
      // Capture the search area
      final pixels = await _monitor.captureScreenRect(
        _searchAreaX, _searchAreaY, _searchAreaW, _searchAreaH,
      );
      if (pixels == null) return;

      final results = <_FoundPoint>[];
      // Sample every 4th pixel for speed (step = 4)
      const step = 4;
      for (int y = 0; y < _searchAreaH; y += step) {
        for (int x = 0; x < _searchAreaW; x += step) {
          final idx = (y * _searchAreaW + x) * 4;
          if (idx + 3 >= pixels.length) continue;
          final b = pixels[idx];
          final g = pixels[idx + 1];
          final r = pixels[idx + 2];
          if ((r - targetR).abs() <= tolerance &&
              (g - targetG).abs() <= tolerance &&
              (b - targetB).abs() <= tolerance) {
            results.add(_FoundPoint(
              x: _searchAreaX + x,
              y: _searchAreaY + y,
              color: Color.fromARGB(255, r, g, b),
            ));
          }
        }
      }

      if (mounted) setState(() => _foundPoints = results);
    } on PlatformException {
      // ignore
    }
  }

  // ─── Conditional Triggers ──────────────────────────────────

  List<Widget> _buildTriggers(bool isDark, AppState state) {
    final cardBg = isDark ? const Color(0xFF252540).withValues(alpha: 0.5) : const Color(0xFFF0F0FA).withValues(alpha: 0.5);
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
            const Text('条件触发', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          ]),
          const SizedBox(height: 8),
          Text('当屏幕指定区域满足条件时自动执行操作', style: TextStyle(fontSize: 12, color: isDark ? const Color(0xFF9090B0) : const Color(0xFF8A8A9A))),
        ]),
      ),
      const SizedBox(height: 12),

      SizedBox(width: double.infinity, child: Button(onPressed: () => _addTrigger(isDark, state), child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Icon(FluentIcons.add, size: 14),
        const SizedBox(width: 6),
        const Text('添加触发条件'),
      ]))),
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
                ToggleSwitch(checked: t.enabled, onChanged: (v) => setState(() => t.enabled = v)),
                const SizedBox(width: 8),
                IconButton(icon: Icon(FluentIcons.delete, size: 14, color: Colors.red), onPressed: () {
                  setState(() => _triggers.remove(t));
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
              const SizedBox(height: 6),
              Row(children: [
                _actionChip(t.actionType.label, isDark),
                const SizedBox(width: 6),
                if (t.actionType == _TriggerActionType.click)
                  Text('点击 (${t.actionX}, ${t.actionY})', style: TextStyle(fontSize: 12, color: isDark ? const Color(0xFF9090B0) : const Color(0xFF8A8A9A)))
                else if (t.actionType == _TriggerActionType.keyPress)
                  Text('按键 ${t.actionKey}', style: TextStyle(fontSize: 12, color: isDark ? const Color(0xFF9090B0) : const Color(0xFF8A8A9A)))
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

  void _addTrigger(bool isDark, AppState state) async {
    final result = await showDialog<_TriggerConfig>(context: context, builder: (ctx) => _AddTriggerDialog());
    if (result != null && mounted) {
      setState(() {
        _triggers.add(_TriggerEntry(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          name: result.name,
          conditionType: result.conditionType,
          actionType: result.actionType,
          x: result.x, y: result.y, w: result.w, h: result.h,
          targetColor: result.targetColor,
          actionX: result.actionX, actionY: result.actionY,
          actionKey: result.actionKey,
          intervalMs: result.intervalMs,
          enabled: true,
        ));
      });
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

class _FoundPoint {
  final int x, y;
  final Color color;
  _FoundPoint({required this.x, required this.y, required this.color});
}

enum _TriggerConditionType { colorMatch, colorChange, colorDisappear }
extension on _TriggerConditionType {
  String get label {
    switch (this) {
      case _TriggerConditionType.colorMatch: return '颜色匹配';
      case _TriggerConditionType.colorChange: return '颜色变化';
      case _TriggerConditionType.colorDisappear: return '颜色消失';
    }
  }
}

enum _TriggerActionType { click, keyPress, startClicker, stopClicker }
extension on _TriggerActionType {
  String get label {
    switch (this) {
      case _TriggerActionType.click: return '点击';
      case _TriggerActionType.keyPress: return '按键';
      case _TriggerActionType.startClicker: return '启动连点';
      case _TriggerActionType.stopClicker: return '停止连点';
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
  final int actionX, actionY;
  final String actionKey;
  int intervalMs;

  _TriggerEntry({
    required this.id, required this.name, required this.conditionType,
    required this.actionType, required this.enabled,
    this.x = 0, this.y = 0, this.w = 100, this.h = 100,
    this.targetColor, this.actionX = 0, this.actionY = 0,
    this.actionKey = '', this.intervalMs = 500,
  });
}

class _TriggerConfig {
  final String name;
  final _TriggerConditionType conditionType;
  final _TriggerActionType actionType;
  final int x, y, w, h;
  final Color? targetColor;
  final int actionX, actionY;
  final String actionKey;
  final int intervalMs;
  _TriggerConfig({
    required this.name, required this.conditionType, required this.actionType,
    required this.x, required this.y, required this.w, required this.h,
    this.targetColor, this.actionX = 0, this.actionY = 0,
    this.actionKey = '', this.intervalMs = 500,
  });
}

// ─── Add Region Dialog ──────────────────────────────────────

class _AddRegionDialog extends StatefulWidget {
  @override
  State<_AddRegionDialog> createState() => _AddRegionDialogState();
}

class _AddRegionDialogState extends State<_AddRegionDialog> {
  int _x = 0, _y = 0, _w = 100, _h = 100;
  double _threshold = 0.85;
  Color? _targetColor;
  bool _selectingArea = false;
  bool _selectingColor = false;
  String _areaInfo = '';
  String _colorInfo = '';

  static const _platformChannel = MethodChannel('com.clicker.pro/platform');

  @override
  void initState() {
    super.initState();
    _platformChannel.setMethodCallHandler((call) async {
      if (!mounted) return;
      switch (call.method) {
        case 'onOverlayClick':
          final args = call.arguments as Map;
          final x = args['x'] as int;
          final y = args['y'] as int;
          await _pickColorFromOverlay(x, y);
          break;
        case 'onOverlayAreaSelected':
          final args = call.arguments as Map;
          final x1 = args['x1'] as int;
          final y1 = args['y1'] as int;
          final x2 = args['x2'] as int;
          final y2 = args['y2'] as int;
          await _platformChannel.invokeMethod('stopOverlay');
          if (mounted) {
            setState(() {
              _selectingArea = false;
              _x = x1; _y = y1;
              _w = x2 - x1; _h = y2 - y1;
              if (_w < 10) _w = 10;
              if (_h < 10) _h = 10;
              _areaInfo = '($_x, $_y) ${_w}x$_h';
            });
          }
          break;
        case 'onOverlayCancelled':
          await _platformChannel.invokeMethod('stopOverlay');
          if (mounted) setState(() { _selectingArea = false; _selectingColor = false; });
          break;
      }
    });
  }

  @override
  void dispose() {
    _platformChannel.invokeMethod('stopOverlay');
    super.dispose();
  }

  Future<void> _pickColorFromOverlay(int x, int y) async {
    try {
      await _platformChannel.invokeMethod('stopOverlay');
      await Future.delayed(const Duration(milliseconds: 50));
      final colorResult = await _platformChannel.invokeMethod<Map>('getPixelColor', [x, y]);
      if (colorResult != null && mounted) {
        final r = colorResult['r'] as int;
        final g = colorResult['g'] as int;
        final b = colorResult['b'] as int;
        setState(() {
          _targetColor = Color.fromARGB(255, r, g, b);
          _selectingColor = false;
          _colorInfo = '已拾取 ($x, $y)';
        });
      }
    } on PlatformException {
      if (mounted) setState(() => _selectingColor = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ContentDialog(
      title: const Text('添加监控区域'),
      content: SizedBox(width: 380, child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (_selectingArea)
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFD32F2F).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0xFFD32F2F).withValues(alpha: 0.3)),
            ),
            child: Row(children: [
              Icon(FluentIcons.checkbox_composite, size: 14, color: const Color(0xFFD32F2F)),
              const SizedBox(width: 8),
              Expanded(child: Text('在屏幕上拖拽选择区域，按 ESC 取消', style: TextStyle(fontSize: 12, color: const Color(0xFFD32F2F)))),
            ]),
          )
        else
          FilledButton(
            onPressed: _startAreaSelect,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(FluentIcons.checkbox_composite, size: 14),
              const SizedBox(width: 6),
              Text(_areaInfo.isNotEmpty ? _areaInfo : '选择屏幕区域'),
            ]),
          ),
        const SizedBox(height: 12),
        Row(children: [
          SizedBox(width: 70, child: TextBox(placeholder: 'X', onChanged: (v) => _x = int.tryParse(v) ?? 0)),
          const SizedBox(width: 6),
          SizedBox(width: 70, child: TextBox(placeholder: 'Y', onChanged: (v) => _y = int.tryParse(v) ?? 0)),
          const SizedBox(width: 6),
          SizedBox(width: 70, child: TextBox(placeholder: '宽', onChanged: (v) => _w = int.tryParse(v) ?? 100)),
          const SizedBox(width: 6),
          SizedBox(width: 70, child: TextBox(placeholder: '高', onChanged: (v) => _h = int.tryParse(v) ?? 100)),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          const Text('阈值: ', style: TextStyle(fontSize: 13)),
          Expanded(child: Slider(value: _threshold, min: 0.5, max: 1.0, divisions: 50, onChanged: (v) => setState(() => _threshold = v))),
          const SizedBox(width: 8),
          Text('${(_threshold * 100).toStringAsFixed(0)}%', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        ]),
        const SizedBox(height: 12),
        if (_selectingColor)
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.08),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.red.withOpacity(0.3)),
            ),
            child: Row(children: [
              Icon(FluentIcons.color, size: 14, color: const Color(0xFFD32F2F)),
              const SizedBox(width: 8),
              Expanded(child: Text('在屏幕上点击拾取颜色，按 ESC 取消', style: TextStyle(fontSize: 12, color: const Color(0xFFD32F2F)))),
            ]),
          )
        else
          Row(children: [
            FilledButton(
              onPressed: _startColorPick,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(FluentIcons.color, size: 14),
                const SizedBox(width: 6),
                Text(_colorInfo.isNotEmpty ? _colorInfo : '拾取目标颜色'),
              ]),
            ),
            if (_targetColor != null) ...[
              const SizedBox(width: 8),
              Container(width: 24, height: 24, decoration: BoxDecoration(
                color: _targetColor,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: const Color(0xFF404060)),
              )),
              const SizedBox(width: 4),
              Text('#${_targetColor!.toARGB32().toRadixString(16).substring(2).toUpperCase()}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            ],
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

  void _startAreaSelect() async {
    setState(() => _selectingArea = true);
    try { await _platformChannel.invokeMethod('startAreaSelectOverlay'); }
    on PlatformException { if (mounted) setState(() => _selectingArea = false); }
  }

  void _startColorPick() async {
    setState(() => _selectingColor = true);
    try { await _platformChannel.invokeMethod('startPickOverlay'); }
    on PlatformException { if (mounted) setState(() => _selectingColor = false); }
  }
}

// ─── Add Trigger Dialog ─────────────────────────────────────

class _AddTriggerDialog extends StatefulWidget {
  @override
  State<_AddTriggerDialog> createState() => _AddTriggerDialogState();
}

class _AddTriggerDialogState extends State<_AddTriggerDialog> {
  _TriggerConditionType _conditionType = _TriggerConditionType.colorMatch;
  _TriggerActionType _actionType = _TriggerActionType.click;
  int _x = 0, _y = 0, _w = 100, _h = 100;
  Color? _targetColor;
  int _actionX = 0, _actionY = 0;
  String _actionKey = '';
  int _intervalMs = 500;
  bool _selectingArea = false;
  bool _selectingColor = false;
  bool _selectingActionPos = false;
  String _areaInfo = '';
  String _colorInfo = '';
  String _actionPosInfo = '';

  static const _platformChannel = MethodChannel('com.clicker.pro/platform');

  @override
  void initState() {
    super.initState();
    _platformChannel.setMethodCallHandler((call) async {
      if (!mounted) return;
      switch (call.method) {
        case 'onOverlayClick':
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
          if (mounted) {
            setState(() {
              _selectingArea = false;
              _x = x1; _y = y1;
              _w = x2 - x1; _h = y2 - y1;
              if (_w < 10) _w = 10;
              if (_h < 10) _h = 10;
              _areaInfo = '($_x, $_y) ${_w}x$_h';
            });
          }
          break;
        case 'onOverlayCancelled':
          await _platformChannel.invokeMethod('stopOverlay');
          if (mounted) setState(() { _selectingArea = false; _selectingColor = false; _selectingActionPos = false; });
          break;
      }
    });
  }

  Future<void> _handleOverlayClick(int x, int y) async {
    try {
      await _platformChannel.invokeMethod('stopOverlay');
      await Future.delayed(const Duration(milliseconds: 50));
      final colorResult = await _platformChannel.invokeMethod<Map>('getPixelColor', [x, y]);
      if (colorResult != null && mounted) {
        final r = colorResult['r'] as int;
        final g = colorResult['g'] as int;
        final b = colorResult['b'] as int;
        setState(() {
          if (_selectingColor) {
            _targetColor = Color.fromARGB(255, r, g, b);
            _selectingColor = false;
            _colorInfo = '已拾取 ($x, $y)';
          } else if (_selectingActionPos) {
            _actionX = x;
            _actionY = y;
            _selectingActionPos = false;
            _actionPosInfo = '($x, $y)';
          }
        });
      }
    } on PlatformException {
      if (mounted) setState(() { _selectingColor = false; _selectingActionPos = false; });
    }
  }

  @override
  void dispose() {
    _platformChannel.invokeMethod('stopOverlay');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ContentDialog(
      title: const Text('添加触发条件'),
      content: SizedBox(width: 400, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Condition type
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
        // Monitor area
        const Text('监控区域:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        if (_selectingArea)
          Text('在屏幕上拖拽选择区域...', style: TextStyle(fontSize: 12, color: const Color(0xFFD32F2F)))
        else
          Row(children: [
            FilledButton(
              onPressed: () async {
                setState(() => _selectingArea = true);
                try { await _platformChannel.invokeMethod('startAreaSelectOverlay'); }
                on PlatformException { if (mounted) setState(() => _selectingArea = false); }
              },
              child: Text(_areaInfo.isNotEmpty ? _areaInfo : '选择区域'),
            ),
          ]),
        Row(children: [
          SizedBox(width: 70, child: TextBox(placeholder: 'X', onChanged: (v) => _x = int.tryParse(v) ?? 0)),
          const SizedBox(width: 6),
          SizedBox(width: 70, child: TextBox(placeholder: 'Y', onChanged: (v) => _y = int.tryParse(v) ?? 0)),
          const SizedBox(width: 6),
          SizedBox(width: 70, child: TextBox(placeholder: '宽', onChanged: (v) => _w = int.tryParse(v) ?? 100)),
          const SizedBox(width: 6),
          SizedBox(width: 70, child: TextBox(placeholder: '高', onChanged: (v) => _h = int.tryParse(v) ?? 100)),
        ]),

        // Target color (for colorMatch / colorDisappear)
        if (_conditionType == _TriggerConditionType.colorMatch || _conditionType == _TriggerConditionType.colorDisappear) ...[
          const SizedBox(height: 8),
          const Text('目标颜色:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Row(children: [
            if (_selectingColor)
              Text('点击屏幕拾取颜色...', style: TextStyle(fontSize: 12, color: const Color(0xFFD32F2F)))
            else
              FilledButton(
                onPressed: () async {
                  setState(() => _selectingColor = true);
                  try { await _platformChannel.invokeMethod('startPickOverlay'); }
                  on PlatformException { if (mounted) setState(() => _selectingColor = false); }
                },
                child: Text(_colorInfo.isNotEmpty ? _colorInfo : '拾取颜色'),
              ),
            if (_targetColor != null) ...[
              const SizedBox(width: 8),
              Container(width: 24, height: 24, decoration: BoxDecoration(
                color: _targetColor,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: const Color(0xFF404060)),
              )),
            ],
          ]),
        ],

        const SizedBox(height: 12),
        // Action type
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

        // Action params
        if (_actionType == _TriggerActionType.click) ...[
          const SizedBox(height: 4),
          Row(children: [
            if (_selectingActionPos)
              Text('点击屏幕选择点击位置...', style: TextStyle(fontSize: 12, color: const Color(0xFFD32F2F)))
            else
              FilledButton(
                onPressed: () async {
                  setState(() => _selectingActionPos = true);
                  try { await _platformChannel.invokeMethod('startPickOverlay'); }
                  on PlatformException { if (mounted) setState(() => _selectingActionPos = false); }
                },
                child: Text(_actionPosInfo.isNotEmpty ? _actionPosInfo : '选择点击位置'),
              ),
            const SizedBox(width: 8),
            SizedBox(width: 70, child: TextBox(placeholder: 'X', onChanged: (v) => _actionX = int.tryParse(v) ?? 0)),
            const SizedBox(width: 6),
            SizedBox(width: 70, child: TextBox(placeholder: 'Y', onChanged: (v) => _actionY = int.tryParse(v) ?? 0)),
          ]),
        ] else if (_actionType == _TriggerActionType.keyPress) ...[
          const SizedBox(height: 4),
          SizedBox(width: 120, child: TextBox(placeholder: '按键 (如 A, Enter)', onChanged: (v) => _actionKey = v)),
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
          actionX: _actionX, actionY: _actionY,
          actionKey: _actionKey,
          intervalMs: _intervalMs,
        )), child: const Text('添加')),
      ],
    );
  }
}
