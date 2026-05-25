/// Floating mini-window — compact overlay with core features.
/// Always-on-top, draggable, with essential clicker controls.
library;

import 'package:fluent_ui/fluent_ui.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import '../services/app_state.dart';
import '../models/clicker_config.dart';

class FloatingWindow extends StatefulWidget {
  final VoidCallback onSwitchToMain;
  const FloatingWindow({super.key, required this.onSwitchToMain});

  @override
  State<FloatingWindow> createState() => _FloatingWindowState();
}

class _FloatingWindowState extends State<FloatingWindow> with WindowListener {
  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowClose() => windowManager.hide();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final isDark = FluentTheme.of(context).brightness == Brightness.dark;
    final config = state.clickerConfig;
    final isRunning = state.isClickerRunning;
    final accent = state.accentColor;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E36).withValues(alpha:0.95) : const Color(0xFFFAFAFF).withValues(alpha:0.95),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? const Color(0xFF3A3A5A) : const Color(0xFFE0E0EE),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha:0.18),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title bar
            GestureDetector(
              onPanStart: (_) => windowManager.startDragging(),
              child: Container(
                height: 32,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF252544).withValues(alpha:0.95) : const Color(0xFFF0F0FA).withValues(alpha:0.95),
                  border: Border(bottom: BorderSide(
                    color: isDark ? const Color(0xFF3A3A5A) : const Color(0xFFE0E0EE),
                    width: 0.5,
                  )),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(FluentIcons.touch, size: 12, color: accent),
                    const SizedBox(width: 6),
                    Text('Clicker', style: TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w700,
                      color: isDark ? const Color(0xFFD0D0F0) : const Color(0xFF4A4A70),
                      fontFamily: 'Segoe UI Variable, Segoe UI, Microsoft YaHei UI',
                    )),
                    const Spacer(),
                    _miniButton(
                      icon: state.floatingAlwaysOnTop ? FluentIcons.pinned_fill : FluentIcons.pinned,
                      isDark: isDark,
                      active: state.floatingAlwaysOnTop,
                      onPressed: () {
                        final v = !state.floatingAlwaysOnTop;
                        state.setFloatingAlwaysOnTop(v);
                        windowManager.setAlwaysOnTop(v);
                      },
                    ),
                    const SizedBox(width: 2),
                    _miniButton(
                      icon: FluentIcons.back_to_window,
                      isDark: isDark,
                      onPressed: widget.onSwitchToMain,
                    ),
                    const SizedBox(width: 2),
                    _miniButton(
                      icon: FluentIcons.chrome_close,
                      isDark: isDark,
                      onPressed: () => windowManager.hide(),
                    ),
                  ],
                ),
              ),
            ),

            // Content
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Toggle button + mode chips in one row
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 120,
                        height: 30,
                        child: FilledButton(
                          style: ButtonStyle(
                            backgroundColor: WidgetStateProperty.resolveWith((states) {
                              if (isRunning) return const Color(0xFFE53935);
                              return accent;
                            }),
                            shape: WidgetStateProperty.all(RoundedRectangleBorder(borderRadius: BorderRadius.circular(6))),
                            padding: WidgetStateProperty.all(EdgeInsets.zero),
                          ),
                          onPressed: state.toggleClicker,
                          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                            Icon(isRunning ? FluentIcons.stop : FluentIcons.play, size: 12, color: Colors.white),
                            const SizedBox(width: 4),
                            Text(
                              isRunning ? '停止' : '开始',
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white,
                                fontFamily: 'Segoe UI Variable, Segoe UI, Microsoft YaHei UI'),
                            ),
                          ]),
                        ),
                      ),
                      const SizedBox(width: 6),
                      _modeChip('鼠', config.clickMode == ClickMode.mouse, () {
                        state.setClickerConfig(config.copyWith(clickMode: ClickMode.mouse));
                      }, isDark),
                      const SizedBox(width: 3),
                      _modeChip('键', config.clickMode == ClickMode.keyboard, () {
                        state.setClickerConfig(config.copyWith(clickMode: ClickMode.keyboard));
                      }, isDark),
                    ],
                  ),

                  const SizedBox(height: 6),

                  // Interval slider row
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('间隔', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600,
                        color: isDark ? const Color(0xFFB0B0D0) : const Color(0xFF5A5A70),
                        fontFamily: 'Segoe UI Variable, Segoe UI, Microsoft YaHei UI')),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Slider(
                          value: config.intervalMs.toDouble().clamp(10.0, 5000.0),
                          min: 10.0, max: 5000.0,
                          divisions: 499,
                          onChanged: (v) {
                            state.setClickerConfig(config.copyWith(intervalMs: v.roundToDouble()));
                          },
                        ),
                      ),
                      SizedBox(width: 42, child: Text(
                        config.intervalMs >= 1000 ? '${(config.intervalMs / 1000).toStringAsFixed(1)}s' : '${config.intervalMs}ms',
                        style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700,
                          color: isDark ? const Color(0xFFD0D0F0) : const Color(0xFF4A4A70),
                          fontFamily: 'Segoe UI Variable, Segoe UI, Microsoft YaHei UI'),
                        textAlign: TextAlign.right,
                      )),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _miniButton({required IconData icon, required bool isDark, bool active = false, required VoidCallback onPressed}) {
    return GestureDetector(
      onTap: onPressed,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          width: 22, height: 22,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            color: active ? (isDark ? const Color(0xFF404060) : const Color(0xFFE0E0F0)) : Colors.transparent,
          ),
          child: Icon(icon, size: 9,
            color: active ? FluentTheme.of(context).accentColor : (isDark ? const Color(0xFF9090B0) : const Color(0xFF6A6A80))),
        ),
      ),
    );
  }

  Widget _modeChip(String label, bool active, VoidCallback onTap, bool isDark) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: active
            ? FluentTheme.of(context).accentColor.withValues(alpha:0.15)
            : (isDark ? const Color(0xFF2A2A48) : const Color(0xFFF0F0FA)),
          borderRadius: BorderRadius.circular(5),
          border: Border.all(
            color: active
              ? FluentTheme.of(context).accentColor
              : (isDark ? const Color(0xFF3A3A5A) : const Color(0xFFD0D0E0)),
          ),
        ),
        child: Text(label, style: TextStyle(
          fontSize: 10, fontWeight: active ? FontWeight.w700 : FontWeight.normal,
          color: active
            ? FluentTheme.of(context).accentColor
            : (isDark ? const Color(0xFFB0B0D0) : const Color(0xFF6A6A80)),
          fontFamily: 'Segoe UI Variable, Segoe UI, Microsoft YaHei UI',
        )),
      ),
    );
  }
}
