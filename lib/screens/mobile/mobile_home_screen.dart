/// Mobile home screen — Material bottom navigation with clicker, macro, hold trigger, settings tabs.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/mobile_app_state.dart';
import 'mobile_clicker_page.dart';
import 'mobile_macro_page.dart';
import 'mobile_hold_trigger_page.dart';
import 'mobile_schedule_page.dart';
import 'mobile_humanize_page.dart';
import 'mobile_vision_page.dart';
import 'mobile_settings_page.dart';

class MobileHomeScreen extends StatefulWidget {
  const MobileHomeScreen({super.key});

  @override
  State<MobileHomeScreen> createState() => _MobileHomeScreenState();
}

class _MobileHomeScreenState extends State<MobileHomeScreen> {
  int _currentIndex = 0;
  final _visionKey = GlobalKey<MobileVisionPageState>();

  late final List<Widget> _pages = <Widget>[
    MobileClickerPage(),
    MobileMacroPage(),
    MobileHoldTriggerPage(),
    const MobileSchedulePage(),
    const MobileHumanizePage(),
    MobileVisionPage(key: _visionKey),
    MobileSettingsPage(),
  ];

  /// 识别 tab 在底部导航中的下标 — 切到该页时重新检查无障碍服务状态。
  static const int _visionTabIndex = 5;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<MobileAppState>();
    final isDark = state.themeMode == 'dark';
    final accent = state.accentColor;

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _pages,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (i) {
          setState(() => _currentIndex = i);
          // Re-check the accessibility service each time the 识别 (vision) tab is
          // selected, so toggling it in Settings is reflected without an app restart.
          if (i == _visionTabIndex) _visionKey.currentState?.checkAccessibility();
        },
        backgroundColor: isDark ? const Color(0xFF1A1A2E) : Colors.white,
        indicatorColor: accent.withValues(alpha: 0.2),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: [
          NavigationDestination(
            icon: Icon(Icons.touch_app_outlined, color: isDark ? Colors.grey : Colors.grey),
            selectedIcon: Icon(Icons.touch_app, color: accent),
            label: '连点',
          ),
          NavigationDestination(
            icon: Icon(Icons.playlist_play_outlined, color: isDark ? Colors.grey : Colors.grey),
            selectedIcon: Icon(Icons.playlist_play, color: accent),
            label: '宏',
          ),
          NavigationDestination(
            icon: Icon(Icons.back_hand_outlined, color: isDark ? Colors.grey : Colors.grey),
            selectedIcon: Icon(Icons.back_hand, color: accent),
            label: '长按',
          ),
          NavigationDestination(
            icon: const Icon(Icons.schedule_outlined, color: Colors.grey),
            selectedIcon: Icon(Icons.schedule, color: accent),
            label: '定时',
          ),
          NavigationDestination(
            icon: const Icon(Icons.people_outline, color: Colors.grey),
            selectedIcon: Icon(Icons.people, color: accent),
            label: '拟人',
          ),
          NavigationDestination(
            icon: Icon(Icons.center_focus_weak_outlined, color: isDark ? Colors.grey : Colors.grey),
            selectedIcon: Icon(Icons.center_focus_strong, color: accent),
            label: '识别',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined, color: isDark ? Colors.grey : Colors.grey),
            selectedIcon: Icon(Icons.settings, color: accent),
            label: '设置',
          ),
        ],
      ),
    );
  }
}
