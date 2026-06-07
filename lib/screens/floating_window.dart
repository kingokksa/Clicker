/// Floating mini-window — compact overlay with full clicker controls.
/// Always-on-top, draggable, auto-hide at screen edges.
library;

import 'dart:async';
import 'dart:ui' as ui;
import 'package:fluent_ui/fluent_ui.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import '../services/app_state.dart';
import '../models/clicker_config.dart';

const _kCollapsedW = 280;
const _kCollapsedH = 95;
const _kExpandedW = 280;
const _kExpandedH = 170;
const _kEdgeHideThreshold = 6; // pixels from edge to trigger auto-hide
const _kEdgePeekSize = 4; // pixels visible when hidden at edge

class FloatingWindow extends StatefulWidget {
  final VoidCallback onSwitchToMain;
  const FloatingWindow({super.key, required this.onSwitchToMain});

  @override
  State<FloatingWindow> createState() => _FloatingWindowState();
}

class _FloatingWindowState extends State<FloatingWindow> with WindowListener, SingleTickerProviderStateMixin {
  late AnimationController _animCtrl;
  bool _expanded = false;

  // Edge auto-hide state
  bool _isEdgeHidden = false;
  Edge? _hiddenEdge;
  Offset _lastPosition = Offset.zero;
  Timer? _edgeHideTimer;
  Timer? _edgeShowTimer;
  bool _isDragging = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _animCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 180));
    _animCtrl.addStatusListener(_onAnimStatus);
  }

  @override
  void dispose() {
    _edgeHideTimer?.cancel();
    _edgeShowTimer?.cancel();
    _animCtrl.removeStatusListener(_onAnimStatus);
    windowManager.removeListener(this);
    _animCtrl.dispose();
    super.dispose();
  }

  void _onAnimStatus(AnimationStatus status) {
    if (status == AnimationStatus.dismissed) {
      windowManager.setSize(Size(_kCollapsedW.toDouble(), _kCollapsedH.toDouble()));
    }
  }

  @override
  void onWindowMove() async {
    final pos = await windowManager.getPosition();
    _lastPosition = pos;
    _checkEdgeHide(pos);
  }

  @override
  void onWindowClose() => windowManager.hide();

  void _toggleExpanded() {
    setState(() {
      _expanded = !_expanded;
      if (_expanded) {
        windowManager.setSize(Size(_kExpandedW.toDouble(), _kExpandedH.toDouble())).then((_) {
          _animCtrl.forward();
        });
      } else {
        _animCtrl.reverse();
      }
    });
  }

  // ── Edge auto-hide logic ──

  Future<void> _checkEdgeHide(Offset pos) async {
    if (_isDragging || _isEdgeHidden) return;
    final screen = await windowManager.getSize();
    final display = ui.PlatformDispatcher.instance.displays.firstOrNull;
    if (display == null) return;
    final screenWidth = display.size.width / display.devicePixelRatio;
    final screenHeight = display.size.height / display.devicePixelRatio;
    final winW = screen.width;
    final winH = screen.height;

    Edge? nearEdge;
    if (pos.dx <= _kEdgeHideThreshold) nearEdge = Edge.left;
    else if (pos.dx + winW >= screenWidth - _kEdgeHideThreshold) nearEdge = Edge.right;
    else if (pos.dy <= _kEdgeHideThreshold) nearEdge = Edge.top;

    if (nearEdge != null) {
      _edgeHideTimer?.cancel();
      _edgeHideTimer = Timer(const Duration(milliseconds: 800), () {
        _hideToEdge(nearEdge!);
      });
    } else {
      _edgeHideTimer?.cancel();
    }
  }

  Future<void> _hideToEdge(Edge edge) async {
    final pos = await windowManager.getPosition();
    final size = await windowManager.getSize();
    _hiddenEdge = edge;
    _isEdgeHidden = true;

    final display = ui.PlatformDispatcher.instance.displays.firstOrNull;
    final sw = display != null ? display.size.width / display.devicePixelRatio : 1920.0;

    Offset newPos;
    switch (edge) {
      case Edge.left:
        newPos = Offset(-size.width + _kEdgePeekSize, pos.dy);
        break;
      case Edge.right:
        newPos = Offset(sw - _kEdgePeekSize, pos.dy);
        break;
      case Edge.top:
        newPos = Offset(pos.dx, -size.height + _kEdgePeekSize);
        break;
    }
    await windowManager.setPosition(newPos);
    if (mounted) setState(() {});
  }

  Future<void> _showFromEdge() async {
    if (!_isEdgeHidden || _hiddenEdge == null) return;
    _edgeShowTimer?.cancel();
    final size = await windowManager.getSize();
    final display = ui.PlatformDispatcher.instance.displays.firstOrNull;
    final sw = display != null ? display.size.width / display.devicePixelRatio : 1920.0;

    Offset newPos;
    switch (_hiddenEdge!) {
      case Edge.left:
        newPos = Offset(0, _lastPosition.dy);
        break;
      case Edge.right:
        newPos = Offset(sw - size.width, _lastPosition.dy);
        break;
      case Edge.top:
        newPos = Offset(_lastPosition.dx, 0);
        break;
    }
    await windowManager.setPosition(newPos);
    _isEdgeHidden = false;
    _hiddenEdge = null;
    if (mounted) setState(() {});
  }

  void _onDragStart() {
    _isDragging = true;
    _edgeHideTimer?.cancel();
    if (_isEdgeHidden) _showFromEdge();
    windowManager.startDragging();
  }

  void _onDragEnd() {
    _isDragging = false;
  }

  /// After mouse leaves the window, check if it's near an edge and auto-hide.
  void _scheduleEdgeHideCheck() {
    if (_isEdgeHidden) return;
    _edgeHideTimer?.cancel();
    _edgeHideTimer = Timer(const Duration(milliseconds: 600), () async {
      if (_isEdgeHidden || _isDragging || !mounted) return;
      final pos = await windowManager.getPosition();
      final size = await windowManager.getSize();
      final display = ui.PlatformDispatcher.instance.displays.firstOrNull;
      if (display == null) return;
      final sw = display.size.width / display.devicePixelRatio;
      final sh = display.size.height / display.devicePixelRatio;

      Edge? nearEdge;
      if (pos.dx <= _kEdgeHideThreshold) nearEdge = Edge.left;
      else if (pos.dx + size.width >= sw - _kEdgeHideThreshold) nearEdge = Edge.right;
      else if (pos.dy <= _kEdgeHideThreshold) nearEdge = Edge.top;

      if (nearEdge != null) {
        _hideToEdge(nearEdge);
      }
    });
  }

  // ── Build ──

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final isDark = FluentTheme.of(context).brightness == Brightness.dark;
    final config = state.clickerConfig;
    final isRunning = state.isClickerRunning;
    final accent = state.accentColor;

    final bgColor = isDark ? const Color(0xFF1E1E36) : const Color(0xFFFAFAFF);
    final surfaceColor = isDark ? const Color(0xFF252544) : const Color(0xFFF0F0FA);
    final borderColor = isDark ? const Color(0xFF3A3A5A) : const Color(0xFFE0E0EE);
    final textPrimary = isDark ? const Color(0xFFD0D0F0) : const Color(0xFF4A4A70);
    final textSecondary = isDark ? const Color(0xFFB0B0D0) : const Color(0xFF5A5A70);
    final textMuted = isDark ? const Color(0xFF8080A0) : const Color(0xFF8A8AA0);

    return MouseRegion(
      onEnter: (_) {
        if (_isEdgeHidden) _showFromEdge();
      },
      onExit: (_) {
        _scheduleEdgeHideCheck();
      },
      child: ExcludeSemantics(
        child: Container(
        width: _kExpandedW.toDouble(),
        decoration: BoxDecoration(
          color: bgColor.withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor, width: 1),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.22), blurRadius: 24, offset: const Offset(0, 6)),
            BoxShadow(color: accent.withValues(alpha: 0.08), blurRadius: 12, offset: const Offset(0, 2)),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Title bar ──
              GestureDetector(
                onPanStart: (_) => _onDragStart(),
                onPanEnd: (_) => _onDragEnd(),
                onDoubleTap: _toggleExpanded,
                child: Container(
                  height: 30,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: surfaceColor.withValues(alpha: 0.96),
                    border: Border(bottom: BorderSide(color: borderColor, width: 0.5)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 6, height: 6,
                        decoration: BoxDecoration(
                          color: isRunning ? const Color(0xFF4CAF50) : accent,
                          shape: BoxShape.circle,
                          boxShadow: isRunning ? [
                            BoxShadow(color: const Color(0xFF4CAF50).withValues(alpha: 0.5), blurRadius: 4)
                          ] : null,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text('Clicker', style: TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w700, color: textPrimary,
                        fontFamily: 'Segoe UI Variable, Segoe UI, Microsoft YaHei UI',
                      )),
                      if (isRunning) ...[
                        const SizedBox(width: 4),
                        Text('${state.clickCount}', style: TextStyle(
                          fontSize: 9, fontWeight: FontWeight.w600, color: accent,
                          fontFamily: 'Segoe UI Variable, Segoe UI, Microsoft YaHei UI',
                        )),
                      ],
                      const Spacer(),
                      _titleBtn(
                        icon: _expanded ? FluentIcons.chevron_up : FluentIcons.chevron_down,
                        isDark: isDark, textMuted: textMuted,
                        onPressed: _toggleExpanded,
                      ),
                      const SizedBox(width: 2),
                      _titleBtn(
                        icon: state.floatingAlwaysOnTop ? FluentIcons.pinned_fill : FluentIcons.pinned,
                        isDark: isDark, textMuted: textMuted, active: state.floatingAlwaysOnTop,
                        onPressed: () {
                          final v = !state.floatingAlwaysOnTop;
                          state.setFloatingAlwaysOnTop(v);
                          windowManager.setAlwaysOnTop(v);
                        },
                      ),
                      const SizedBox(width: 2),
                      _titleBtn(
                        icon: FluentIcons.back_to_window,
                        isDark: isDark, textMuted: textMuted,
                        onPressed: widget.onSwitchToMain,
                      ),
                      const SizedBox(width: 2),
                      _titleBtn(
                        icon: FluentIcons.chrome_close,
                        isDark: isDark, textMuted: textMuted,
                        onPressed: () => windowManager.hide(),
                      ),
                    ],
                  ),
                ),
              ),

              // ── Main controls (always visible) ──
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Row 1: Start/Stop + Emergency + Mode chips
                    Row(
                      children: [
                        SizedBox(
                          width: 88, height: 28,
                          child: FilledButton(
                            style: ButtonStyle(
                              backgroundColor: WidgetStateProperty.resolveWith((_) =>
                                isRunning ? const Color(0xFFE53935) : accent),
                              shape: WidgetStateProperty.all(RoundedRectangleBorder(borderRadius: BorderRadius.circular(6))),
                              padding: WidgetStateProperty.all(EdgeInsets.zero),
                            ),
                            onPressed: state.toggleClicker,
                            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                              Icon(isRunning ? FluentIcons.stop : FluentIcons.play, size: 11, color: Colors.white),
                              const SizedBox(width: 4),
                              Text(isRunning ? '停止' : '开始', style: const TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white,
                                fontFamily: 'Segoe UI Variable, Segoe UI, Microsoft YaHei UI',
                              )),
                            ]),
                          ),
                        ),
                        const SizedBox(width: 4),
                        SizedBox(
                          width: 28, height: 28,
                          child: FilledButton(
                            style: ButtonStyle(
                              backgroundColor: WidgetStateProperty.all(const Color(0xFFFF5722).withValues(alpha: 0.15)),
                              shape: WidgetStateProperty.all(RoundedRectangleBorder(borderRadius: BorderRadius.circular(6))),
                              padding: WidgetStateProperty.all(EdgeInsets.zero),
                            ),
                            onPressed: () {
                              state.stopClicker();
                              AppState.broadcastEmergencyStop();
                            },
                            child: const Icon(FluentIcons.warning, size: 12, color: Color(0xFFFF5722)),
                          ),
                        ),
                        const Spacer(),
                        _chip('鼠', config.clickMode == ClickMode.mouse, () {
                          state.setClickerConfig(config.copyWith(clickMode: ClickMode.mouse));
                        }, isDark, accent),
                        const SizedBox(width: 3),
                        _chip('键', config.clickMode == ClickMode.keyboard, () {
                          state.setClickerConfig(config.copyWith(clickMode: ClickMode.keyboard));
                        }, isDark, accent),
                      ],
                    ),

                    const SizedBox(height: 4),

                    // Row 2: Interval
                    Row(
                      children: [
                        Text('间隔', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: textSecondary,
                          fontFamily: 'Segoe UI Variable, Segoe UI, Microsoft YaHei UI')),
                        const SizedBox(width: 4),
                        Expanded(
                          child: _SimpleSlider(
                            value: config.intervalMs.toDouble().clamp(10.0, 5000.0),
                            min: 10.0, max: 5000.0,
                            accent: accent,
                            onChanged: (v) => state.setClickerConfig(config.copyWith(intervalMs: v)),
                          ),
                        ),
                        SizedBox(width: 42, child: Text(
                          config.intervalMs >= 1000 ? '${(config.intervalMs / 1000).toStringAsFixed(1)}s' : '${config.intervalMs}ms',
                          style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: textPrimary,
                            fontFamily: 'Segoe UI Variable, Segoe UI, Microsoft YaHei UI'),
                          textAlign: TextAlign.right,
                        )),
                      ],
                    ),

                    // ── Expanded controls ──
                    SizeTransition(
                      sizeFactor: _animCtrl,
                      axisAlignment: -1.0,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            child: Container(height: 0.5, color: borderColor),
                          ),

                          // Mouse mode options
                          if (config.clickMode == ClickMode.mouse) ...[
                            Row(
                              children: [
                                Text('按钮', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: textSecondary,
                                  fontFamily: 'Segoe UI Variable, Segoe UI, Microsoft YaHei UI')),
                                const SizedBox(width: 4),
                                _chip('左', config.mouseButton == MouseButton.left, () {
                                  state.setClickerConfig(config.copyWith(mouseButton: MouseButton.left));
                                }, isDark, accent),
                                const SizedBox(width: 3),
                                _chip('右', config.mouseButton == MouseButton.right, () {
                                  state.setClickerConfig(config.copyWith(mouseButton: MouseButton.right));
                                }, isDark, accent),
                                const SizedBox(width: 3),
                                _chip('中', config.mouseButton == MouseButton.middle, () {
                                  state.setClickerConfig(config.copyWith(mouseButton: MouseButton.middle));
                                }, isDark, accent),
                                const Spacer(),
                                Text('类型', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: textSecondary,
                                  fontFamily: 'Segoe UI Variable, Segoe UI, Microsoft YaHei UI')),
                                const SizedBox(width: 4),
                                _chip('单', config.clickType == ClickType.single, () {
                                  state.setClickerConfig(config.copyWith(clickType: ClickType.single));
                                }, isDark, accent),
                                const SizedBox(width: 3),
                                _chip('双', config.clickType == ClickType.double, () {
                                  state.setClickerConfig(config.copyWith(clickType: ClickType.double));
                                }, isDark, accent),
                              ],
                            ),
                          ],

                          // Keyboard mode options
                          if (config.clickMode == ClickMode.keyboard) ...[
                            Row(
                              children: [
                                Text('按键', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: textSecondary,
                                  fontFamily: 'Segoe UI Variable, Segoe UI, Microsoft YaHei UI')),
                                const SizedBox(width: 4),
                                _keySelector(config, state, isDark, accent, textPrimary),
                                const Spacer(),
                                Text('模式', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: textSecondary,
                                  fontFamily: 'Segoe UI Variable, Segoe UI, Microsoft YaHei UI')),
                                const SizedBox(width: 4),
                                _chip('重复', config.keyActionMode == KeyActionMode.repeat, () {
                                  state.setClickerConfig(config.copyWith(keyActionMode: KeyActionMode.repeat));
                                }, isDark, accent),
                                const SizedBox(width: 3),
                                _chip('按住', config.keyActionMode == KeyActionMode.hold, () {
                                  state.setClickerConfig(config.copyWith(keyActionMode: KeyActionMode.hold));
                                }, isDark, accent),
                              ],
                            ),
                          ],

                          const SizedBox(height: 4),

                          // Repeat mode
                          Row(
                            children: [
                              Text('重复', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: textSecondary,
                                fontFamily: 'Segoe UI Variable, Segoe UI, Microsoft YaHei UI')),
                              const SizedBox(width: 4),
                              _chip('无限', config.repeatMode == ClickRepeatMode.infinite, () {
                                state.setClickerConfig(config.copyWith(repeatMode: ClickRepeatMode.infinite));
                              }, isDark, accent),
                              const SizedBox(width: 3),
                              _chip('次数', config.repeatMode == ClickRepeatMode.count, () {
                                state.setClickerConfig(config.copyWith(repeatMode: ClickRepeatMode.count));
                              }, isDark, accent),
                              const SizedBox(width: 3),
                              _chip('时长', config.repeatMode == ClickRepeatMode.duration, () {
                                state.setClickerConfig(config.copyWith(repeatMode: ClickRepeatMode.duration));
                              }, isDark, accent),
                              if (config.repeatMode == ClickRepeatMode.count) ...[
                                const SizedBox(width: 4),
                                SizedBox(
                                  width: 48, height: 22,
                                  child: TextBox(
                                    controller: TextEditingController(text: config.repeatCount.toString())
                                      ..selection = TextSelection.collapsed(offset: config.repeatCount.toString().length),
                                    style: TextStyle(fontSize: 10, color: textPrimary),
                                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                    onChanged: (v) {
                                      final n = int.tryParse(v);
                                      if (n != null && n > 0) state.setClickerConfig(config.copyWith(repeatCount: n));
                                    },
                                  ),
                                ),
                              ],
                              if (config.repeatMode == ClickRepeatMode.duration) ...[
                                const SizedBox(width: 4),
                                SizedBox(
                                  width: 48, height: 22,
                                  child: TextBox(
                                    controller: TextEditingController(text: config.durationSeconds.toString())
                                      ..selection = TextSelection.collapsed(offset: config.durationSeconds.toString().length),
                                    style: TextStyle(fontSize: 10, color: textPrimary),
                                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                    onChanged: (v) {
                                      final n = int.tryParse(v);
                                      if (n != null && n > 0) state.setClickerConfig(config.copyWith(durationSeconds: n));
                                    },
                                  ),
                                ),
                                Text('s', style: TextStyle(fontSize: 10, color: textMuted)),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ));
  }

  Widget _titleBtn({required IconData icon, required bool isDark, required Color textMuted, bool active = false, required VoidCallback onPressed}) {
    return GestureDetector(
      onTap: onPressed,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: 22, height: 22,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            color: active ? (isDark ? const Color(0xFF404060) : const Color(0xFFE0E0F0)) : Colors.transparent,
          ),
          child: Icon(icon, size: 9,
            color: active ? FluentTheme.of(context).accentColor : textMuted),
        ),
      ),
    );
  }

  Widget _chip(String label, bool active, VoidCallback onTap, bool isDark, Color accent) {
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color: active ? accent.withValues(alpha: 0.15) : (isDark ? const Color(0xFF2A2A48) : const Color(0xFFF0F0FA)),
            borderRadius: BorderRadius.circular(5),
            border: Border.all(
              color: active ? accent : (isDark ? const Color(0xFF3A3A5A) : const Color(0xFFD0D0E0)),
              width: active ? 1.2 : 0.8,
            ),
          ),
          child: Text(label, style: TextStyle(
            fontSize: 10, fontWeight: active ? FontWeight.w700 : FontWeight.normal,
            color: active ? accent : (isDark ? const Color(0xFFB0B0D0) : const Color(0xFF6A6A80)),
            fontFamily: 'Segoe UI Variable, Segoe UI, Microsoft YaHei UI',
          )),
        ),
      ),
    );
  }

  Widget _keySelector(ClickerConfig config, AppState state, bool isDark, Color accent, Color textPrimary) {
    return GestureDetector(
      onTap: () => _showKeyPicker(config, state, isDark, accent),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF2A2A48) : const Color(0xFFF0F0FA),
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: isDark ? const Color(0xFF3A3A5A) : const Color(0xFFD0D0E0)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(config.keyToRepeat.toUpperCase(), style: TextStyle(
              fontSize: 10, fontWeight: FontWeight.w700, color: accent,
              fontFamily: 'Segoe UI Variable, Segoe UI, Microsoft YaHei UI',
            )),
            const SizedBox(width: 2),
            Icon(FluentIcons.chevron_down, size: 8, color: isDark ? const Color(0xFF8080A0) : const Color(0xFF8A8AA0)),
          ],
        ),
      ),
    );
  }

  void _showKeyPicker(ClickerConfig config, AppState state, bool isDark, Color accent) {
    final overlay = Overlay.of(context);
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (ctx) => _KeyPickerOverlay(
        isDark: isDark,
        accent: accent,
        currentKey: config.keyToRepeat,
        onSelected: (key) {
          state.setClickerConfig(config.copyWith(keyToRepeat: key));
          entry.remove();
        },
        onDismiss: () => entry.remove(),
      ),
    );
    overlay.insert(entry);
  }
}

