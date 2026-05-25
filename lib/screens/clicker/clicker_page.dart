/// Auto-clicker page — Fluent UI design.
library;

import 'package:fluent_ui/fluent_ui.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import '../../services/app_state.dart';
import '../../models/clicker_config.dart';
import '../../models/hotkey_config.dart';
import '../../widgets/position_picker_dialog.dart' show PositionPickerOverlay;

class ClickerPage extends StatelessWidget {
  const ClickerPage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final theme = FluentTheme.of(context);
    final config = state.clickerConfig;
    final isKeyboard = config.clickMode == ClickMode.keyboard;
    final isWide = MediaQuery.of(context).size.width >= 700;

    final modeSections = <Widget>[
      _section(title: '操作模式', icon: FluentIcons.switch_widget, child: _buildModeSelector(context, config, state, theme)),
    ];

    if (isKeyboard) {
      modeSections.addAll([
        _spacing,
        _section(title: '按键动作', icon: FluentIcons.keyboard_classic, child: _buildKeyActionSelector(config, state, theme)),
        if (config.keyActionMode == KeyActionMode.repeat) ...[
          _spacing, _section(title: '按键选择', icon: FluentIcons.keyboard_classic, child: _buildKeySelector(context, config, state, theme)),
        ],
        if (config.keyActionMode == KeyActionMode.hold) ...[
          _spacing, _section(title: '按住按键', icon: FluentIcons.back, child: _buildKeySelector(context, config, state, theme)),
        ],
        if (config.keyActionMode == KeyActionMode.sequence) ...[
          _spacing, _section(title: '按键序列', icon: FluentIcons.bulleted_list, child: _buildKeySequenceEditor(context, config, state, theme)),
        ],
        if (config.keyActionMode == KeyActionMode.combo) ...[
          _spacing, _section(title: '组合键', icon: FluentIcons.merge, child: _buildComboKeyEditor(context, config, state, theme)),
        ],
        if (config.keyActionMode == KeyActionMode.text) ...[
          _spacing, _section(title: '自动打字', icon: FluentIcons.font, child: _buildTextTypeEditor(context, config, state, theme)),
        ],
        _spacing, _section(title: '防检测', icon: FluentIcons.shield, subtitle: '模拟人工按键抖动', child: _buildJitterSettings(config, state, theme)),
      ]);
    } else {
      modeSections.addAll([
        _spacing, _section(title: '点击类型', icon: FluentIcons.touch, child: _buildClickTypeSelector(config, state, theme)),
        _spacing, _section(title: '鼠标按键', icon: FluentIcons.touch_pointer, child: _buildMouseButtonSelector(config, state, theme)),
        _spacing, _section(title: '点击位置', icon: FluentIcons.map_pin, child: _buildPositionSelector(context, config, state, theme)),
        _spacing, _section(title: '随机偏移', icon: FluentIcons.open_in_new_tab, subtitle: '模拟人工点击偏移', child: _buildRandomOffset(config, state, theme)),
      ]);
    }

    final settingsSections = <Widget>[
      _inlineSection(title: isKeyboard ? '按键间隔' : '点击间隔', child: _buildIntervalSlider(config, state, theme)),
      _spacing,
      _inlineSection(title: '随机延迟', child: _buildRandomDelay(config, state, theme)),
      _spacing,
      _inlineSection(title: '重复模式', child: _buildRepeatModeSelector(config, state, theme)),
      _spacing,
      _inlineSection(title: '按住触发', child: _buildHoldTrigger(context, config, state, theme)),
    ];

