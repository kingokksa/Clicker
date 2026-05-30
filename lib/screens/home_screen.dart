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
  String _currentPageId = 'clicker';
  bool _isFloatingMode = false;
  bool _isMaximized = false;
  bool _isClosing = false;

  final Map<String, ({Widget widget, GlobalKey key})> _pluginPageCache = {};
  final Map<String, ({Widget widget, GlobalKey key})> _lazyPages = {};

  int _pageIdToIndex(String pageId) {
    final plugins = PluginRegistry.instance.enabledPlugins;
    if (pageId == 'clicker') return 0;
    for (int i = 0; i < plugins.length; i++) {
      if (plugins[i].manifest.id == pageId) return i + 1;
    }
    final pluginCount = plugins.length;
    if (pageId == 'plugin_center') return pluginCount + 1;
    if (pageId == 'settings') return pluginCount + 2;
    return 0;
  }

  String _indexToPageId(int index) {
    final plugins = PluginRegistry.instance.enabledPlugins;
    final pluginCount = plugins.length;
    if (index == 0) return 'clicker';
    if (index >= 1 && index <= pluginCount) return plugins[index - 1].manifest.id;
    if (index == pluginCount + 1) return 'plugin_center';
    if (index == pluginCount + 2) return 'settings';
    return 'clicker';
  }

  Widget _getOrCreatePage(String pageId) {
    final existing = _lazyPages[pageId];
    if (existing != null) return existing.widget;

    final plugins = PluginRegistry.instance.enabledPlugins;

    Widget page;
    GlobalKey key;

    if (pageId == 'clicker') {
      key = GlobalKey();
      page = KeyedSubtree(key: key, child: const ClickerPage());
    } else if (plugins.any((p) => p.manifest.id == pageId)) {
      final plugin = plugins.firstWhere((p) => p.manifest.id == pageId);
      final cached = _pluginPageCache[pageId];
      if (cached == null) {
        key = GlobalKey();
        final widget = KeyedSubtree(key: key, child: Builder(builder: plugin.buildPage));
        _pluginPageCache[pageId] = (widget: widget, key: key);
        _lazyPages[pageId] = (widget: widget, key: key);
        return widget;
      }
      _lazyPages[pageId] = cached;
      return cached.widget;
    } else if (pageId == 'plugin_center') {
      key = GlobalKey();
      page = KeyedSubtree(key: key, child: const PluginPage());
    } else {
      key = GlobalKey();
      page = KeyedSubtree(key: key, child: const SettingsPage());
    }

    final entry = (widget: page, key: key);
    _lazyPages[pageId] = entry;
    return page;
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
      final enabledIds = PluginRegistry.instance.enabledPlugins.map((p) => p.manifest.id).toSet();
      _pluginPageCache.removeWhere((id, _) => !enabledIds.contains(id));
      _lazyPages.removeWhere((id, _) => id != 'clicker' && id != 'plugin_center' && id != 'settings' && !enabledIds.contains(id));
      if (!enabledIds.contains(_currentPageId) &&
          _currentPageId != 'clicker' &&
          _currentPageId != 'plugin_center' &&
          _currentPageId != 'settings') {
        _currentPageId = 'clicker';
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
    final appState = context.watch<AppState>();

    _getOrCreatePage(_currentPageId);

    final currentPage = _lazyPages[_currentPageId]?.widget ?? const SizedBox.shrink();
    final currentIndex = _pageIdToIndex(_currentPageId);

    return DragToResizeArea(
      resizeEdgeSize: 6,
      child: Column(children: [
        _GlassTitleBar(isDark: isDark, isMaximized: _isMaximized, onFloatingMode: _switchToFloating, animations: appState.uiAnimations),
        Expanded(child: Row(children: [
          _buildSidebar(isDark, plugins, currentIndex),
          // Page content — rendered directly without AnimatedSwitcher
          Expanded(child: ColoredBox(
            color: FluentTheme.of(context).scaffoldBackgroundColor,
            child: AnimatedSwitcher(
              duration: appState.uiAnimations ? const Duration(milliseconds: 200) : Duration.zero,
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: child,
              ),
              child: KeyedSubtree(key: ValueKey(_currentPageId), child: currentPage),
            ),
          )),
        ])),
      ]),
    );
  }

  Widget _buildSidebar(bool isDark, List<ClickerPlugin> plugins, int selectedIndex) {
    final accent = FluentTheme.of(context).accentColor;
    const compactWidth = 50.0;
    final bgColor = isDark ? const Color(0xFF16162A) : const Color(0xFFF2F2FA);

    // Build all sidebar items
    final items = <_SidebarItem>[
      _SidebarItem(icon: FluentIcons.touch, label: '连点', index: 0),
      // Plugin items (index 1..pluginCount)
      for (int i = 0; i < plugins.length; i++)
        _SidebarItem(icon: plugins[i].manifest.icon, label: plugins[i].manifest.name, index: i + 1),
      // Footer items
      _SidebarItem(icon: FluentIcons.puzzle, label: '插件中心', index: plugins.length + 1),
      _SidebarItem(icon: FluentIcons.settings, label: '设置', index: plugins.length + 2),
    ];

    return Container(
      width: compactWidth,
      color: bgColor.withValues(alpha: 0.75),
      child: Column(children: [
        // Header
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text('C', style: TextStyle(
            fontSize: 14, fontWeight: FontWeight.w700,
            fontFamily: 'Segoe UI Variable, Segoe UI, Microsoft YaHei UI',
            color: isDark ? const Color(0xFFC0C0E8) : const Color(0xFF5A5A80),
          )),
        ),
        // Main items
        Expanded(child: ListView.builder(
          padding: EdgeInsets.zero,
          itemCount: items.length - 2, // exclude footer items
          itemBuilder: (ctx, i) => _buildSidebarItem(items[i], selectedIndex, accent, isDark),
        )),
        // Footer items (plugin center + settings)
        ...List.generate(2, (i) => _buildSidebarItem(items[items.length - 2 + i], selectedIndex, accent, isDark)),
        const SizedBox(height: 8),
      ]),
    );
  }

  Widget _buildSidebarItem(_SidebarItem item, int selectedIndex, AccentColor accent, bool isDark) {
    final selected = item.index == selectedIndex;
    final selectedBg = accent.withValues(alpha: 0.15);
    final state = context.watch<AppState>();
    final animations = state.uiAnimations;

    return Tooltip(
      message: item.label,
      child: _SidebarItemButton(
        item: item,
        selected: selected,
        selectedBg: selectedBg,
        accent: accent,
        isDark: isDark,
        animations: animations,
        onTap: () => setState(() => _currentPageId = _indexToPageId(item.index)),
      ),
    );
  }
}