enum Edge { left, right, top }

/// Custom slider to avoid fluent_ui Slider showValueIndicator bug
class _SimpleSlider extends StatefulWidget {
  final double value;
  final double min;
  final double max;
  final Color accent;
  final ValueChanged<double> onChanged;

  const _SimpleSlider({
    required this.value,
    required this.min,
    required this.max,
    required this.accent,
    required this.onChanged,
  });

  @override
  State<_SimpleSlider> createState() => _SimpleSliderState();
}

class _SimpleSliderState extends State<_SimpleSlider> {
  double? _dragValue;
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    final v = _dragging ? _dragValue! : widget.value;
    final t = ((v - widget.min) / (widget.max - widget.min)).clamp(0.0, 1.0);
    final isDark = FluentTheme.of(context).brightness == Brightness.dark;
    final trackColor = isDark ? const Color(0xFF3A3A5A) : const Color(0xFFD0D0E0);

    return GestureDetector(
      onHorizontalDragStart: (_) => setState(() { _dragging = true; }),
      onHorizontalDragUpdate: (details) {
        final box = context.findRenderObject() as RenderBox;
        final localX = details.localPosition.dx;
        final ratio = (localX / box.size.width).clamp(0.0, 1.0);
        final newValue = widget.min + ratio * (widget.max - widget.min);
        setState(() => _dragValue = newValue);
        widget.onChanged(newValue);
      },
      onHorizontalDragEnd: (_) => setState(() { _dragging = false; _dragValue = null; }),
      child: Container(
        height: 20,
        alignment: Alignment.center,
        child: CustomPaint(
          size: Size(double.infinity, 20),
          painter: _SliderPainter(t: t, trackColor: trackColor, activeColor: widget.accent),
        ),
      ),
    );
  }
}

