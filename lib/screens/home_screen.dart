/// Home screen — Fluent NavigationView with custom title bar & glass effect.
/// Supports window resizing via DragToResizeArea, system tray, and floating window mode.
library;

import 'dart:async';
import 'dart:io';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import 'package:flutter/services.dart';
import '../services/app_state.dart';
import '../services/system_tray_service.dart';
import '../services/plugin/plugin_manager.dart';
import '../services/plugin/plugin_host.dart';
import '../services/plugin/plugin_manifest.dart';
import '../services/plugin/icon_resolver.dart';
import 'clicker/clicker_page.dart';
import 'settings/settings_page.dart';
import 'sidebar/plugin_page.dart';
import 'floating_window.dart';

/// 导航条目（来自已启用插件 manifest 的页面声明，静态数据零加载成本）
class _NavItem {
  final String pageId;
  final String label;
  final IconData icon;
  const _NavItem({required this.pageId, required this.label, required this.icon});
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  /// Global key to access HomeScreen state for navigation
  static final GlobalKey<HomeScreenState> globalKey = GlobalKey();

  @override
  State<HomeScreen> createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> with WindowListener {
  String _currentPageId = 'clicker';
  bool _isFloatingMode = false;
  bool _isMaximized = false;
  bool _isClosing = false;

  /// 插件页面 widget 缓存（激活后首次构建，切换页面不销毁）
  final Map<String, Widget> _pluginPageCache = {};
  /// 按需激活防重入
  final Set<String> _activatingPages = {};
  /// 导航条目缓存 — 仅在插件列表变化（启用/停用/安装）时重算，
  /// 避免每次 build 遍历全部插件 manifest
  List<_NavItem>? _navItemsCache;

  /// Navigate to a specific page by ID (e.g., 'macro', 'hold_trigger', 'settings')
  void navigateTo(String pageId) {
    if (mounted) setState(() => _currentPageId = pageId);
  }

  /// 导航条目：已启用插件 manifest 声明的页面（静态，无需激活插件）。
  /// 点击页面时才触发插件按需激活（onPage 事件）。结果缓存。
  List<_NavItem> _navItems() {
    if (_navItemsCache != null) return _navItemsCache!;
    final pm = PluginManager.instance;
    final items = <_NavItem>[];
    for (final desc in pm.plugins) {
      if (!pm.isInstalled(desc.id) || !pm.isEnabled(desc.id)) continue;
      for (final page in desc.manifest.contributions.pages) {
        if (!page.showInNav) continue;
        items.add(_NavItem(
          pageId: resolveFullPageId(desc.id, page.id),
          label: page.title,
          icon: resolvePluginIcon(page.icon ?? desc.manifest.icon),
        ));
      }
    }
    // 按 manifest 声明的 order 排序（PageContribution 无序时保持注册顺序）
    final orders = <String, int>{};
    for (final desc in pm.plugins) {
      for (final page in desc.manifest.contributions.pages) {
        orders[resolveFullPageId(desc.id, page.id)] = page.order;
      }
    }
    items.sort((a, b) =>
        (orders[a.pageId] ?? 100).compareTo(orders[b.pageId] ?? 100));
    _navItemsCache = items;
    return items;
  }

  int _pageIdToIndex(String pageId, List<_NavItem> navItems) {
    if (pageId == 'clicker') return 0;
    for (int i = 0; i < navItems.length; i++) {
      if (navItems[i].pageId == pageId) return i + 1;
    }
    final n = navItems.length;
    if (pageId == 'plugin_center') return n + 1;
    if (pageId == 'settings') return n + 2;
    return 0;
  }

  String _indexToPageId(int index, List<_NavItem> navItems) {
    final n = navItems.length;
    if (index == 0) return 'clicker';
    if (index >= 1 && index <= n) return navItems[index - 1].pageId;
    if (index == n + 1) return 'plugin_center';
    if (index == n + 2) return 'settings';
    return 'clicker';
  }

  /// 页面切换入口：插件页面若未激活则触发按需激活
  void _selectPage(String pageId) {
    setState(() => _currentPageId = pageId);
    final reg = PluginHost.instance.page(pageId);
    if (reg == null) _ensurePageActivated(pageId);
  }

  void _ensurePageActivated(String pageId) {
    if (_activatingPages.contains(pageId)) return;
    _activatingPages.add(pageId);
    PluginManager.instance.ensurePageActivated(pageId).whenComplete(() {
      _activatingPages.remove(pageId);
    });
  }

  /// 构建页面内容。插件页面优先从 PluginHost 取已注册 builder；
  /// 未注册（插件未激活）时显示加载占位并触发按需激活，
  /// 激活完成后 PluginHost 通知重建，即可渲染真实页面。
  Widget _buildPageContent(String pageId) {
    if (pageId == 'clicker') return const ClickerPage();
    if (pageId == 'plugin_center') return const PluginPage();
    if (pageId == 'settings') return const SettingsPage();

    final cached = _pluginPageCache[pageId];
    if (cached != null) return cached;

    final reg = PluginHost.instance.page(pageId);
    if (reg != null) {
      final widget = Builder(builder: reg.builder);
      _pluginPageCache[pageId] = widget;
      return widget;
    }

    // 插件未激活 — 触发按需激活并显示占位
    _ensurePageActivated(pageId);
    return const Center(child: ProgressRing());
  }

  static const _platformChannel = MethodChannel('com.clicker.pro/platform');

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _initSystemTray();
    _checkMaximized();
    // 插件状态/扩展点变化时重建导航
    PluginManager.instance.addListener(_onPluginStateChanged);
    PluginHost.instance.addListener(_onPluginStateChanged);
  }