    final pageContent = ScaffoldPage.scrollable(
      padding: const EdgeInsets.all(20),
      children: [
        if (isWide)
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: Column(children: modeSections)),
            const SizedBox(width: 16),
            Expanded(child: Column(children: settingsSections)),
          ])
        else
          ...modeSections,
        if (!isWide) ...settingsSections,
        if (state.isClickerRunning) ...[
          const SizedBox(height: 12),
          _buildStatusBar(state, theme),
        ],
        // Bottom padding for FAB
        const SizedBox(height: 70),
      ],
    );

    return Stack(children: [
      pageContent,
      // Floating action button
      Positioned(
        right: 24, bottom: 24,
        child: _buildFAB(state, theme),
      ),
    ]);
  }

  static const _spacing = SizedBox(height: 10);

  // ─── Section Card ─────────────────────────────────────────

  Widget _section({required String title, required IconData icon, required Widget child, String? subtitle}) {
    return Builder(builder: (context) {
      final isDark = FluentTheme.of(context).brightness == Brightness.dark;
      final accent = FluentTheme.of(context).accentColor;
      final subtitleColor = isDark ? const Color(0xFF9090B0) : const Color(0xFF8A8A9A);
      return Card(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, size: 14, color: accent),
            const SizedBox(width: 8),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              if (subtitle != null) Text(subtitle, style: TextStyle(fontSize: 10, color: subtitleColor)),
            ])),
          ]),
          const SizedBox(height: 10),
          child,
        ]),
      );
    });
  }

  // ─── Inline Section (no card border, compact) ─────────────

  Widget _inlineSection({required String title, required Widget child}) {
    return Builder(builder: (context) {
      final isDark = FluentTheme.of(context).brightness == Brightness.dark;
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF252540).withOpacity(0.5) : const Color(0xFFF0F0FA).withOpacity(0.5),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
            color: isDark ? const Color(0xFFC0C0E8) : const Color(0xFF5A5A80))),
          const SizedBox(height: 8),
          child,
        ]),
      );
    });
  }

  // ─── Selectable Chip (no checkmark) ───────────────────────

  Widget _selectChip(String label, bool selected, VoidCallback onTap, {IconData? icon}) {
    return Builder(builder: (context) {
      final isDark = FluentTheme.of(context).brightness == Brightness.dark;
      final accent = FluentTheme.of(context).accentColor;
      final unselectedBg = isDark ? const Color(0xFF303050) : const Color(0xFFE8E8F0);
      final unselectedBorder = isDark ? const Color(0xFF404060) : const Color(0xFFD0D0D8);
      final unselectedText = isDark ? const Color(0xFFC0C0D8) : const Color(0xFF5A5A70);
      final unselectedIcon = isDark ? const Color(0xFF9090B0) : const Color(0xFF8A8A9A);
      return MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: selected ? accent.withOpacity(0.15) : unselectedBg,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: selected ? accent : unselectedBorder),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (icon != null) ...[
                Icon(icon, size: 14, color: selected ? accent : unselectedIcon),
                const SizedBox(width: 6),
              ],
              Text(label, style: TextStyle(
                fontSize: 13, fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                color: selected ? accent : unselectedText,
              )),
            ]),
          ),
        ),
      );
    });
  }

  // ─── Mode Selector ────────────────────────────────────────

  Widget _buildModeSelector(BuildContext context, ClickerConfig config, AppState state, FluentThemeData theme) {
    return Row(children: [
      Expanded(child: _selectChip('鼠标', config.clickMode == ClickMode.mouse,
        () => state.setClickerConfig(config.copyWith(clickMode: ClickMode.mouse)), icon: FluentIcons.touch_pointer)),
      const SizedBox(width: 8),
      Expanded(child: _selectChip('键盘', config.clickMode == ClickMode.keyboard,
        () => state.setClickerConfig(config.copyWith(clickMode: ClickMode.keyboard)), icon: FluentIcons.keyboard_classic)),
    ]);
  }

  // ─── Key Action Mode ──────────────────────────────────────

  Widget _buildKeyActionSelector(ClickerConfig config, AppState state, FluentThemeData theme) {
    final modes = [
      (KeyActionMode.repeat, FluentIcons.repeat_all, '重复按键'),
      (KeyActionMode.hold, FluentIcons.back, '持续按住'),
      (KeyActionMode.sequence, FluentIcons.bulleted_list, '按键序列'),
      (KeyActionMode.combo, FluentIcons.merge, '组合键'),
      (KeyActionMode.text, FluentIcons.font, '自动打字'),
    ];
    return Wrap(spacing: 6, runSpacing: 6, children: modes.map((m) =>
      _selectChip(m.$3, config.keyActionMode == m.$1,
        () => state.setClickerConfig(config.copyWith(keyActionMode: m.$1)), icon: m.$2),
    ).toList());
  }

  // ─── Key Selector ─────────────────────────────────────────

  Widget _buildKeySelector(BuildContext context, ClickerConfig config, AppState state, FluentThemeData theme) {
    final accent = theme.accentColor;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Center(child: GestureDetector(
        onTap: () => _showKeyPicker(context, state, config),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
          decoration: BoxDecoration(
            color: accent.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: accent.withOpacity(0.4)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(config.keyToRepeat.toUpperCase(), style: TextStyle(
              color: accent, fontWeight: FontWeight.w700,
              fontFamily: 'monospace', fontSize: 22, letterSpacing: 2,
            )),
            const SizedBox(width: 10),
            Icon(FluentIcons.edit, size: 14, color: accent.withOpacity(0.6)),
          ]),
        ),
      )),
      const SizedBox(height: 12),
      const Text('常用按键', style: TextStyle(fontSize: 12)),
      const SizedBox(height: 6),
      Wrap(spacing: 4, runSpacing: 4, children: [
        'Space', 'Enter', 'Tab', 'Escape', 'Delete', 'Up', 'Down', 'Left', 'Right',
      ].map((key) => _selectChip(key, config.keyToRepeat.toLowerCase() == key.toLowerCase(),
        () => state.setClickerConfig(config.copyWith(keyToRepeat: key.toLowerCase())),
      )).toList()),
    ]);
  }

  void _showKeyPicker(BuildContext context, AppState state, ClickerConfig config) {
    showDialog(context: context, builder: (ctx) => _KeyPickerDialog(
      currentKey: config.keyToRepeat,
      onConfirm: (key) { state.setClickerConfig(config.copyWith(keyToRepeat: key)); Navigator.pop(ctx); },
    ));
  }

  // ─── Key Sequence Editor ──────────────────────────────────

  Widget _buildKeySequenceEditor(BuildContext context, ClickerConfig config, AppState state, FluentThemeData theme) {
    final seq = config.keySequence;
    final isDark = theme.brightness == Brightness.dark;
    final containerBg = isDark ? const Color(0xFF303050) : const Color(0xFFF0F0F8);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (seq.isNotEmpty) ...[
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: containerBg, borderRadius: BorderRadius.circular(8)),
          child: Wrap(spacing: 4, runSpacing: 4, children: [
            for (int i = 0; i < seq.length; i++) ...[
              _keyChip(seq[i].key, onDelete: () {
                final n = List<KeySequenceItem>.from(seq)..removeAt(i);
                state.setClickerConfig(config.copyWith(keySequence: n));
              }),
              if (i < seq.length - 1) const Icon(FluentIcons.forward, size: 12),
            ],
          ]),
        ),
        const SizedBox(height: 6),
        Row(children: [
          Text('共 ${seq.length} 个按键', style: TextStyle(fontSize: 12, color: theme.brightness == Brightness.dark ? const Color(0xFF9090B0) : const Color(0xFF8A8A9A))),
          const Spacer(),
          HyperlinkButton(onPressed: () => state.setClickerConfig(config.copyWith(keySequence: <KeySequenceItem>[])), child: const Text('清空')),
        ]),
      ] else
        const Padding(padding: EdgeInsets.all(16), child: Center(child: Text('点击下方按钮添加按键', style: TextStyle(fontSize: 12)))),
      const SizedBox(height: 8),
      SizedBox(width: double.infinity, child: Button(onPressed: () => _showSequenceKeyPicker(context, state, config), child: const Text('+ 添加按键'))),
      const SizedBox(height: 10),
      const Text('快速模板', style: TextStyle(fontSize: 12)),
      const SizedBox(height: 4),
      Wrap(spacing: 4, runSpacing: 4, children: [
        _seqTemplateChip('WASD移动', [const KeySequenceItem(key: 'w', delayMs: 100), const KeySequenceItem(key: 'a', delayMs: 100), const KeySequenceItem(key: 's', delayMs: 100), const KeySequenceItem(key: 'd', delayMs: 100)], config, state),
        _seqTemplateChip('连招123', [const KeySequenceItem(key: '1', delayMs: 200), const KeySequenceItem(key: '2', delayMs: 200), const KeySequenceItem(key: '3', delayMs: 200)], config, state),
        _seqTemplateChip('方向循环', [const KeySequenceItem(key: 'up', delayMs: 150), const KeySequenceItem(key: 'right', delayMs: 150), const KeySequenceItem(key: 'down', delayMs: 150), const KeySequenceItem(key: 'left', delayMs: 150)], config, state),
      ]),
    ]);
  }

  Widget _keyChip(String key, {VoidCallback? onDelete}) {
    return Builder(builder: (context) {
      final accent = FluentTheme.of(context).accentColor;
      return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: accent.withOpacity(0.1), borderRadius: BorderRadius.circular(4), border: Border.all(color: accent.withOpacity(0.3))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(key.toUpperCase(), style: TextStyle(color: accent, fontWeight: FontWeight.w600, fontFamily: 'monospace', fontSize: 12)),
        if (onDelete != null) ...[
          const SizedBox(width: 4),
          IconButton(icon: const Icon(FluentIcons.clear, size: 10), onPressed: onDelete),
        ],
      ]),
    );
    });
  }

  Widget _seqTemplateChip(String label, List<KeySequenceItem> items, ClickerConfig config, AppState state) {
    return _selectChip(label, false, () => state.setClickerConfig(config.copyWith(keySequence: items)));
  }

  void _showSequenceKeyPicker(BuildContext context, AppState state, ClickerConfig config) {
    showDialog(context: context, builder: (ctx) => _SequenceKeyPickerDialog(onConfirm: (key, delayMs) {
      final n = List<KeySequenceItem>.from(config.keySequence)..add(KeySequenceItem(key: key, delayMs: delayMs));
      state.setClickerConfig(config.copyWith(keySequence: n));
      Navigator.pop(ctx);
    }));
  }

  // ─── Combo Key Editor ─────────────────────────────────────

  Widget _buildComboKeyEditor(BuildContext context, ClickerConfig config, AppState state, FluentThemeData theme) {
    final combo = config.comboKeys;
    final isDark = theme.brightness == Brightness.dark;
    final containerBg = isDark ? const Color(0xFF303050) : const Color(0xFFF0F0F8);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: containerBg, borderRadius: BorderRadius.circular(8)),
        child: combo.isEmpty
          ? const Center(child: Text('点击下方按钮添加组合键', style: TextStyle(fontSize: 12)))
          : Wrap(spacing: 4, runSpacing: 4, children: [
              for (int i = 0; i < combo.length; i++) ...[
                _keyChip(combo[i], onDelete: () {
                  final n = List<String>.from(combo)..removeAt(i);
                  state.setClickerConfig(config.copyWith(comboKeys: n));
                }),
                if (i < combo.length - 1) Text('+', style: TextStyle(fontWeight: FontWeight.bold, color: FluentTheme.of(context).accentColor)),
              ],
            ]),
      ),
      const SizedBox(height: 8),
      const Text('常用组合', style: TextStyle(fontSize: 12)),
      const SizedBox(height: 4),
      Wrap(spacing: 4, runSpacing: 4, children: [
        _comboTemplateChip('Ctrl+C', ['ctrl', 'c'], config, state),
        _comboTemplateChip('Ctrl+V', ['ctrl', 'v'], config, state),
        _comboTemplateChip('Ctrl+Z', ['ctrl', 'z'], config, state),
        _comboTemplateChip('Ctrl+S', ['ctrl', 's'], config, state),
        _comboTemplateChip('Ctrl+A', ['ctrl', 'a'], config, state),
        _comboTemplateChip('Alt+F4', ['alt', 'f4'], config, state),
        _comboTemplateChip('Alt+Tab', ['alt', 'tab'], config, state),
        _comboTemplateChip('Ctrl+Shift+Esc', ['ctrl', 'shift', 'escape'], config, state),
      ]),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(child: Button(onPressed: () => _showComboKeyPicker(context, state, config, isModifier: true), child: const Text('+ 修饰键'))),
        const SizedBox(width: 8),
        Expanded(child: Button(onPressed: () => _showComboKeyPicker(context, state, config, isModifier: false), child: const Text('+ 普通键'))),
      ]),
    ]);
  }

  Widget _comboTemplateChip(String label, List<String> combo, ClickerConfig config, AppState state) {
    return _selectChip(label, false, () => state.setClickerConfig(config.copyWith(comboKeys: combo)));
  }

  void _showComboKeyPicker(BuildContext context, AppState state, ClickerConfig config, {required bool isModifier}) {
    showDialog(context: context, builder: (ctx) => _ComboKeyPickerDialog(isModifier: isModifier, onConfirm: (key) {
      final n = List<String>.from(config.comboKeys)..add(key);
      state.setClickerConfig(config.copyWith(comboKeys: n));
      Navigator.pop(ctx);
    }));
  }

  // ─── Text Type Editor ─────────────────────────────────────

  Widget _buildTextTypeEditor(BuildContext context, ClickerConfig config, AppState state, FluentThemeData theme) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      TextBox(maxLines: 4, placeholder: '在此输入文本内容...', controller: TextEditingController(text: config.textToType),
        onChanged: (v) => state.setClickerConfig(config.copyWith(textToType: v))),
      const SizedBox(height: 10),
      Row(children: [
        const Text('打字速度:', style: TextStyle(fontSize: 13)),
        const SizedBox(width: 8),
        Text('${config.textTypeDelayMs}ms/字', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        Expanded(child: Slider(value: config.textTypeDelayMs.toDouble(), min: 10, max: 500, divisions: 49,
          label: '${config.textTypeDelayMs}ms',
          onChanged: (v) => state.setClickerConfig(config.copyWith(textTypeDelayMs: v.round())))),
      ]),
      const SizedBox(height: 6),
      const Text('快速填充', style: TextStyle(fontSize: 12)),
      const SizedBox(height: 4),
      Wrap(spacing: 4, runSpacing: 4, children: [
        _textTemplateChip('Hello World', 'Hello World!', config, state),
        _textTemplateChip('测试文本', '这是一段测试文本。', config, state),
        _textTemplateChip('数字序列', '1 2 3 4 5 6 7 8 9 10', config, state),
      ]),
    ]);
  }

  Widget _textTemplateChip(String label, String text, ClickerConfig config, AppState state) {
    return _selectChip(label, false, () => state.setClickerConfig(config.copyWith(textToType: text)));
  }

  // ─── Jitter Settings ──────────────────────────────────────

  Widget _buildJitterSettings(ClickerConfig config, AppState state, FluentThemeData theme) {
    return Column(children: [
      Row(children: [
        const Expanded(child: Text('启用按键抖动', style: TextStyle(fontSize: 13))),
        ToggleSwitch(checked: config.jitterEnabled, onChanged: (v) => state.setClickerConfig(config.copyWith(jitterEnabled: v))),
      ]),
      if (config.jitterEnabled) ...[
        const SizedBox(height: 10),
        Row(children: [
          const Text('范围:', style: TextStyle(fontSize: 12)),
          const SizedBox(width: 8),
          SizedBox(width: 70, child: TextBox(
            controller: TextEditingController(text: config.jitterMinMs.toString()),
            onChanged: (v) { final p = int.tryParse(v); if (p != null && p >= 0) state.setClickerConfig(config.copyWith(jitterMinMs: p)); },
          )),
          const SizedBox(width: 6), const Text('~', style: TextStyle(fontSize: 13)), const SizedBox(width: 6),
          SizedBox(width: 70, child: TextBox(
            controller: TextEditingController(text: config.jitterMaxMs.toString()),
            onChanged: (v) { final p = int.tryParse(v); if (p != null && p >= 0) state.setClickerConfig(config.copyWith(jitterMaxMs: p)); },
          )),
          const Text(' ms', style: TextStyle(fontSize: 12)),
        ]),
      ],
    ]);
  }

  // ─── Random Offset ────────────────────────────────────────

  Widget _buildRandomOffset(ClickerConfig config, AppState state, FluentThemeData theme) {
    return Column(children: [
      Row(children: [
        const Expanded(child: Text('启用随机偏移', style: TextStyle(fontSize: 13))),
        ToggleSwitch(checked: config.randomOffsetEnabled, onChanged: (v) => state.setClickerConfig(config.copyWith(randomOffsetEnabled: v))),
      ]),
      if (config.randomOffsetEnabled) ...[
        const SizedBox(height: 10),
        Row(children: [
          const Text('范围:', style: TextStyle(fontSize: 12)),
          const SizedBox(width: 8),
          SizedBox(width: 70, child: TextBox(
            controller: TextEditingController(text: config.randomOffsetMinPx.toString()),
            onChanged: (v) { final p = int.tryParse(v); if (p != null && p >= 0) state.setClickerConfig(config.copyWith(randomOffsetMinPx: p)); },
          )),
          const SizedBox(width: 6), const Text('~', style: TextStyle(fontSize: 13)), const SizedBox(width: 6),
          SizedBox(width: 70, child: TextBox(
            controller: TextEditingController(text: config.randomOffsetMaxPx.toString()),
            onChanged: (v) { final p = int.tryParse(v); if (p != null && p >= 0) state.setClickerConfig(config.copyWith(randomOffsetMaxPx: p)); },
          )),
          const Text(' px', style: TextStyle(fontSize: 12)),
        ]),
        const SizedBox(height: 8),
        Slider(value: config.randomOffsetMaxPx.toDouble(), min: 1, max: 50, divisions: 49,
          label: '${config.randomOffsetMaxPx}px',
          onChanged: (v) => state.setClickerConfig(config.copyWith(randomOffsetMaxPx: v.round()))),
      ],
    ]);
  }

  // ─── Click Type ───────────────────────────────────────────

  Widget _buildClickTypeSelector(ClickerConfig config, AppState state, FluentThemeData theme) {
    return Row(children: [
      Expanded(child: _selectChip('单击', config.clickType == ClickType.single,
        () => state.setClickerConfig(config.copyWith(clickType: ClickType.single)))),
      const SizedBox(width: 8),
      Expanded(child: _selectChip('双击', config.clickType == ClickType.double,
        () => state.setClickerConfig(config.copyWith(clickType: ClickType.double)))),
    ]);
  }

  // ─── Mouse Button ─────────────────────────────────────────

  Widget _buildMouseButtonSelector(ClickerConfig config, AppState state, FluentThemeData theme) {
    final labels = {MouseButton.left: '左键', MouseButton.right: '右键', MouseButton.middle: '中键'};
    return Wrap(spacing: 6, children: MouseButton.values.map((btn) =>
      _selectChip(labels[btn]!, config.mouseButton == btn,
        () => state.setClickerConfig(config.copyWith(mouseButton: btn))),
    ).toList());
  }

  // ─── Position ─────────────────────────────────────────────

  Widget _buildPositionSelector(BuildContext context, ClickerConfig config, AppState state, FluentThemeData theme) {
    final isFixed = config.positionMode == PositionMode.fixed;
    return Column(children: [
      Row(children: [
        Expanded(child: _selectChip('跟随鼠标', !isFixed,
          () => state.setClickerConfig(config.copyWith(positionMode: PositionMode.current)))),
        const SizedBox(width: 8),
        Expanded(child: _selectChip('固定位置', isFixed,
          () => state.setClickerConfig(config.copyWith(positionMode: PositionMode.fixed)))),
      ]),
      if (isFixed) ...[
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: Row(children: [
            const Text('X:', style: TextStyle(fontSize: 13)),
            const SizedBox(width: 6),
            SizedBox(width: 70, child: TextBox(controller: TextEditingController(text: config.fixedX.toString()),
              onChanged: (v) { final p = int.tryParse(v); if (p != null) state.setClickerConfig(config.copyWith(fixedX: p)); })),
          ])),
          const SizedBox(width: 12),
          Expanded(child: Row(children: [
            const Text('Y:', style: TextStyle(fontSize: 13)),
            const SizedBox(width: 6),
            SizedBox(width: 70, child: TextBox(controller: TextEditingController(text: config.fixedY.toString()),
              onChanged: (v) { final p = int.tryParse(v); if (p != null) state.setClickerConfig(config.copyWith(fixedY: p)); })),
          ])),
          const SizedBox(width: 8),
          Button(onPressed: () => _pickPosition(context, state), child: const Text('选取')),
        ]),
      ],
    ]);
  }

  Future<void> _pickPosition(BuildContext context, AppState state) async {
    final config = state.clickerConfig;
    final wasAlwaysOnTop = await windowManager.isAlwaysOnTop();
    await windowManager.setAlwaysOnTop(true);
    await windowManager.setFullScreen(true);
    await Future.delayed(const Duration(milliseconds: 100));

    final result = await showGeneralDialog<({int x, int y})>(
      context: context, barrierDismissible: true, barrierLabel: '选取位置',
      barrierColor: Colors.transparent, transitionDuration: const Duration(milliseconds: 150),
      pageBuilder: (ctx, a1, a2) => PositionPickerOverlay(initialX: config.fixedX, initialY: config.fixedY),
    );

    await windowManager.setFullScreen(false);
    if (!wasAlwaysOnTop) await windowManager.setAlwaysOnTop(false);
    if (result != null) state.setClickerConfig(state.clickerConfig.copyWith(fixedX: result.x, fixedY: result.y));
  }

  // ─── Interval ─────────────────────────────────────────────

  Widget _buildIntervalSlider(ClickerConfig config, AppState state, FluentThemeData theme) {
    final ms = config.intervalMs;
    String label;
    if (ms >= 1000) {
      label = '${(ms / 1000).toStringAsFixed(1)}s';
    } else if (ms != ms.roundToDouble()) {
      label = '${ms.toStringAsFixed(2)}ms';
    } else {
      label = '${ms.toInt()}ms';
    }
    return Column(children: [
      Row(children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
        const SizedBox(width: 12),
        ...<double>[10, 50, 100, 500, 1000].map((v) => Padding(padding: const EdgeInsets.only(left: 4),
          child: _selectChip(
            v >= 1000 ? '${(v / 1000).toStringAsFixed(0)}s' : '${v.toInt()}ms',
            (ms - v).abs() < 0.005,
            () => state.setClickerConfig(config.copyWith(intervalMs: v))))),
      ]),
      const SizedBox(height: 4),
      Row(children: [
        Expanded(child: Slider(
          value: ms.clamp(10, 300000),
          min: 10, max: 300000,
          onChanged: (v) => state.setClickerConfig(config.copyWith(intervalMs: v.roundToDouble())),
        )),
      ]),
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text('10ms', style: TextStyle(fontSize: 11, color: theme.brightness == Brightness.dark ? const Color(0xFF707090) : const Color(0xFF9A9AAA))),
        Text('5min', style: TextStyle(fontSize: 11, color: theme.brightness == Brightness.dark ? const Color(0xFF707090) : const Color(0xFF9A9AAA))),
      ]),
      const SizedBox(height: 6),
      SizedBox(width: 140, child: TextBox(
        placeholder: '自定义(ms)',
        textAlign: TextAlign.center,
        controller: TextEditingController(text: ms == ms.roundToDouble() ? ms.toInt().toString() : ms.toStringAsFixed(2)),
        onChanged: (v) { final p = double.tryParse(v); if (p != null && p >= 10) state.setClickerConfig(config.copyWith(intervalMs: p)); },
      )),
    ]);
  }

  // ─── Random Delay ─────────────────────────────────────────

  Widget _buildRandomDelay(ClickerConfig config, AppState state, FluentThemeData theme) {
    final enabled = config.randomDelayMinMs > 0 || config.randomDelayMaxMs > 0;
    return Column(children: [
      Row(children: [
        const Expanded(child: Text('启用随机延迟', style: TextStyle(fontSize: 13))),
        ToggleSwitch(checked: enabled, onChanged: (v) {
          state.setClickerConfig(config.copyWith(randomDelayMinMs: v ? 10 : 0, randomDelayMaxMs: v ? 50 : 0));
        }),
      ]),
      if (enabled) ...[
        const SizedBox(height: 10),
        Row(children: [
          const Text('最小:', style: TextStyle(fontSize: 12)),
          const SizedBox(width: 6),
          SizedBox(width: 70, child: TextBox(
            controller: TextEditingController(text: config.randomDelayMinMs.toString()),
            onChanged: (v) { final p = int.tryParse(v); if (p != null && p >= 0) state.setClickerConfig(config.copyWith(randomDelayMinMs: p)); },
          )),
          const SizedBox(width: 12),
          const Text('最大:', style: TextStyle(fontSize: 12)),
          const SizedBox(width: 6),
          SizedBox(width: 70, child: TextBox(
            controller: TextEditingController(text: config.randomDelayMaxMs.toString()),
            onChanged: (v) { final p = int.tryParse(v); if (p != null && p >= 0) state.setClickerConfig(config.copyWith(randomDelayMaxMs: p)); },
          )),
          const Text(' ms', style: TextStyle(fontSize: 12)),
        ]),
      ],
    ]);
  }

  // ─── Repeat Mode ──────────────────────────────────────────

  Widget _buildRepeatModeSelector(ClickerConfig config, AppState state, FluentThemeData theme) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(spacing: 6, children: [
        _selectChip('无限重复', config.repeatMode == ClickRepeatMode.infinite, () => state.setClickerConfig(config.copyWith(repeatMode: ClickRepeatMode.infinite))),
        _selectChip('指定次数', config.repeatMode == ClickRepeatMode.count, () => state.setClickerConfig(config.copyWith(repeatMode: ClickRepeatMode.count))),
        _selectChip('定时关闭', config.repeatMode == ClickRepeatMode.duration, () => state.setClickerConfig(config.copyWith(repeatMode: ClickRepeatMode.duration))),
      ]),
      const SizedBox(height: 10),
      if (config.repeatMode == ClickRepeatMode.count)
        Row(children: [
          const Text('次数:', style: TextStyle(fontSize: 13)),
          const SizedBox(width: 8),
          SizedBox(width: 100, child: TextBox(
            controller: TextEditingController(text: config.repeatCount.toString()),
            onChanged: (v) { final p = int.tryParse(v); if (p != null && p > 0) state.setClickerConfig(config.copyWith(repeatCount: p)); },
          )),
        ])
      else if (config.repeatMode == ClickRepeatMode.duration)
        Row(children: [
          const Text('时长:', style: TextStyle(fontSize: 13)),
          const SizedBox(width: 8),
          SizedBox(width: 100, child: TextBox(
            controller: TextEditingController(text: config.durationSeconds.toString()),
            onChanged: (v) { final p = int.tryParse(v); if (p != null && p > 0) state.setClickerConfig(config.copyWith(durationSeconds: p)); },
          )),
          const Text(' 秒', style: TextStyle(fontSize: 12)),
        ]),
    ]);
  }

  // ─── Hold Trigger ─────────────────────────────────────────

  Widget _buildHoldTrigger(BuildContext context, ClickerConfig config, AppState state, FluentThemeData theme) {
    final hotkeyConfig = state.hotkeyConfig;
    return Column(children: [
      Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('启用按住触发', style: TextStyle(fontSize: 13)),
          Text('按住 ${hotkeyConfig.holdTrigger} 时自动连点', style: TextStyle(fontSize: 11, color: theme.brightness == Brightness.dark ? const Color(0xFF9090B0) : const Color(0xFF8A8A9A))),
        ])),
        ToggleSwitch(checked: config.holdTriggerEnabled, onChanged: (v) => state.setClickerConfig(config.copyWith(holdTriggerEnabled: v))),
      ]),
      if (config.holdTriggerEnabled) ...[
        const SizedBox(height: 10),
        Row(children: [
          const Text('触发键:', style: TextStyle(fontSize: 13)),
          const SizedBox(width: 8),
          _buildHotkeySelector(context, currentKey: hotkeyConfig.holdTrigger, onChanged: (k) => state.setHotkeyConfig(hotkeyConfig.copyWith(holdTrigger: k))),
        ]),
      ],
    ]);
  }

  Widget _buildHotkeySelector(BuildContext context, {required String currentKey, required void Function(String) onChanged}) {
    final parsed = HotkeyConfig.splitHotkey(currentKey);
    final selectedMods = parsed.mods;
    final selectedKey = parsed.key;
    return Wrap(spacing: 4, runSpacing: 4, children: [
      for (final mod in HotkeyConfig.modifiers)
        _selectChip(mod, selectedMods.contains(mod), () {
          final n = List<String>.from(selectedMods);
          if (selectedMods.contains(mod)) {
            n.remove(mod);
          } else {
            n.add(mod);
          }
          onChanged(HotkeyConfig.buildHotkey(n, selectedKey));
        }),
      const SizedBox(width: 4),
      ComboBox<String>(value: HotkeyConfig.keys.contains(selectedKey) ? selectedKey : null, items: HotkeyConfig.keys.map((k) => ComboBoxItem(value: k, child: Text(k, style: const TextStyle(fontSize: 12)))).toList(),
        onChanged: (v) { if (v != null) onChanged(HotkeyConfig.buildHotkey(selectedMods, v)); },
        isExpanded: false,
      ),
    ]);
  }

  // ─── Floating Action Button ───────────────────────────────

  Widget _buildFAB(AppState state, FluentThemeData theme) {
    final isRunning = state.isClickerRunning;
    final canStart = state.clickerConfig.autoClickEnabled;
    final hotkey = state.hotkeyConfig.startStopClicker;
    final isDark = theme.brightness == Brightness.dark;
    final accent = theme.accentColor;
    final fabColor = !canStart ? (isDark ? const Color(0xFF404060) : const Color(0xFFD0D0D8)) : (isRunning ? Colors.red : accent);
    return MouseRegion(
      cursor: canStart ? SystemMouseCursors.click : SystemMouseCursors.forbidden,
      child: GestureDetector(
        onTap: canStart ? state.toggleClicker : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          decoration: BoxDecoration(
            color: fabColor,
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: fabColor.withOpacity(0.4),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
              BoxShadow(
                color: (isDark ? const Color(0xFF1A1A2E) : const Color(0xFFF5F5FA)).withOpacity(0.3),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(!canStart ? FluentIcons.blocked : (isRunning ? FluentIcons.stop : FluentIcons.play), size: 18, color: Colors.white),
            const SizedBox(width: 10),
            Text(!canStart ? '已禁用' : (isRunning ? '停止 ($hotkey)' : '开始 ($hotkey)'),
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white)),
          ]),
        ),
      ),
    );
  }

  // ─── Status Bar ───────────────────────────────────────────

  Widget _buildStatusBar(AppState state, FluentThemeData theme) {
    final isKeyboard = state.clickerConfig.clickMode == ClickMode.keyboard;
    final showStats = state.clickerConfig.statsEnabled;
    final cps = state.clickService.averageCps;
    final elapsed = state.clickService.elapsedDuration;
    final elapsedStr = elapsed != null
        ? (elapsed.inHours > 0 ? '${elapsed.inHours}h ${elapsed.inMinutes % 60}m' : (elapsed.inMinutes > 0 ? '${elapsed.inMinutes}m ${elapsed.inSeconds % 60}s' : '${elapsed.inSeconds}s'))
        : '';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: const Color(0xFF00E676).withOpacity(0.08), borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF00E676).withOpacity(0.3))),
      child: Row(children: [
        const Icon(FluentIcons.circle_fill, size: 8, color: Color(0xFF00E676)),
        const SizedBox(width: 8),
        Text('运行中 · ${isKeyboard ? "已按键" : "已点击"} ${state.clickCount} 次', style: const TextStyle(color: Color(0xFF00E676), fontSize: 13)),
        if (showStats) ...[
          const SizedBox(width: 12),
          Text('${cps.toStringAsFixed(1)} CPS', style: TextStyle(color: const Color(0xFF00E676).withOpacity(0.8), fontSize: 12)),
          const SizedBox(width: 8),
          Text(elapsedStr, style: TextStyle(color: const Color(0xFF00E676).withOpacity(0.7), fontSize: 12)),
        ],
        const Spacer(),
        Text('${state.clickerConfig.intervalMs}ms/次', style: TextStyle(color: const Color(0xFF00E676).withOpacity(0.7), fontSize: 12)),
      ]),
    );
  }
}