class _SliderPainter extends CustomPainter {
  final double t;
  final Color trackColor;
  final Color activeColor;

  _SliderPainter({required this.t, required this.trackColor, required this.activeColor});

  @override
  void paint(Canvas canvas, Size size) {
    final cy = size.height / 2;
    final trackR = Radius.circular(2);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromPoints(Offset(0, cy - 2), Offset(size.width, cy + 2)), trackR),
      Paint()..color = trackColor,
    );
    if (t > 0) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromPoints(Offset(0, cy - 2), Offset(size.width * t, cy + 2)), trackR),
        Paint()..color = activeColor,
      );
    }
    final tx = size.width * t;
    canvas.drawCircle(Offset(tx, cy), 6, Paint()..color = activeColor);
    canvas.drawCircle(Offset(tx, cy), 3, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant _SliderPainter old) => old.t != t;
}

class _KeyPickerOverlay extends StatefulWidget {
  final bool isDark;
  final Color accent;
  final String currentKey;
  final ValueChanged<String> onSelected;
  final VoidCallback onDismiss;

  static const _keys = [
    'F1', 'F2', 'F3', 'F4', 'F5', 'F6', 'F7', 'F8', 'F9', 'F10', 'F11', 'F12',
    '0', '1', '2', '3', '4', '5', '6', '7', '8', '9',
    'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm',
    'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z',
    'space', 'enter', 'tab', 'escape', 'backspace', 'delete',
    'insert', 'home', 'end', 'pageup', 'pagedown',
    'up', 'down', 'left', 'right',
    'capslock', 'shift', 'ctrl', 'alt',
    'num0', 'num1', 'num2', 'num3', 'num4', 'num5', 'num6', 'num7', 'num8', 'num9',
  ];

