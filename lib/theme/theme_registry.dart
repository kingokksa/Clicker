/// Theme extension API — allows custom themes to be registered and applied.
///
/// Users or plugins can define their own color schemes and register them
/// so they appear in the settings page theme selector.
library;

import 'package:fluent_ui/fluent_ui.dart';

/// Describes a custom theme pack.
class ThemePack {
  final String id;
  final String name;
  final FluentThemeData lightTheme;
  final FluentThemeData darkTheme;

  const ThemePack({
    required this.id,
    required this.name,
    required this.lightTheme,
    required this.darkTheme,
  });
}

/// Registry for theme packs.
class ThemeRegistry {
  ThemeRegistry._();
  static final ThemeRegistry instance = ThemeRegistry._();

  final Map<String, ThemePack> _packs = {};

  /// All registered theme packs.
  List<ThemePack> get packs => _packs.values.toList();

  /// Built-in theme ids.
  static const String defaultId = 'default';

  /// Register a theme pack.
  void register(ThemePack pack) {
    _packs[pack.id] = pack;
  }

  /// Unregister a theme pack by id.
  void unregister(String id) {
    if (id == defaultId) return; // prevent removing built-in
    _packs.remove(id);
  }

  /// Get a theme pack by id, or null.
  ThemePack? getPack(String id) => _packs[id];

  /// Initialize with the built-in default theme.
  void initDefaults() {
    if (_packs.containsKey(defaultId)) return;
    register(ThemePack(
      id: defaultId,
      name: '默认 (Purple)',
      lightTheme: FluentThemeData(
        brightness: Brightness.light,
        accentColor: Colors.purple,
        visualDensity: VisualDensity.standard,
        scaffoldBackgroundColor: const Color(0xFFF5F5FA).withOpacity(0.85),
        cardColor: Colors.white.withOpacity(0.75),
        navigationPaneTheme: NavigationPaneThemeData(
          backgroundColor: const Color(0xFFF0F0FA).withOpacity(0.6),
        ),
      ),
      darkTheme: FluentThemeData(
        brightness: Brightness.dark,
        accentColor: Colors.purple,
        visualDensity: VisualDensity.standard,
        scaffoldBackgroundColor: const Color(0xFF1A1A2E).withOpacity(0.85),
        cardColor: const Color(0xFF252540).withOpacity(0.75),
        navigationPaneTheme: NavigationPaneThemeData(
          backgroundColor: const Color(0xFF1A1A2E).withOpacity(0.6),
        ),
      ),
    ));
  }
}