  @override
  void dispose() {
    _pluginPageCache.clear();
    PluginManager.instance.removeListener(_onPluginStateChanged);
    PluginHost.instance.removeListener(_onPluginStateChanged);
    windowManager.removeListener(this);
    super.dispose();
  }

  void _onPluginStateChanged() {
    if (!mounted) return;
    _navItemsCache = null;  // 插件列表/状态变化 — 导航缓存失效
    final validIds = _navItems().map((i) => i.pageId).toSet();
    // 插件停用后移除其页面缓存
    _pluginPageCache.removeWhere((id, _) => !validIds.contains(id));
    if (!validIds.contains(_currentPageId) &&
        _currentPageId != 'clicker' &&
        _currentPageId != 'plugin_center' &&
        _currentPageId != 'settings') {
      _currentPageId = 'clicker';
    }
    setState(() {});
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
    // 通知插件应用退出并释放全部资源
    unawaited(PluginManager.instance.shutdown());
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

    final navItems = _navItems();
    // 细粒度订阅：只监听本组件实际用到的字段（动画开关）。
    // 此前 watch 整个 AppState — 连点计数每 500ms 刷新会触发整页
    // （含 IndexedStack 所有页面）无差别重建，是 UI 卡顿主因之一。
    final uiAnimations = context.select<AppState, bool>((s) => s.uiAnimations);

    final currentIndex = _pageIdToIndex(_currentPageId, navItems);

    // Build all pages in order for IndexedStack
    final allPageIds = <String>[
      'clicker',
      for (final item in navItems) item.pageId,
      'plugin_center',
      'settings',
    ];

    final pages =
        allPageIds.map(_buildPageContent).toList();

    return DragToResizeArea(
      resizeEdgeSize: 6,
      child: Column(children: [
        _GlassTitleBar(isDark: isDark, isMaximized: _isMaximized, onFloatingMode: _switchToFloating, animations: uiAnimations),
        Expanded(child: Row(children: [
          _buildSidebar(isDark, navItems, currentIndex),
          // Page content — IndexedStack keeps all pages alive (no dispose on switch)
          Expanded(child: ColoredBox(
            color: FluentTheme.of(context).scaffoldBackgroundColor,
            child: IndexedStack(
              index: currentIndex,
              children: pages,
            ),
          )),
        ])),
      ]),
    );
  }

  Widget _buildSidebar(bool isDark, List<_NavItem> navItems, int selectedIndex) {
    final accent = FluentTheme.of(context).accentColor;
    const compactWidth = 50.0;
    final bgColor = isDark ? const Color(0xFF16162A) : const Color(0xFFF2F2FA);

    // Build all sidebar items
    final items = <_SidebarItem>[
      const _SidebarItem(icon: FluentIcons.touch, label: '连点', index: 0),
      // Plugin nav items (index 1..n)
      for (int i = 0; i < navItems.length; i++)
        _SidebarItem(icon: navItems[i].icon, label: navItems[i].label, index: i + 1),
      // Footer items
      _SidebarItem(icon: FluentIcons.puzzle, label: '插件中心', index: navItems.length + 1),
      _SidebarItem(icon: FluentIcons.settings, label: '设置', index: navItems.length + 2),
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
          itemBuilder: (ctx, i) => _buildSidebarItem(items[i], navItems, selectedIndex, accent, isDark),
        )),
        // Footer items (plugin center + settings)
        ...List.generate(2, (i) => _buildSidebarItem(items[items.length - 2 + i], navItems, selectedIndex, accent, isDark)),
        const SizedBox(height: 8),
      ]),
    );
  }

  Widget _buildSidebarItem(_SidebarItem item, List<_NavItem> navItems, int selectedIndex, AccentColor accent, bool isDark) {
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
        onTap: () => _selectPage(_indexToPageId(item.index, navItems)),
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
            ? const Color(0xFF16162A).withValues(alpha: 0.88)
            : const Color(0xFFF0F0FA).withValues(alpha: 0.88),
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
