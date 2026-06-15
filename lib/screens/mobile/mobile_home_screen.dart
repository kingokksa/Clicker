/// Mobile home screen — Material bottom navigation with clicker, macro, hold trigger, settings tabs.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/mobile_app_state.dart';
import 'mobile_clicker_page.dart';
import 'mobile_macro_page.dart';
import 'mobile_hold_trigger_page.dart';
import 'mobile_settings_page.dart';

class MobileHomeScreen extends StatefulWidget {
  const MobileHomeScreen({super.key});

  @override
  State<MobileHomeScreen> createState() => _MobileHomeScreenState();
}

class _MobileHomeScreenState extends State<MobileHomeScreen> {
  int _currentIndex = 0;

  static const _pages = <Widget>[
    MobileClickerPage(),
    MobileMacroPage(),
    MobileHoldTriggerPage(),
    MobileSettingsPage(),
  ];

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
        onDestinationSelected: (i) => setState(() => _currentIndex = i),
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
            icon: Icon(Icons.settings_outlined, color: isDark ? Colors.grey : Colors.grey),
            selectedIcon: Icon(Icons.settings, color: accent),
            label: '设置',
          ),
        ],
      ),
    );
  }
}
