/// Theme center page — actually applies theme, accent color, and visual effects.
library;

import 'package:fluent_ui/fluent_ui.dart';
import 'package:provider/provider.dart';
import '../../services/app_state.dart';

class ThemeCenterPage extends StatelessWidget {
  const ThemeCenterPage({super.key});

  static const _accentOptions = [
    _AccentOption('紫罗兰', Color(0xFF7C4DFF)),
    _AccentOption('天蓝', Color(0xFF00BCD4)),
    _AccentOption('玫红', Color(0xFFFF4081)),
    _AccentOption('翠绿', Color(0xFF4CAF50)),
    _AccentOption('琥珀', Color(0xFFFFB300)),
    _AccentOption('烈焰', Color(0xFFFF6D00)),
    _AccentOption('靛蓝', Color(0xFF3F51B5)),
    _AccentOption('薄荷', Color(0xFF26A69A)),
  ];

  static const _themePresets = [
    _ThemePreset(name: '深邃紫夜', primary: Color(0xFF7C4DFF), isDark: true),
    _ThemePreset(name: '极光蓝', primary: Color(0xFF00BCD4), isDark: true),
    _ThemePreset(name: '赛博粉', primary: Color(0xFFFF4081), isDark: true),
    _ThemePreset(name: '森林绿', primary: Color(0xFF4CAF50), isDark: true),
    _ThemePreset(name: '日落橙', primary: Color(0xFFFF6D00), isDark: true),
    _ThemePreset(name: '极简白', primary: Color(0xFF7C4DFF), isDark: false),
    _ThemePreset(name: '暖阳黄', primary: Color(0xFFFFB300), isDark: false),
    _ThemePreset(name: '薄荷青', primary: Color(0xFF26A69A), isDark: false),
  ];

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final isDark = state.themeMode == 'dark';
    final accent = state.accentColor;

