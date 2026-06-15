/// Mobile app entry point — Material Design for Android/iOS.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'services/mobile_app_state.dart';
import 'screens/mobile/mobile_home_screen.dart';

class MobileClickerApp extends StatefulWidget {
  const MobileClickerApp({super.key});

  @override
  State<MobileClickerApp> createState() => _MobileClickerAppState();
}

class _MobileClickerAppState extends State<MobileClickerApp> {
  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => MobileAppState()..init(),
      child: Consumer<MobileAppState>(
        builder: (context, state, _) {
          if (!state.isInitialized) {
            return MaterialApp(
              debugShowCheckedModeBanner: false,
              home: Scaffold(
                body: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: state.accentColor),
                      const SizedBox(height: 16),
                      const Text('正在初始化...'),
                    ],
                  ),
                ),
              ),
            );
          }

          final isDark = state.themeMode == 'dark';
          final accent = state.accentColor;

          return MaterialApp(
            title: 'Clicker',
            debugShowCheckedModeBanner: false,
            theme: ThemeData(
              brightness: Brightness.light,
              colorSchemeSeed: accent,
              useMaterial3: true,
              scaffoldBackgroundColor: const Color(0xFFF8F8FC),
              cardTheme: CardThemeData(
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            darkTheme: ThemeData(
              brightness: Brightness.dark,
              colorSchemeSeed: accent,
              useMaterial3: true,
              scaffoldBackgroundColor: const Color(0xFF121220),
              cardTheme: CardThemeData(
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            themeMode: isDark ? ThemeMode.dark : ThemeMode.light,
            home: const MobileHomeScreen(),
          );
        },
      ),
    );
  }
}
