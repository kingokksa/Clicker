/// Home screen — Fluent NavigationView with custom title bar & glass effect.
/// Supports window resizing via DragToResizeArea, system tray, and floating window mode.
library;

import 'dart:io';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import '../services/app_state.dart';
import '../services/system_tray_service.dart';
import 'clicker/clicker_page.dart';
import 'macro/macro_page.dart';
import 'settings/settings_page.dart';
import 'sidebar/plugin_page.dart';
import 'sidebar/image_recognition_page.dart';
import 'sidebar/theme_center_page.dart';
import 'sidebar/background_execution_page.dart';
import 'floating_window.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WindowListener {
  int _currentIndex = 0;
  bool _isFloatingMode = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _initSystemTray();
  }

  Future<void> _initSystemTray() async {
    if (!Platform.isWindows) return;
    final tray = SystemTrayService();
    tray.onShowFloatingWindow = _switchToFloating;
    tray.onShowMainWindow = _switchToMain;
    await tray.init();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowClose() async {
    final state = context.read<AppState>();
    if (Platform.isWindows) {
      if (state.hasAskedMinimizeToTray) {
        // User already made a choice before
        if (state.minimizeToTray) {
          await SystemTrayService().hideToTray();
        } else {
          await _cleanupAndExit();
        }
      } else {
        // First time: show prompt
        _showCloseDialog(state);
      }
    } else {
      await windowManager.destroy();
    }
  }

  Future<void> _cleanupAndExit() async {
    final state = context.read<AppState>();
    // Stop all running services before exit
    state.clickService.stop();
    state.stopMacro();
    state.cancelRecording();
    state.platformInput.stopListening();
    await windowManager.destroy();
  }

  Future<void> _showCloseDialog(AppState state) async {
    bool remember = false;
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => ContentDialog(
          title: const Text('关闭确认'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('你希望如何关闭？'),
            const SizedBox(height: 16),
            Row(children: [
              Checkbox(
                checked: remember,
                onChanged: (v) => setDialogState(() => remember = v ?? false),
              ),
              const SizedBox(width: 8),
              const Text('记住我的选择', style: TextStyle(fontSize: 13)),
            ]),
          ]),
          actions: [
            Button(
              onPressed: () => Navigator.pop(ctx, 'close'),
              child: const Text('直接退出'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, 'tray'),
              child: const Text('最小化到托盘'),
            ),
          ],
        ),
      ),
    );

    if (result == 'tray') {
      if (remember) state.setMinimizeToTray(true);
      await SystemTrayService().hideToTray();
    } else if (result == 'close') {
      if (remember) state.setMinimizeToTray(false);
      await _cleanupAndExit();
    }
  }

  Future<void> _switchToFloating() async {
    final state = context.read<AppState>();
    setState(() => _isFloatingMode = true);
    await windowManager.setMinimumSize(const Size(180, 60));
    await windowManager.setSize(const Size(280, 95));
    await windowManager.setAlwaysOnTop(state.floatingAlwaysOnTop);
    await windowManager.show();
    await windowManager.focus();
  }

  Future<void> _switchToMain() async {
    setState(() => _isFloatingMode = false);
    await windowManager.setAlwaysOnTop(false);
    await windowManager.setMinimumSize(const Size(500, 680));
    await windowManager.setSize(const Size(920, 720));
    await windowManager.center();
    await windowManager.show();
    await windowManager.focus();
    // Re-apply always-on-top setting from app state
    final state = context.read<AppState>();
    if (state.alwaysOnTop) {
      await windowManager.setAlwaysOnTop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = FluentTheme.of(context).brightness == Brightness.dark;

    if (_isFloatingMode) {
      return FloatingWindow(onSwitchToMain: _switchToMain);
    }

    return DragToResizeArea(
      resizeEdgeSize: 6,
      child: Column(children: [
        _GlassTitleBar(isDark: isDark, onFloatingMode: _switchToFloating),
        Expanded(child: NavigationView(
            pane: NavigationPane(
              selected: _currentIndex,
              onChanged: (i) => setState(() => _currentIndex = i),
              displayMode: PaneDisplayMode.compact,
              header: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Text('Clicker', style: TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w700,
                  fontFamily: 'Segoe UI Variable, Segoe UI, Microsoft YaHei UI',
                  color: isDark ? const Color(0xFFC0C0E8) : const Color(0xFF5A5A80),
                )),
              ),
              items: [
                PaneItem(icon: const Icon(FluentIcons.touch), title: const Text('连点'), body: const ClickerPage()),
                PaneItem(icon: const Icon(FluentIcons.record2), title: const Text('宏'), body: const MacroPage()),
                PaneItemSeparator(),
                PaneItem(icon: const Icon(FluentIcons.puzzle), title: const Text('功能管理'), body: const PluginPage()),
                PaneItem(icon: const Icon(FluentIcons.settings), title: const Text('后台执行'), body: const BackgroundExecutionPage()),
                PaneItem(icon: const Icon(FluentIcons.image_pixel), title: const Text('图像识别'), body: const ImageRecognitionPage()),
                PaneItem(icon: const Icon(FluentIcons.color), title: const Text('主题中心'), body: const ThemeCenterPage()),
              ],
              footerItems: [
                PaneItem(icon: const Icon(FluentIcons.settings), title: const Text('设置'), body: const SettingsPage()),
              ],
            ),
          ),
        ),
      ]),
    );
  }
}