class _SidebarItemButton extends StatefulWidget {
  final _SidebarItem item;
  final bool selected;
  final Color selectedBg;
  final AccentColor accent;
  final bool isDark;
  final bool animations;
  final VoidCallback onTap;
  const _SidebarItemButton({
    required this.item,
    required this.selected,
    required this.selectedBg,
    required this.accent,
    required this.isDark,
    required this.animations,
    required this.onTap,
  });
  @override
  State<_SidebarItemButton> createState() => _SidebarItemButtonState();
}

class _SidebarItemButtonState extends State<_SidebarItemButton> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final hoverColor = widget.isDark ? const Color(0xFF303050) : const Color(0xFFE0E0F0);
    final bgColor = widget.selected
      ? widget.selectedBg
      : (_hovering ? hoverColor : Colors.transparent);
    final iconColor = widget.selected
      ? widget.accent
      : (widget.isDark ? const Color(0xFF9090B0) : const Color(0xFF6A6A80));

    return GestureDetector(
      onTap: widget.onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovering = true),
        onExit: (_) => setState(() => _hovering = false),
        child: AnimatedContainer(
          duration: widget.animations ? const Duration(milliseconds: 200) : Duration.zero,
          curve: Curves.easeOutCubic,
          width: 50,
          height: 42,
          margin: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Center(child: AnimatedScale(
            duration: widget.animations ? const Duration(milliseconds: 200) : Duration.zero,
            curve: Curves.easeOutCubic,
            scale: widget.selected ? 1.15 : 1.0,
            child: Icon(widget.item.icon, size: 16, color: iconColor),
          )),
        ),
      ),
    );
  }
}