// ─── Key Picker Dialog ───────────────────────────────────────

class _KeyPickerDialog extends StatefulWidget {
  final String currentKey;
  final ValueChanged<String> onConfirm;
  const _KeyPickerDialog({required this.currentKey, required this.onConfirm});
  @override
  State<_KeyPickerDialog> createState() => _KeyPickerDialogState();
}

class _KeyPickerDialogState extends State<_KeyPickerDialog> {
  late String _selectedKey;
  static const _categories = <(String, List<String>)>[
    ('功能键', ['F1','F2','F3','F4','F5','F6','F7','F8','F9','F10','F11','F12']),
    ('编辑键', ['Space','Enter','Tab','Escape','Backspace','Delete','Insert']),
    ('方向键', ['Up','Down','Left','Right','Home','End','PageUp','PageDown']),
    ('数字', ['0','1','2','3','4','5','6','7','8','9']),
    ('字母', ['A','B','C','D','E','F','G','H','I','J','K','L','M','N','O','P','Q','R','S','T','U','V','W','X','Y','Z']),
  ];

  @override
  void initState() { super.initState(); _selectedKey = widget.currentKey; }

  @override
  Widget build(BuildContext context) {
    final isDark = FluentTheme.of(context).brightness == Brightness.dark;
    final accent = FluentTheme.of(context).accentColor;
    final unselectedBg = isDark ? const Color(0xFF303050) : const Color(0xFFE8E8F0);
    final unselectedBorder = isDark ? const Color(0xFF404060) : const Color(0xFFD0D0D8);
    final unselectedText = isDark ? const Color(0xFFC0C0D8) : const Color(0xFF5A5A70);
    return ContentDialog(
      title: const Text('选择按键'),
      content: SizedBox(width: 400, child: Column(mainAxisSize: MainAxisSize.min, children: [
        Center(child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          decoration: BoxDecoration(color: accent.withOpacity(0.1), borderRadius: BorderRadius.circular(8), border: Border.all(color: accent.withOpacity(0.4))),
          child: Text(_selectedKey.toUpperCase(), style: TextStyle(color: accent, fontWeight: FontWeight.w700, fontFamily: 'monospace', fontSize: 18)),
        )),
        const SizedBox(height: 12),
        ..._categories.map((cat) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(cat.$1, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
          const SizedBox(height: 4),
          Wrap(spacing: 3, runSpacing: 3, children: cat.$2.map((key) {
            final sel = _selectedKey.toLowerCase() == key.toLowerCase();
            return GestureDetector(onTap: () => setState(() => _selectedKey = key.toLowerCase()),
              child: Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: sel ? accent.withOpacity(0.2) : unselectedBg,
                  borderRadius: BorderRadius.circular(4), border: Border.all(color: sel ? accent : unselectedBorder)),
                child: Text(key, style: TextStyle(fontSize: 11, color: sel ? accent : unselectedText, fontWeight: sel ? FontWeight.w600 : FontWeight.normal)),
              ),
            );
          }).toList()),
          const SizedBox(height: 8),
        ])),
      ])),
      actions: [FilledButton(onPressed: () => widget.onConfirm(_selectedKey), child: const Text('确认'))],
    );
  }
}

