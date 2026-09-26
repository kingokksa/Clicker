/// App entry point — initialises state and launches FluentApp.
library;

import 'package:fluent_ui/fluent_ui.dart';
import 'package:provider/provider.dart';
import 'services/app_state.dart';
import 'screens/home_screen.dart';

class ClickerApp extends StatefulWidget {
  const ClickerApp({super.key});

  @override
  State<ClickerApp> createState() => _ClickerAppState();
}

class _ClickerAppState extends State<ClickerApp> {
  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AppState()..init(),
      child: Consumer<AppState>(
        builder: (context, state, _) {
          if (!state.isInitialized) {
            return const FluentApp(
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
          final uiScale = state.uiScale;
          return FluentApp(
            title: 'Clicker',
            debugShowCheckedModeBanner: false,
            theme: FluentThemeData(
              brightness: Brightness.light,
              accentColor: _toAccent(accent),
              visualDensity: VisualDensity.standard,
              fontFamily: 'Segoe UI Variable, Segoe UI, Microsoft YaHei UI, PingFang SC, sans-serif',
              scaffoldBackgroundColor: const Color(0xFFF8F8FC),
              cardColor: Colors.white,
              navigationPaneTheme: NavigationPaneThemeData(
                backgroundColor: const Color(0xFFF2F2FA),
              ),
            ),
            darkTheme: FluentThemeData(
              brightness: Brightness.dark,
              accentColor: _toAccent(accent),
              visualDensity: VisualDensity.standard,
              fontFamily: 'Segoe UI Variable, Segoe UI, Microsoft YaHei UI, PingFang SC, sans-serif',
              scaffoldBackgroundColor: const Color(0xFF16162A),
              cardColor: const Color(0xFF22223A),
              navigationPaneTheme: NavigationPaneThemeData(
                backgroundColor: const Color(0xFF16162A),
              ),
            ),
            themeMode: isDark ? ThemeMode.dark : ThemeMode.light,
            builder: (context, child) {
              // 统一放大所有文本：全局 textScaler 会同时作用于主题排版
              // 和各页面硬编码的 fontSize，一次生效、无需逐组件改字号。
              final media = MediaQuery.of(context);
              return MediaQuery(
                data: media.copyWith(textScaler: TextScaler.linear(uiScale)),
                child: ExcludeSemantics(child: child!),
              );
            },
            home: HomeScreen(key: HomeScreen.globalKey),
          );
        },
      ),
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