class _SidebarItem {
  final IconData icon;
  final String label;
  final int index;
  const _SidebarItem({required this.icon, required this.label, required this.index});
}

// ─── Title Bar ───────────────────────────────────────────────

class _GlassTitleBar extends StatelessWidget {
  final bool isDark;
  final bool isMaximized;
  final VoidCallback onFloatingMode;
  final bool animations;
  static const _platformChannel = MethodChannel('com.clicker.pro/platform');
  const _GlassTitleBar({required this.isDark, required this.isMaximized, required this.onFloatingMode, required this.animations});

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
          _TopMostButton(isDark: isDark, isPinned: state.alwaysOnTop, animations: animations, onToggle: () {
            final v = !state.alwaysOnTop;
            state.setAlwaysOnTop(v);
            windowManager.setAlwaysOnTop(v);
          }),
          _WindowButton(
            icon: FluentIcons.back_to_window,
            isDark: isDark,
            animations: animations,
            tooltip: '悬浮窗',
            onPressed: onFloatingMode,
          ),
          _WindowButton(icon: FluentIcons.chrome_minimize, isDark: isDark, animations: animations, onPressed: () => _platformChannel.invokeMethod('minimizeWindow')),
          _MaximizeButton(isDark: isDark, isMaximized: isMaximized, animations: animations),
          _WindowButton(icon: FluentIcons.chrome_close, isDark: isDark, animations: animations, isClose: true, onPressed: () => windowManager.close()),
        ]),
      ),
    );
  }
}

// ─── Window Buttons ──────────────────────────────────────────

class _TopMostButton extends StatefulWidget {
  final bool isDark;
  final bool isPinned;
  final bool animations;
  final VoidCallback onToggle;
  const _TopMostButton({required this.isDark, required this.isPinned, required this.animations, required this.onToggle});
  @override
  State<_TopMostButton> createState() => _TopMostButtonState();
}