// ─── Sequence Key Picker Dialog ──────────────────────────────

class _SequenceKeyPickerDialog extends StatefulWidget {
  final void Function(String key, int delayMs) onConfirm;
  const _SequenceKeyPickerDialog({required this.onConfirm});
  @override
  State<_SequenceKeyPickerDialog> createState() => _SequenceKeyPickerDialogState();
}

class _SequenceKeyPickerDialogState extends State<_SequenceKeyPickerDialog> {
  String _selectedKey = 'space';
  int _delayMs = 50;

  static const _categories = <(String, List<String>)>[
    ('功能键', ['F1','F2','F3','F4','F5','F6','F7','F8','F9','F10','F11','F12']),
    ('编辑键', ['Space','Enter','Tab','Escape','Backspace','Delete','Insert']),
    ('方向键', ['Up','Down','Left','Right','Home','End','PageUp','PageDown']),
    ('数字', ['0','1','2','3','4','5','6','7','8','9']),
    ('字母', ['A','B','C','D','E','F','G','H','I','J','K','L','M','N','O','P','Q','R','S','T','U','V','W','X','Y','Z']),
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = FluentTheme.of(context).brightness == Brightness.dark;
    final accent = FluentTheme.of(context).accentColor;
    final unselectedBg = isDark ? const Color(0xFF303050) : const Color(0xFFE8E8F0);
    final unselectedBorder = isDark ? const Color(0xFF404060) : const Color(0xFFD0D0D8);
    final unselectedText = isDark ? const Color(0xFFC0C0D8) : const Color(0xFF5A5A70);
    return ContentDialog(
      title: const Text('添加按键'),
      content: SizedBox(width: 400, child: Column(mainAxisSize: MainAxisSize.min, children: [
        Center(child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          decoration: BoxDecoration(color: accent.withOpacity(0.1), borderRadius: BorderRadius.circular(8), border: Border.all(color: accent.withOpacity(0.4))),
          child: Text(_selectedKey.toUpperCase(), style: TextStyle(color: accent, fontWeight: FontWeight.w700, fontFamily: 'monospace', fontSize: 18)),
        )),
        const SizedBox(height: 10),
        Row(children: [
          const Text('延迟:', style: TextStyle(fontSize: 12)),
          const SizedBox(width: 6),
          Text('${_delayMs}ms', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
          Expanded(child: Slider(value: _delayMs.toDouble(), min: 0, max: 1000, divisions: 50, onChanged: (v) => setState(() => _delayMs = v.round()))),
        ]),
        const SizedBox(height: 8),
        ..._categories.map((cat) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(cat.$1, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
          const SizedBox(height: 4),
          Wrap(spacing: 3, runSpacing: 3, children: cat.$2.map((key) {
            final sel = _selectedKey.toLowerCase() == key.toLowerCase();
            return GestureDetector(onTap: () => setState(() => _selectedKey = key.toLowerCase()),
              child: Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: sel ? accent.withOpacity(0.2) : unselectedBg,
                  borderRadius: BorderRadius.circular(4), border: Border.all(color: sel ? accent : unselectedBorder)),
                child: Text(key, style: TextStyle(fontSize: 11, color: sel ? accent : unselectedText, fontWeight: sel ? FontWeight.w600 : FontWeight.normal)),
              ),
            );
          }).toList()),
          const SizedBox(height: 6),
        ])),
      ])),
      actions: [FilledButton(onPressed: () => widget.onConfirm(_selectedKey, _delayMs), child: const Text('确认'))],
    );
  }
}

