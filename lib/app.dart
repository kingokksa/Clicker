/// App entry point — initialises state and launches FluentApp.
library;

import 'package:fluent_ui/fluent_ui.dart';
import 'package:provider/provider.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart' as acrylic;
import 'services/app_state.dart';
import 'screens/home_screen.dart';

class ClickerApp extends StatelessWidget {
  const ClickerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AppState()..init(),
      child: Consumer<AppState>(
        builder: (context, state, _) {
          _updateAcrylic(state.themeMode, state.accentColor);

          if (!state.isInitialized) {
            return FluentApp(
              debugShowCheckedModeBanner: false,
              home: const ScaffoldPage(
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
              scaffoldBackgroundColor: const Color(0xFFF8F8FC).withOpacity(0.88),
              cardColor: Colors.white.withOpacity(0.78),
              navigationPaneTheme: NavigationPaneThemeData(
                backgroundColor: const Color(0xFFF2F2FA).withOpacity(0.75),
              ),
            ),
            darkTheme: FluentThemeData(
              brightness: Brightness.dark,
              accentColor: _toAccent(accent),
              visualDensity: VisualDensity.standard,
              fontFamily: 'Segoe UI Variable, Segoe UI, Microsoft YaHei UI, PingFang SC, sans-serif',
              scaffoldBackgroundColor: const Color(0xFF16162A).withOpacity(0.88),
              cardColor: const Color(0xFF22223A).withOpacity(0.78),
              navigationPaneTheme: NavigationPaneThemeData(
                backgroundColor: const Color(0xFF16162A).withOpacity(0.75),
              ),
            ),
            themeMode: isDark ? ThemeMode.dark : ThemeMode.light,
            home: const HomeScreen(),
          );
        },
      ),
    );
  }

  void _updateAcrylic(String themeMode, Color accent) {
    final isDark = themeMode == 'dark';
    acrylic.Window.setEffect(
      effect: acrylic.WindowEffect.acrylic,
      color: isDark ? const Color(0xFF16162A) : const Color(0xFFF8F8FC),
      dark: isDark,
    );
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