  const _KeyPickerOverlay({
    required this.isDark,
    required this.accent,
    required this.currentKey,
    required this.onSelected,
    required this.onDismiss,
  });

  @override
  State<_KeyPickerOverlay> createState() => _KeyPickerOverlayState();
}

class _KeyPickerOverlayState extends State<_KeyPickerOverlay> {
  final _scrollCtrl = ScrollController();

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  String _label(String k) {
    const labels = {
      'space': 'SPC', 'enter': 'ENT', 'tab': 'TAB', 'escape': 'ESC',
      'backspace': 'BKS', 'delete': 'DEL', 'insert': 'INS', 'home': 'HM',
      'end': 'END', 'pageup': 'PGU', 'pagedown': 'PGD',
      'up': '↑', 'down': '↓', 'left': '←', 'right': '→',
      'capslock': 'CAP', 'shift': 'SHF', 'ctrl': 'CTR', 'alt': 'ALT',
    };
    return labels[k] ?? k.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final bgColor = widget.isDark ? const Color(0xFF252544) : const Color(0xFFF5F5FF);
    final borderColor = widget.isDark ? const Color(0xFF3A3A5A) : const Color(0xFFE0E0EE);
    final textPrimary = widget.isDark ? const Color(0xFFD0D0F0) : const Color(0xFF4A4A70);
    final sectionColor = widget.isDark ? const Color(0xFF8080A0) : const Color(0xFF8A8AA0);

    return Stack(
      children: [
        // Click anywhere to dismiss
        Positioned.fill(
          child: GestureDetector(
            onTap: widget.onDismiss,
            child: Container(color: Colors.black.withValues(alpha: 0.2)),
          ),
        ),
        // Panel
        Center(
          child: Container(
            width: 300,
            constraints: const BoxConstraints(maxHeight: 320),
            padding: const EdgeInsets.fromLTRB(10, 10, 6, 10),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: borderColor),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 16)],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header row - outside scroll area
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Row(children: [
                    Text('选择按键', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: textPrimary)),
                    const Spacer(),
                    GestureDetector(onTap: widget.onDismiss, child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: Container(
                        width: 20, height: 20,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(3),
                          color: widget.isDark ? const Color(0xFF3A3A5A) : const Color(0xFFE0E0EE),
                        ),
                        child: Icon(FluentIcons.chrome_close, size: 10, color: sectionColor),
                      ),
                    )),
                  ]),
                ),
                const SizedBox(height: 8),
                // Scrollable keys area
                Flexible(
                  child: Scrollbar(
                    controller: _scrollCtrl,
                    thumbVisibility: true,
                    child: SingleChildScrollView(
                      controller: _scrollCtrl,
                      padding: const EdgeInsets.only(right: 8),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('功能键', style: TextStyle(fontSize: 9, color: sectionColor)),
                          const SizedBox(height: 3),
                          Wrap(spacing: 3, runSpacing: 3, children: _KeyPickerOverlay._keys.sublist(0, 12).map((k) => _keyBtn(k)).toList()),
                          const SizedBox(height: 6),
                          Text('数字', style: TextStyle(fontSize: 9, color: sectionColor)),
                          const SizedBox(height: 3),
                          Wrap(spacing: 3, runSpacing: 3, children: _KeyPickerOverlay._keys.sublist(12, 22).map((k) => _keyBtn(k)).toList()),
                          const SizedBox(height: 6),
                          Text('字母', style: TextStyle(fontSize: 9, color: sectionColor)),
                          const SizedBox(height: 3),
                          Wrap(spacing: 3, runSpacing: 3, children: _KeyPickerOverlay._keys.sublist(22, 48).map((k) => _keyBtn(k)).toList()),
                          const SizedBox(height: 6),
                          Text('特殊', style: TextStyle(fontSize: 9, color: sectionColor)),
                          const SizedBox(height: 3),
                          Wrap(spacing: 3, runSpacing: 3, children: _KeyPickerOverlay._keys.sublist(48).map((k) => _keyBtn(k)).toList()),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _keyBtn(String k) {
    final active = k == widget.currentKey;
    final borderColor = widget.isDark ? const Color(0xFF3A3A5A) : const Color(0xFFE0E0EE);
    return GestureDetector(
      onTap: () => widget.onSelected(k),
      child: Container(
        width: 28, height: 24,
        decoration: BoxDecoration(
          color: active ? widget.accent.withValues(alpha: 0.2) : (widget.isDark ? const Color(0xFF1E1E36) : const Color(0xFFFAFAFF)),
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: active ? widget.accent : borderColor, width: active ? 1.2 : 0.8),
        ),
        child: Center(child: Text(_label(k), style: TextStyle(
          fontSize: 8, fontWeight: active ? FontWeight.w700 : FontWeight.normal,
          color: active ? widget.accent : (widget.isDark ? const Color(0xFFD0D0F0) : const Color(0xFF4A4A70)),
        ))),
      ),
    );
  }
}
