/// Home screen — Fluent NavigationView with custom title bar & glass effect.
/// Supports window resizing via DragToResizeArea, system tray, and floating window mode.
library;

import 'dart:io';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import 'package:flutter/services.dart';
import '../services/app_state.dart';
import '../services/system_tray_service.dart';
import '../services/plugin_system.dart';
import '../services/plugin_registry.dart';
import 'clicker/clicker_page.dart';
import 'settings/settings_page.dart';
import 'sidebar/plugin_page.dart';
import 'floating_window.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WindowListener {
  int _currentIndex = 0;
  bool _isFloatingMode = false;
  bool _isMaximized = false;
  bool _isClosing = false;

  // Cache plugin page instances with GlobalKeys to preserve state across rebuilds
  final Map<String, ({Widget widget, GlobalKey key})> _pluginPageCache = {};

  // Lazy-loaded page cache: only created when first visited
  final Map<int, Widget> _lazyPages = {};

  Widget _getOrCreatePage(int index) {
    return _lazyPages.putIfAbsent(index, () {
      switch (index) {
        case 0: return const ClickerPage();
        case 1: return const PluginPage();
        default:
          final plugins = PluginRegistry.instance.enabledPlugins;
          final pluginIndex = index - 2;
          if (pluginIndex >= 0 && pluginIndex < plugins.length) {
            final plugin = plugins[pluginIndex];
            final cached = _pluginPageCache[plugin.manifest.id];
            if (cached == null) {
              final key = GlobalKey();
              final widget = KeyedSubtree(key: key, child: Builder(builder: plugin.buildPage));
              _pluginPageCache[plugin.manifest.id] = (widget: widget, key: key);
            }
            return _pluginPageCache[plugin.manifest.id]!.widget;
          }
          return const SettingsPage();
      }
    });
  }

  static const _platformChannel = MethodChannel('com.clicker.pro/platform');

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _initSystemTray();
    _checkMaximized();
    // Rebuild nav when plugins change
    PluginRegistry.instance.addListener(_onPluginsChanged);
  }

  @override
  void dispose() {
    _pluginPageCache.clear();
    PluginRegistry.instance.removeListener(_onPluginsChanged);
    windowManager.removeListener(this);
    super.dispose();
  }

  void _onPluginsChanged() {
    if (mounted) {
      // Reset index if it's out of bounds after plugin change
      final totalItems = 2 + PluginRegistry.instance.enabledPlugins.length + 1; // clicker + separator + plugins + settings
      if (_currentIndex >= totalItems) {
        _currentIndex = 0;
      }
      setState(() {});
    }
  }

  void _checkMaximized() {
    windowManager.isMaximized().then((m) {
      if (mounted) setState(() => _isMaximized = m);
    });
  }

  @override
  void onWindowMaximize() => setState(() => _isMaximized = true);
  @override
  void onWindowUnmaximize() => setState(() => _isMaximized = false);

  Future<void> _initSystemTray() async {
    if (!Platform.isWindows) return;
    final tray = SystemTrayService();
    tray.onShowFloatingWindow = _switchToFloating;
    tray.onShowMainWindow = _switchToMain;
    await tray.init();
  }

  @override
  void onWindowClose() {
    if (_isClosing) return;
    final state = context.read<AppState>();
    if (Platform.isWindows) {
      if (state.hasAskedMinimizeToTray) {
        if (state.minimizeToTray) {
          SystemTrayService().hideToTray();
        } else {
          _cleanupAndExit();
        }
      } else {
        _showCloseDialog(state);
      }
    } else {
      _cleanupAndExit();
    }
  }

  void _cleanupAndExit() {
    if (_isClosing) return;
    _isClosing = true;
    final state = context.read<AppState>();
    state.clickService.stop();
    state.stopMacro();
    state.cancelRecording();
    state.platformInput.stopListening();
    // Use native PostQuitMessage for instant exit.
    // windowManager.destroy() uses PostQuitMessage(0) which is correct,
    // but we also need to destroy the window immediately.
    _platformChannel.invokeMethod('destroyWindow');
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
      SystemTrayService().hideToTray();
    } else if (result == 'close') {
      if (remember) state.setMinimizeToTray(false);
      _cleanupAndExit();
    }
  }

  Future<void> _switchToFloating() async {
    final state = context.read<AppState>();
    setState(() => _isFloatingMode = true);
    // Use native batch method — single platform channel call instead of 5+
    windowManager.setMinimumSize(const Size(180, 60));
    _platformChannel.invokeMethod('switchToFloatingWindow', [state.floatingAlwaysOnTop]);
  }

  Future<void> _switchToMain() async {
    setState(() => _isFloatingMode = false);
    final state = context.read<AppState>();
    // Use native batch method — single platform channel call instead of 6+
    windowManager.setMinimumSize(const Size(500, 680));
    _platformChannel.invokeMethod('switchToMainWindow', [state.alwaysOnTop]);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = FluentTheme.of(context).brightness == Brightness.dark;

    if (_isFloatingMode) {
      return FloatingWindow(onSwitchToMain: _switchToMain);
    }

    final plugins = PluginRegistry.instance.enabledPlugins;
    final totalPages = 2 + plugins.length + 1;

    // _currentIndex is the index into effectiveItems (separators excluded)
    // 0 -> ClickerPage, 1 -> PluginPage, 2..2+plugins-1 -> plugins, 2+plugins -> SettingsPage
    final pageIndex = _currentIndex.clamp(0, totalPages - 1);

    // Ensure current page is created (lazy)
    _getOrCreatePage(pageIndex);

    // Build all created pages for IndexedStack (unvisited slots get placeholder)
    final pages = List<Widget>.generate(totalPages, (i) {
      final page = _lazyPages[i];
      if (page != null) return page;
      return const SizedBox.shrink();
    });

    return DragToResizeArea(
      resizeEdgeSize: 6,
      child: Column(children: [
        _GlassTitleBar(isDark: isDark, isMaximized: _isMaximized, onFloatingMode: _switchToFloating),
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
                PaneItem(icon: const Icon(FluentIcons.touch), title: const Text('连点'), body: const SizedBox.shrink()),
                PaneItemSeparator(),
                PaneItem(icon: const Icon(FluentIcons.puzzle), title: const Text('插件中心'), body: const SizedBox.shrink()),
                ...plugins.map((plugin) =>
                  PaneItem(icon: Icon(plugin.manifest.icon), title: Text(plugin.manifest.name), body: const SizedBox.shrink()),
                ),
              ],
              footerItems: [
                PaneItem(icon: const Icon(FluentIcons.settings), title: const Text('设置'), body: const SizedBox.shrink()),
              ],
            ),
            paneBodyBuilder: (item, body) => IndexedStack(
              index: pageIndex,
              children: pages,
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
  final bool isMaximized;
  final VoidCallback onFloatingMode;
  static const _platformChannel = MethodChannel('com.clicker.pro/platform');
  const _GlassTitleBar({required this.isDark, required this.isMaximized, required this.onFloatingMode});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return GestureDetector(
      onDoubleTap: () {
        if (isMaximized) {
          _platformChannel.invokeMethod('unmaximizeWindow');
        } else {
          _platformChannel.invokeMethod('maximizeWindow');
        }
      },
      onPanStart: (_) => windowManager.startDragging(),
      child: Container(
        height: 36,
        decoration: BoxDecoration(
          color: isDark
            ? const Color(0xFF16162A).withValues(alpha:0.88)
            : const Color(0xFFF0F0FA).withValues(alpha:0.88),
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
          _WindowButton(icon: FluentIcons.chrome_minimize, isDark: isDark, onPressed: () => _platformChannel.invokeMethod('minimizeWindow')),
          _MaximizeButton(isDark: isDark, isMaximized: isMaximized),
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
  final bool isMaximized;
  const _MaximizeButton({required this.isDark, required this.isMaximized});
  @override
  State<_MaximizeButton> createState() => _MaximizeButtonState();
}

class _MaximizeButtonState extends State<_MaximizeButton> {
  bool _hovering = false;
  static const _platformChannel = MethodChannel('com.clicker.pro/platform');

  @override
  Widget build(BuildContext context) {
    final color = widget.isDark ? const Color(0xFF9090B0) : const Color(0xFF6A6A80);
    return GestureDetector(
      onTap: () {
        if (widget.isMaximized) {
          _platformChannel.invokeMethod('unmaximizeWindow');
        } else {
          _platformChannel.invokeMethod('maximizeWindow');
        }
      },
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovering = true),
        onExit: (_) => setState(() => _hovering = false),
        child: Container(
          width: 46, height: 36,
          color: _hovering ? (widget.isDark ? const Color(0xFF404060) : const Color(0xFFE0E0F0)) : Colors.transparent,
          child: Center(
            child: widget.isMaximized
              ? _RestoreIcon(color: color)
              : _MaximizeIcon(color: color),
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