// ─── Combo Key Picker Dialog ─────────────────────────────────

class _ComboKeyPickerDialog extends StatefulWidget {
  final bool isModifier;
  final ValueChanged<String> onConfirm;
  const _ComboKeyPickerDialog({required this.isModifier, required this.onConfirm});
  @override
  State<_ComboKeyPickerDialog> createState() => _ComboKeyPickerDialogState();
}

class _ComboKeyPickerDialogState extends State<_ComboKeyPickerDialog> {
  String _selectedKey = '';

  static const _modifierKeys = ['Ctrl', 'Alt', 'Shift'];
  static const _regularCategories = <(String, List<String>)>[
    ('功能键', ['F1','F2','F3','F4','F5','F6','F7','F8','F9','F10','F11','F12']),
    ('编辑键', ['Space','Enter','Tab','Escape','Backspace','Delete','Insert']),
    ('方向键', ['Up','Down','Left','Right','Home','End','PageUp','PageDown']),
    ('数字', ['0','1','2','3','4','5','6','7','8','9']),
    ('字母', ['A','B','C','D','E','F','G','H','I','J','K','L','M','N','O','P','Q','R','S','T','U','V','W','X','Y','Z']),
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = FluentTheme.of(context).brightness == Brightness.dark;
    final accent = FluentTheme.of(context).accentColor;
    final unselectedBg = isDark ? const Color(0xFF303050) : const Color(0xFFE8E8F0);
    final unselectedBorder = isDark ? const Color(0xFF404060) : const Color(0xFFD0D0D8);
    final unselectedText = isDark ? const Color(0xFFC0C0D8) : const Color(0xFF5A5A70);
    final keys = widget.isModifier ? _modifierKeys : null;
    return ContentDialog(
      title: Text(widget.isModifier ? '选择修饰键' : '选择普通键'),
      content: SizedBox(width: 400, child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (keys != null)
          Wrap(spacing: 6, runSpacing: 6, children: keys.map((key) {
            final sel = _selectedKey.toLowerCase() == key.toLowerCase();
            return GestureDetector(onTap: () => setState(() => _selectedKey = key.toLowerCase()),
              child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(color: sel ? accent.withOpacity(0.2) : unselectedBg,
                  borderRadius: BorderRadius.circular(4), border: Border.all(color: sel ? accent : unselectedBorder)),
                child: Text(key, style: TextStyle(fontSize: 12, color: sel ? accent : unselectedText, fontWeight: sel ? FontWeight.w600 : FontWeight.normal)),
              ),
            );
          }).toList())
        else
          ..._regularCategories.map((cat) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(cat.$1, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
            const SizedBox(height: 4),
            Wrap(spacing: 3, runSpacing: 3, children: cat.$2.map((key) {
              final sel = _selectedKey.toLowerCase() == key.toLowerCase();
              return GestureDetector(onTap: () => setState(() => _selectedKey = key.toLowerCase()),
                child: Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: sel ? accent.withOpacity(0.2) : unselectedBg,
                    borderRadius: BorderRadius.circular(4), border: Border.all(color: sel ? accent : unselectedBorder)),
                  child: Text(key, style: TextStyle(fontSize: 11, color: sel ? accent : unselectedText, fontWeight: sel ? FontWeight.w600 : FontWeight.normal)),
                ),
              );
            }).toList()),
            const SizedBox(height: 6),
          ])),
      ])),
      actions: [FilledButton(onPressed: _selectedKey.isEmpty ? null : () => widget.onConfirm(_selectedKey), child: const Text('确认'))],
    );
  }
}
