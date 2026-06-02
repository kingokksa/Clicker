/// App entry point — initialises state and launches FluentApp.
library;

import 'dart:io';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:provider/provider.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart' as acrylic;
import 'package:flutter/services.dart';
import 'services/app_state.dart';
import 'screens/home_screen.dart';

class ClickerApp extends StatefulWidget {
  const ClickerApp({super.key});

  @override
  State<ClickerApp> createState() => _ClickerAppState();
}

class _ClickerAppState extends State<ClickerApp> {
  String? _lastThemeMode;
  Color? _lastAccentColor;
  static const _platformChannel = MethodChannel('com.clicker.pro/platform');

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AppState()..init(),
      child: Consumer<AppState>(
        builder: (context, state, _) {
          // Only update acrylic when theme or accent actually changes
          // to avoid constant DWM reconfiguration causing lag/flicker
          if (_lastThemeMode != state.themeMode || _lastAccentColor != state.accentColor) {
            _lastThemeMode = state.themeMode;
            _lastAccentColor = state.accentColor;
            _updateAcrylic(state.themeMode, state.accentColor);
          }

          if (!state.isInitialized) {
            return FluentApp(
              debugShowCheckedModeBanner: false,
              home: ExcludeSemantics(
                child: ScaffoldPage(
                content: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ProgressRing(),
                      SizedBox(height: 16),
                      Text('正在初始化...'),
                    ],
                  ),
                ),
              ),
            ),
            );
          }

          final isDark = state.themeMode == 'dark';
          final accent = state.accentColor;
          return FluentApp(
            title: 'Clicker',
            debugShowCheckedModeBanner: false,
            theme: FluentThemeData(
              brightness: Brightness.light,
              accentColor: _toAccent(accent),
              visualDensity: VisualDensity.standard,
              fontFamily: 'Segoe UI Variable, Segoe UI, Microsoft YaHei UI, PingFang SC, sans-serif',
              scaffoldBackgroundColor: const Color(0xFFF8F8FC).withValues(alpha: 0.88),
              cardColor: Colors.white.withValues(alpha: 0.78),
              navigationPaneTheme: NavigationPaneThemeData(
                backgroundColor: const Color(0xFFF2F2FA).withValues(alpha: 0.75),
                animationDuration: Duration.zero,
              ),
            ),
            darkTheme: FluentThemeData(
              brightness: Brightness.dark,
              accentColor: _toAccent(accent),
              visualDensity: VisualDensity.standard,
              fontFamily: 'Segoe UI Variable, Segoe UI, Microsoft YaHei UI, PingFang SC, sans-serif',
              scaffoldBackgroundColor: const Color(0xFF16162A).withValues(alpha: 0.88),
              cardColor: const Color(0xFF22223A).withValues(alpha: 0.78),
              navigationPaneTheme: NavigationPaneThemeData(
                backgroundColor: const Color(0xFF16162A).withValues(alpha: 0.75),
                animationDuration: Duration.zero,
              ),
            ),
            themeMode: isDark ? ThemeMode.dark : ThemeMode.light,
            builder: (context, child) {
              return ExcludeSemantics(child: child!);
            },
            home: const HomeScreen(),
          );
        },
      ),
    );
  }

  void _updateAcrylic(String themeMode, Color accent) {
    if (!Platform.isWindows) return;
    final isDark = themeMode == 'dark';
    try {
      acrylic.Window.setEffect(
        effect: acrylic.WindowEffect.acrylic,
        color: isDark ? const Color(0xFF16162A) : const Color(0xFFF8F8FC),
        dark: isDark,
      );
    } catch (_) {}
    try {
      _platformChannel.invokeMethod('reapplyDwmFixes');
    } catch (_) {}
  }
}

/// Helper to create AccentColor from a Color value for FluentThemeData.
AccentColor _toAccent(Color c) {
  return AccentColor.swatch({
    'darkest': c,
    'darker': c,
    'dark': c,
    'normal': c,
    'light': Color.lerp(c, Colors.white, 0.2) ?? c,
    'lighter': Color.lerp(c, Colors.white, 0.4) ?? c,
    'lightest': Color.lerp(c, Colors.white, 0.6) ?? c,
  });
}