    return ScaffoldPage.scrollable(
      padding: const EdgeInsets.all(20),
      children: [
        // Header
        Row(children: [
          Icon(FluentIcons.color, size: 20, color: accent),
          const SizedBox(width: 10),
          const Text('主题中心', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 20),

        // ── Dark/Light mode ──────────────────────────────────
        _sectionTitle('外观模式', isDark),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: _modeChip('深色模式', isDark, () => state.setThemeMode('dark'), isDark)),
          const SizedBox(width: 8),
          Expanded(child: _modeChip('浅色模式', !isDark, () => state.setThemeMode('light'), isDark)),
        ]),

        const SizedBox(height: 20),

        // ── Theme presets ────────────────────────────────────
        _sectionTitle('主题预设', isDark),
        const SizedBox(height: 8),
        Wrap(spacing: 10, runSpacing: 10, children: [
          for (final preset in _themePresets)
            _buildPresetCard(preset, preset.primary == accent && preset.isDark == isDark, isDark, state),
        ]),

        const SizedBox(height: 20),

        // ── Accent color ────────────────────────────────────
        _sectionTitle('强调色', isDark),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final opt in _accentOptions)
            _buildAccentChip(opt, opt.color == accent, isDark, state),
        ]),

        const SizedBox(height: 20),

        // ── Custom color ─────────────────────────────────────
        _sectionTitle('自定义颜色', isDark),
        const SizedBox(height: 8),
        _buildCustomColorCard(isDark, state),
      ],
    );
  }

  Widget _sectionTitle(String title, bool isDark) {
    return Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700,
      color: isDark ? const Color(0xFFC0C0E8) : const Color(0xFF5A5A80)));
  }

  Widget _modeChip(String label, bool selected, VoidCallback onTap, bool isDark) {
    final bgColor = isDark ? const Color(0xFF252540) : const Color(0xFFF0F0FA);
    return Builder(builder: (context) {
      final accent = FluentTheme.of(context).accentColor;
      return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: BoxDecoration(
            color: selected ? accent.withValues(alpha: 0.15) : bgColor,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: selected ? accent : (isDark ? const Color(0xFF303050) : const Color(0xFFD0D0E0)), width: selected ? 2 : 1),
          ),
          child: Center(child: Text(label, style: TextStyle(
            fontSize: 14, fontWeight: selected ? FontWeight.w700 : FontWeight.normal,
            color: selected ? accent : (isDark ? const Color(0xFFC0C0D8) : const Color(0xFF5A5A70)),
          ))),
        ),
      ),
    );
    });
  }

  Widget _buildPresetCard(_ThemePreset preset, bool selected, bool isDark, AppState state) {
    final bg = preset.isDark ? const Color(0xFF1A1A2E) : const Color(0xFFF5F5FA);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () {
          state.setThemeMode(preset.isDark ? 'dark' : 'light');
          state.setAccentColor(preset.primary);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 130, height: 90,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: selected ? preset.primary : (isDark ? const Color(0xFF303050) : const Color(0xFFD0D0E0)), width: selected ? 2.5 : 1),
            boxShadow: selected ? [BoxShadow(color: preset.primary.withValues(alpha: 0.3), blurRadius: 8, spreadRadius: 1)] : null,
          ),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Container(width: 40, height: 4, decoration: BoxDecoration(color: preset.primary, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 8),
            Container(width: 60, height: 3, decoration: BoxDecoration(color: preset.primary.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 4),
            Container(width: 45, height: 3, decoration: BoxDecoration(color: preset.primary.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 10),
            Text(preset.name, style: TextStyle(fontSize: 11, fontWeight: selected ? FontWeight.w700 : FontWeight.normal,
              color: preset.isDark ? const Color(0xFFC0C0E8) : const Color(0xFF5A5A80))),
          ]),
        ),
      ),
    );
  }

  Widget _buildAccentChip(_AccentOption opt, bool selected, bool isDark, AppState state) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => state.setAccentColor(opt.color),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? opt.color.withValues(alpha: 0.15) : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: selected ? opt.color : (isDark ? const Color(0xFF404060) : const Color(0xFFD0D0D8))),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 14, height: 14, decoration: BoxDecoration(
              color: opt.color, borderRadius: BorderRadius.circular(4),
              border: Border.all(color: selected ? Colors.white : Colors.transparent, width: 2),
            )),
            const SizedBox(width: 6),
            Text(opt.name, style: TextStyle(fontSize: 12, fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
              color: selected ? opt.color : (isDark ? const Color(0xFFC0C0D8) : const Color(0xFF5A5A70)))),
          ]),
        ),
      ),
    );
  }

  Widget _buildCustomColorCard(bool isDark, AppState state) {
    final cardBg = isDark ? const Color(0xFF252540).withValues(alpha: 0.5) : const Color(0xFFF0F0FA).withValues(alpha: 0.5);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: isDark ? const Color(0xFF303050) : const Color(0xFFD0D0E0)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('输入十六进制颜色值', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Row(children: [
          SizedBox(width: 120, child: TextBox(
            placeholder: '#7C4DFF',
            onChanged: (v) {
              final hex = v.replaceFirst('#', '');
              if (hex.length == 6) {
                final val = int.tryParse(hex, radix: 16);
                if (val != null) state.setAccentColor(Color(0xFF000000 + val));
              }
            },
          )),
          const SizedBox(width: 12),
          Container(width: 32, height: 32, decoration: BoxDecoration(
            color: state.accentColor,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: isDark ? const Color(0xFF404060) : const Color(0xFFD0D0D8)),
          )),
          const SizedBox(width: 8),
          Text('当前: #${state.accentColor.toARGB32().toRadixString(16).substring(2).toUpperCase()}', style: TextStyle(fontSize: 12, color: isDark ? const Color(0xFF9090B0) : const Color(0xFF8A8A9A))),
        ]),
      ]),
    );
  }
}

class _ThemePreset {
  final String name;
  final Color primary;
  final bool isDark;
  const _ThemePreset({required this.name, required this.primary, required this.isDark});
}

class _AccentOption {
  final String name;
  final Color color;
  const _AccentOption(this.name, this.color);
}