// ─── Title Bar ───────────────────────────────────────────────

class _GlassTitleBar extends StatelessWidget {
  final bool isDark;
  final VoidCallback onFloatingMode;
  const _GlassTitleBar({required this.isDark, required this.onFloatingMode});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return GestureDetector(
      onDoubleTap: () async {
        if (await windowManager.isMaximized()) {
          windowManager.unmaximize();
        } else {
          windowManager.maximize();
        }
      },
      onPanStart: (_) => windowManager.startDragging(),
      child: Container(
        height: 36,
        decoration: BoxDecoration(
          color: isDark
            ? const Color(0xFF16162A).withOpacity(0.88)
            : const Color(0xFFF0F0FA).withOpacity(0.88),
          border: Border(
            bottom: BorderSide(
              color: isDark ? const Color(0xFF303050) : const Color(0xFFD0D0E0),
              width: 1,
            ),
          ),
        ),
        child: Row(children: [
          const SizedBox(width: 12),
          Icon(FluentIcons.touch, size: 14, color: FluentTheme.of(context).accentColor),
          const SizedBox(width: 8),
          Text('Clicker', style: TextStyle(
            fontSize: 12, fontWeight: FontWeight.w600,
            fontFamily: 'Segoe UI Variable, Segoe UI, Microsoft YaHei UI',
            color: isDark ? const Color(0xFFC0C0E8) : const Color(0xFF5A5A80),
          )),
          const Spacer(),
          // Always-on-top toggle
          _TopMostButton(isDark: isDark, isPinned: state.alwaysOnTop, onToggle: () {
            final v = !state.alwaysOnTop;
            state.setAlwaysOnTop(v);
            windowManager.setAlwaysOnTop(v);
          }),
          // Floating window button
          _WindowButton(
            icon: FluentIcons.back_to_window,
            isDark: isDark,
            tooltip: '悬浮窗',
            onPressed: onFloatingMode,
          ),
          _WindowButton(icon: FluentIcons.chrome_minimize, isDark: isDark, onPressed: () => windowManager.minimize()),
          _MaximizeButton(isDark: isDark),
          _WindowButton(icon: FluentIcons.chrome_close, isDark: isDark, isClose: true, onPressed: () => windowManager.close()),
        ]),
      ),
    );
  }
}

// ─── Window Buttons ──────────────────────────────────────────

class _TopMostButton extends StatefulWidget {
  final bool isDark;
  final bool isPinned;
  final VoidCallback onToggle;
  const _TopMostButton({required this.isDark, required this.isPinned, required this.onToggle});
  @override
  State<_TopMostButton> createState() => _TopMostButtonState();
}

class _TopMostButtonState extends State<_TopMostButton> {
  bool _hovering = false;
  @override
  Widget build(BuildContext context) {
    final accent = FluentTheme.of(context).accentColor;
    final bgColor = _hovering
      ? (widget.isDark ? const Color(0xFF404060) : const Color(0xFFE0E0F0))
      : Colors.transparent;
    return Tooltip(
      message: widget.isPinned ? '取消置顶' : '置顶',
      child: GestureDetector(
        onTap: widget.onToggle,
        child: MouseRegion(
          onEnter: (_) => setState(() => _hovering = true),
          onExit: (_) => setState(() => _hovering = false),
          child: Container(
            width: 36, height: 36, color: bgColor,
            child: Center(child: Icon(
              widget.isPinned ? FluentIcons.pinned_fill : FluentIcons.pinned,
              size: 10,
              color: widget.isPinned ? accent : (widget.isDark ? const Color(0xFF9090B0) : const Color(0xFF6A6A80)),
            )),
          ),
        ),
      ),
    );
  }
}