class _TopMostButtonState extends State<_TopMostButton> with SingleTickerProviderStateMixin {
  bool _hovering = false;
  late final AnimationController _scaleCtrl;
  late final Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _scaleCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 150));
    _scaleAnim = Tween<double>(begin: 1.0, end: 0.9).animate(
      CurvedAnimation(parent: _scaleCtrl, curve: Curves.easeOutCubic),
    );
  }

  @override
  void dispose() {
    _scaleCtrl.dispose();
    super.dispose();
  }

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
          onEnter: (_) => setState(() { _hovering = true; _scaleCtrl.forward(); }),
          onExit: (_) => setState(() { _hovering = false; _scaleCtrl.reverse(); }),
          child: Container(
            width: 36, height: 36, color: bgColor,
            child: Center(child: ScaleTransition(
              scale: widget.animations ? _scaleAnim : const AlwaysStoppedAnimation(1.0),
              child: AnimatedSwitcher(
                duration: widget.animations ? const Duration(milliseconds: 200) : Duration.zero,
                transitionBuilder: (child, animation) => FadeTransition(opacity: animation, child: child),
                child: Icon(
                  widget.isPinned ? FluentIcons.pinned_fill : FluentIcons.pinned,
                  key: ValueKey(widget.isPinned),
                  size: 10,
                  color: widget.isPinned ? accent : (widget.isDark ? const Color(0xFF9090B0) : const Color(0xFF6A6A80)),
                ),
              ),
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
  final bool animations;
  final String? tooltip;
  final VoidCallback onPressed;
  const _WindowButton({required this.icon, required this.isDark, this.isClose = false, required this.animations, this.tooltip, required this.onPressed});
  @override
  State<_WindowButton> createState() => _WindowButtonState();
}

class _WindowButtonState extends State<_WindowButton> with SingleTickerProviderStateMixin {
  bool _hovering = false;
  late final AnimationController _scaleCtrl;
  late final Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _scaleCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 150));
    _scaleAnim = Tween<double>(begin: 1.0, end: 0.9).animate(
      CurvedAnimation(parent: _scaleCtrl, curve: Curves.easeOutCubic),
    );
  }

  @override
  void dispose() {
    _scaleCtrl.dispose();
    super.dispose();
  }

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
          onEnter: (_) => setState(() { _hovering = true; _scaleCtrl.forward(); }),
          onExit: (_) => setState(() { _hovering = false; _scaleCtrl.reverse(); }),
          child: Container(
              width: 46, height: 36, color: bgColor,
              child: Center(child: ScaleTransition(
                scale: widget.animations ? _scaleAnim : const AlwaysStoppedAnimation(1.0),
                child: Icon(widget.icon, size: 10,
                  color: _hovering && widget.isClose ? Colors.white : (widget.isDark ? const Color(0xFF9090B0) : const Color(0xFF6A6A80)),
                ),
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
  final bool animations;
  const _MaximizeButton({required this.isDark, required this.isMaximized, required this.animations});
  @override
  State<_MaximizeButton> createState() => _MaximizeButtonState();
}

class _MaximizeButtonState extends State<_MaximizeButton> with SingleTickerProviderStateMixin {
  bool _hovering = false;
  late final AnimationController _scaleCtrl;
  late final Animation<double> _scaleAnim;
  static const _platformChannel = MethodChannel('com.clicker.pro/platform');

  @override
  void initState() {
    super.initState();
    _scaleCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 150));
    _scaleAnim = Tween<double>(begin: 1.0, end: 0.9).animate(
      CurvedAnimation(parent: _scaleCtrl, curve: Curves.easeOutCubic),
    );
  }

  @override
  void dispose() {
    _scaleCtrl.dispose();
    super.dispose();
  }

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
        onEnter: (_) => setState(() { _hovering = true; _scaleCtrl.forward(); }),
        onExit: (_) => setState(() { _hovering = false; _scaleCtrl.reverse(); }),
        child: Container(
            width: 46, height: 36,
            color: _hovering ? (widget.isDark ? const Color(0xFF404060) : const Color(0xFFE0E0F0)) : Colors.transparent,
            child: Center(
              child: ScaleTransition(
                scale: widget.animations ? _scaleAnim : const AlwaysStoppedAnimation(1.0),
                child: AnimatedSwitcher(
                  duration: widget.animations ? const Duration(milliseconds: 200) : Duration.zero,
                  transitionBuilder: (child, animation) => FadeTransition(opacity: animation, child: child),
                  child: widget.isMaximized
                    ? _RestoreIcon(key: const ValueKey('restore'), color: color)
                    : _MaximizeIcon(key: const ValueKey('maximize'), color: color),
                ),
              ),
            ),
          ),
      ),
    );
  }
}

// ─── Custom Icons ────────────────────────────────────────────

class _MaximizeIcon extends StatelessWidget {
  final Color color;
  const _MaximizeIcon({super.key, required this.color});
  @override
  Widget build(BuildContext context) => CustomPaint(size: const Size(10, 10), painter: _RectPainter(color: color));
}

class _RestoreIcon extends StatelessWidget {
  final Color color;
  const _RestoreIcon({super.key, required this.color});
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