class _WindowButton extends StatefulWidget {
  final IconData icon;
  final bool isDark;
  final bool isClose;
  final String? tooltip;
  final VoidCallback onPressed;
  const _WindowButton({required this.icon, required this.isDark, this.isClose = false, this.tooltip, required this.onPressed});
  @override
  State<_WindowButton> createState() => _WindowButtonState();
}

class _WindowButtonState extends State<_WindowButton> {
  bool _hovering = false;
  @override
  Widget build(BuildContext context) {
    final bgColor = widget.isClose
      ? (_hovering ? Colors.red : Colors.transparent)
      : (_hovering ? (widget.isDark ? const Color(0xFF404060) : const Color(0xFFE0E0F0)) : Colors.transparent);
    return Tooltip(
      message: widget.tooltip ?? '',
      child: GestureDetector(
        onTap: widget.onPressed,
        child: MouseRegion(
          onEnter: (_) => setState(() => _hovering = true),
          onExit: (_) => setState(() => _hovering = false),
          child: Container(
            width: 46, height: 36, color: bgColor,
            child: Center(child: Icon(widget.icon, size: 10,
              color: _hovering && widget.isClose ? Colors.white : (widget.isDark ? const Color(0xFF9090B0) : const Color(0xFF6A6A80)),
            )),
          ),
        ),
      ),
    );
  }
}

class _MaximizeButton extends StatefulWidget {
  final bool isDark;
  const _MaximizeButton({required this.isDark});
  @override
  State<_MaximizeButton> createState() => _MaximizeButtonState();
}

class _MaximizeButtonState extends State<_MaximizeButton> {
  bool _hovering = false;
  bool _isMaximized = false;

  @override
  void initState() {
    super.initState();
    _checkMaximized();
  }

  Future<void> _checkMaximized() async {
    final m = await windowManager.isMaximized();
    if (mounted && _isMaximized != m) setState(() => _isMaximized = m);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () async {
        if (await windowManager.isMaximized()) { await windowManager.unmaximize(); } else { await windowManager.maximize(); }
        _checkMaximized();
      },
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovering = true),
        onExit: (_) => setState(() => _hovering = false),
        child: Container(
          width: 46, height: 36,
          color: _hovering ? (widget.isDark ? const Color(0xFF404060) : const Color(0xFFE0E0F0)) : Colors.transparent,
          child: Center(
            child: _isMaximized
              ? _RestoreIcon(color: widget.isDark ? const Color(0xFF9090B0) : const Color(0xFF6A6A80))
              : _MaximizeIcon(color: widget.isDark ? const Color(0xFF9090B0) : const Color(0xFF6A6A80)),
          ),
        ),
      ),
    );
  }
}

// ─── Custom Icons ────────────────────────────────────────────

class _MaximizeIcon extends StatelessWidget {
  final Color color;
  const _MaximizeIcon({required this.color});
  @override
  Widget build(BuildContext context) => CustomPaint(size: const Size(10, 10), painter: _RectPainter(color: color));
}

class _RestoreIcon extends StatelessWidget {
  final Color color;
  const _RestoreIcon({required this.color});
  @override
  Widget build(BuildContext context) => CustomPaint(size: const Size(10, 10), painter: _RestorePainter(color: color));
}

class _RectPainter extends CustomPainter {
  final Color color;
  _RectPainter({required this.color});
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = 1;
    canvas.drawRect(Rect.fromLTWH(0.5, 0.5, size.width - 1, size.height - 1), p);
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _RestorePainter extends CustomPainter {
  final Color color;
  _RestorePainter({required this.color});
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = 1;
    canvas.drawRect(Rect.fromLTWH(0, 2.5, size.width - 3, size.height - 3), p);
    canvas.drawRect(Rect.fromLTWH(2.5, 0, size.width - 3, size.height - 3), p);
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
