/// Auto-clicker page — Fluent UI design.
library;

import 'package:fluent_ui/fluent_ui.dart';
import '../../widgets/debounced_text_box.dart';
import 'package:provider/provider.dart';
import '../../services/app_state.dart';
import '../../services/screen_overlay_service.dart';
import '../../models/clicker_config.dart';
import '../../models/hotkey_config.dart';

class ClickerPage extends StatefulWidget {
  const ClickerPage({super.key});

  @override
  State<ClickerPage> createState() => _ClickerPageState();
}

/// 点击间隔滑块的显示单位
enum _IntervalUnit { ms, s, min }

class _ClickerPageState extends State<ClickerPage> {
  /// 点击间隔滑块的显示单位（值始终以毫秒存储，仅滑块刻度/分档变化）
  _IntervalUnit _intervalUnit = _IntervalUnit.ms;
  final _textTypeController = TextEditingController();

  @override
  void dispose() {
    _textTypeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final theme = FluentTheme.of(context);
    final config = state.clickerConfig;
    final isKeyboard = config.clickMode == ClickMode.keyboard;
    final isWide = MediaQuery.of(context).size.width >= 700;

    // Sync controller text with config (only when different to avoid cursor reset)
    if (_textTypeController.text != config.textToType) {
      final sel = _textTypeController.selection;
      _textTypeController.text = config.textToType;
      if (sel.start >= 0 && sel.end <= config.textToType.length) {
        _textTypeController.selection = sel;
      }
    }

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
      ]);
    } else {
      modeSections.addAll([
        _spacing, _section(title: '操作类型', icon: FluentIcons.touch, child: _buildMouseActionSelector(config, state, theme)),
        if (config.clickType == ClickType.single || config.clickType == ClickType.double) ...[
          _spacing, _section(title: '鼠标按键', icon: FluentIcons.touch_pointer, child: _buildMouseButtonSelector(config, state, theme)),
          _spacing, _section(title: '点击位置', icon: FluentIcons.map_pin, child: _buildPositionSelector(context, config, state, theme)),
        ],
        if (config.clickType == ClickType.drag) ...[
          _spacing, _section(title: '拖拽路径', icon: FluentIcons.move, child: _buildMouseDragPathSelector(context, config, state, theme)),
        ],
        if (config.clickType == ClickType.swipe) ...[
          _spacing, _section(title: '扫过路径', icon: FluentIcons.forward, child: _buildMouseSwipePathSelector(context, config, state, theme)),
        ],
        if (config.clickType == ClickType.sequence) ...[
          _spacing, _section(title: '动作序列', icon: FluentIcons.bulleted_list, child: _buildMouseSequenceEditor(context, config, state, theme)),
          _spacing, _section(title: '点击位置', icon: FluentIcons.map_pin, child: _buildPositionSelector(context, config, state, theme)),
        ],
      ]);
    }

    final settingsSections = <Widget>[
      _inlineSection(title: isKeyboard ? '按键间隔' : '点击间隔', child: _buildIntervalSlider(config, state, theme)),
      _spacing,
      _section(title: '重复模式', icon: FluentIcons.refresh, child: _buildRepeatModeSelector(config, state, theme)),
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

  Widget _section({required String title, required IconData icon, required Widget child}) {
    return Builder(builder: (context) {
      final isDark = FluentTheme.of(context).brightness == Brightness.dark;
      final accent = FluentTheme.of(context).accentColor;
      return Card(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, size: 14, color: accent),
            const SizedBox(width: 8),
            Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
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
          color: isDark ? const Color(0xFF252540).withValues(alpha: 0.5) : const Color(0xFFF0F0FA).withValues(alpha: 0.5),
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
              color: selected ? accent.withValues(alpha: 0.15) : unselectedBg,
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
            color: accent.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: accent.withValues(alpha: 0.4)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(config.keyToRepeat.toUpperCase(), style: TextStyle(
              color: accent, fontWeight: FontWeight.w700,
              fontFamily: 'monospace', fontSize: 22, letterSpacing: 2,
            )),
            const SizedBox(width: 10),
            Icon(FluentIcons.edit, size: 14, color: accent.withValues(alpha: 0.6)),
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
      decoration: BoxDecoration(color: accent.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4), border: Border.all(color: accent.withValues(alpha: 0.3))),
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

  // ─── Mouse Sequence Editor ────────────────────────────────

  Widget _buildMouseSequenceEditor(BuildContext context, ClickerConfig config, AppState state, FluentThemeData theme) {
    final seq = config.mouseSequence;
    final isDark = theme.brightness == Brightness.dark;
    final containerBg = isDark ? const Color(0xFF303050) : const Color(0xFFF0F0F8);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (seq.isNotEmpty) ...[
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: containerBg, borderRadius: BorderRadius.circular(8)),
          child: Wrap(spacing: 4, runSpacing: 4, children: [
            for (int i = 0; i < seq.length; i++) ...[
              _mouseActionChip(seq[i], onDelete: () {
                final n = List<MouseActionItem>.from(seq)..removeAt(i);
                state.setClickerConfig(config.copyWith(mouseSequence: n));
              }),
              if (i < seq.length - 1) const Icon(FluentIcons.forward, size: 12),
            ],
          ]),
        ),
        const SizedBox(height: 6),
        Row(children: [
          Text('共 ${seq.length} 个动作', style: TextStyle(fontSize: 12, color: theme.brightness == Brightness.dark ? const Color(0xFF9090B0) : const Color(0xFF8A8A9A))),
          const Spacer(),
          HyperlinkButton(onPressed: () => state.setClickerConfig(config.copyWith(mouseSequence: <MouseActionItem>[])), child: const Text('清空')),
        ]),
      ] else
        const Padding(padding: EdgeInsets.all(16), child: Center(child: Text('点击下方按钮添加动作', style: TextStyle(fontSize: 12)))),
      const SizedBox(height: 8),
      SizedBox(width: double.infinity, child: Button(onPressed: () => _showMouseActionPicker(context, state, config), child: const Text('+ 添加动作'))),
      const SizedBox(height: 10),
      const Text('快速模板', style: TextStyle(fontSize: 12)),
      const SizedBox(height: 4),
      Wrap(spacing: 4, runSpacing: 4, children: [
        _mouseTemplateChip('左键后右键', [
          const MouseActionItem(action: MouseActionType.click, button: MouseButton.left, delayMs: 50),
          const MouseActionItem(action: MouseActionType.click, button: MouseButton.right, delayMs: 50),
        ], config, state),
        _mouseTemplateChip('左键双击', [
          const MouseActionItem(action: MouseActionType.doubleClick, button: MouseButton.left, delayMs: 50),
        ], config, state),
        _mouseTemplateChip('按住后松开', [
          const MouseActionItem(action: MouseActionType.press, button: MouseButton.left, delayMs: 200),
          const MouseActionItem(action: MouseActionType.release, button: MouseButton.left, delayMs: 50),
        ], config, state),
      ]),
    ]);
  }

  static String _mouseActionLabel(MouseActionItem item) {
    if (item.action == MouseActionType.delay) return '延迟 ${item.delayMs}ms';
    const actionLabels = {
      MouseActionType.click: '单击',
      MouseActionType.doubleClick: '双击',
      MouseActionType.press: '按下',
      MouseActionType.release: '松开',
    };
    const buttonLabels = {
      MouseButton.left: '左键', MouseButton.right: '右键', MouseButton.middle: '中键',
      MouseButton.scrollUp: '滚轮上', MouseButton.scrollDown: '滚轮下',
      MouseButton.x1: '侧键1', MouseButton.x2: '侧键2',
    };
    return '${buttonLabels[item.button]}·${actionLabels[item.action]}';
  }

  Widget _mouseActionChip(MouseActionItem item, {VoidCallback? onDelete}) {
    return Builder(builder: (context) {
      final accent = FluentTheme.of(context).accentColor;
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(color: accent.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4), border: Border.all(color: accent.withValues(alpha: 0.3))),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(_mouseActionLabel(item), style: TextStyle(color: accent, fontWeight: FontWeight.w600, fontFamily: 'monospace', fontSize: 12)),
          if (onDelete != null) ...[
            const SizedBox(width: 4),
            IconButton(icon: const Icon(FluentIcons.clear, size: 10), onPressed: onDelete),
          ],
        ]),
      );
    });
  }

  Widget _mouseTemplateChip(String label, List<MouseActionItem> items, ClickerConfig config, AppState state) {
    return _selectChip(label, false, () => state.setClickerConfig(config.copyWith(mouseSequence: items)));
  }

  void _showMouseActionPicker(BuildContext context, AppState state, ClickerConfig config) {
    showDialog(context: context, builder: (ctx) => _MouseActionPickerDialog(onConfirm: (item) {
      final n = List<MouseActionItem>.from(config.mouseSequence)..add(item);
      state.setClickerConfig(config.copyWith(mouseSequence: n));
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
      TextBox(maxLines: 4, placeholder: '在此输入文本内容...', controller: _textTypeController,
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

  // ─── Mouse Action Type (click / drag / swipe) ────────────

  Widget _buildMouseActionSelector(ClickerConfig config, AppState state, FluentThemeData theme) {
    return Wrap(spacing: 6, runSpacing: 6, children: [
      _selectChip('单击', config.clickType == ClickType.single,
        () => state.setClickerConfig(config.copyWith(clickType: ClickType.single))),
      _selectChip('双击', config.clickType == ClickType.double,
        () => state.setClickerConfig(config.copyWith(clickType: ClickType.double))),
      _selectChip('拖拽', config.clickType == ClickType.drag,
        () => state.setClickerConfig(config.copyWith(clickType: ClickType.drag)), icon: FluentIcons.move),
      _selectChip('扫过', config.clickType == ClickType.swipe,
        () => state.setClickerConfig(config.copyWith(clickType: ClickType.swipe)), icon: FluentIcons.forward),
      _selectChip('序列', config.clickType == ClickType.sequence,
        () => state.setClickerConfig(config.copyWith(clickType: ClickType.sequence)), icon: FluentIcons.bulleted_list),
    ]);
  }

  // ─── Mouse Drag Path ──────────────────────────────────────

  Widget _buildMouseDragPathSelector(BuildContext context, ClickerConfig config, AppState state, FluentThemeData theme) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _buildCoordRow('起点', config.dragStartX, config.dragStartY, (x, y) =>
        state.setClickerConfig(config.copyWith(dragStartX: x, dragStartY: y))),
      const SizedBox(height: 8),
      _buildCoordRow('终点', config.dragEndX, config.dragEndY, (x, y) =>
        state.setClickerConfig(config.copyWith(dragEndX: x, dragEndY: y))),
      const SizedBox(height: 8),
      Row(children: [
        Button(onPressed: () async {
          final result = await ScreenOverlayService.instance.startPick();
          if (result != null) state.setClickerConfig(config.copyWith(dragStartX: result.$1, dragStartY: result.$2));
        }, child: const Text('选取起点')),
        const SizedBox(width: 8),
        Button(onPressed: () async {
          final result = await ScreenOverlayService.instance.startPick();
          if (result != null) state.setClickerConfig(config.copyWith(dragEndX: result.$1, dragEndY: result.$2));
        }, child: const Text('选取终点')),
      ]),
    ]);
  }

  // ─── Mouse Swipe Path ─────────────────────────────────────

  Widget _buildMouseSwipePathSelector(BuildContext context, ClickerConfig config, AppState state, FluentThemeData theme) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _buildCoordRow('起点', config.swipeStartX, config.swipeStartY, (x, y) =>
        state.setClickerConfig(config.copyWith(swipeStartX: x, swipeStartY: y))),
      const SizedBox(height: 8),
      _buildCoordRow('终点', config.swipeEndX, config.swipeEndY, (x, y) =>
        state.setClickerConfig(config.copyWith(swipeEndX: x, swipeEndY: y))),
      const SizedBox(height: 8),
      Row(children: [
        Button(onPressed: () async {
          final result = await ScreenOverlayService.instance.startPick();
          if (result != null) state.setClickerConfig(config.copyWith(swipeStartX: result.$1, swipeStartY: result.$2));
        }, child: const Text('选取起点')),
        const SizedBox(width: 8),
        Button(onPressed: () async {
          final result = await ScreenOverlayService.instance.startPick();
          if (result != null) state.setClickerConfig(config.copyWith(swipeEndX: result.$1, swipeEndY: result.$2));
        }, child: const Text('选取终点')),
      ]),
    ]);
  }

  Widget _buildCoordRow(String label, int x, int y, void Function(int, int) onChanged) {
    return Row(children: [
      Text(label, style: const TextStyle(fontSize: 13)),
      const SizedBox(width: 8),
      const Text('X:', style: TextStyle(fontSize: 13)),
      const SizedBox(width: 4),
      SizedBox(width: 70, child: TextBox(
        controller: TextEditingController(text: x.toString()),
        onChanged: (v) { final p = int.tryParse(v); if (p != null) onChanged(p, y); },
      )),
      const SizedBox(width: 8),
      const Text('Y:', style: TextStyle(fontSize: 13)),
      const SizedBox(width: 4),
      SizedBox(width: 70, child: TextBox(
        controller: TextEditingController(text: y.toString()),
        onChanged: (v) { final p = int.tryParse(v); if (p != null) onChanged(x, p); },
      )),
    ]);
  }

  // ─── Mouse Button ─────────────────────────────────────────

  Widget _buildMouseButtonSelector(ClickerConfig config, AppState state, FluentThemeData theme) {
    final labels = {
      MouseButton.left: '左键', MouseButton.right: '右键', MouseButton.middle: '中键',
      MouseButton.scrollUp: '滚轮上', MouseButton.scrollDown: '滚轮下',
      MouseButton.x1: '侧键1', MouseButton.x2: '侧键2',
    };
    return Wrap(spacing: 6, runSpacing: 4, children: MouseButton.values.map((btn) =>
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
    final result = await ScreenOverlayService.instance.startPick();
    if (result != null) {
      final (x, y) = result;
      state.setClickerConfig(state.clickerConfig.copyWith(fixedX: x, fixedY: y));
    }
  }

  // ─── Interval ─────────────────────────────────────────────

  Widget _buildIntervalSlider(ClickerConfig config, AppState state, FluentThemeData theme) {
    final ms = config.intervalMs;

    // 每个单位下的快捷档位（毫秒值 + 标签）
    final (List<double> chipMs, List<String> chipLabels) =
      switch (_intervalUnit) {
        _IntervalUnit.ms  => (const [1, 10, 50, 100, 500, 1000], const ['1ms', '10ms', '50ms', '100ms', '500ms', '1s']),
        _IntervalUnit.s   => (const [100, 500, 1000, 2000, 5000, 10000, 30000, 60000], const ['0.1s', '0.5s', '1s', '2s', '5s', '10s', '30s', '60s']),
        _IntervalUnit.min => (const [60000, 120000, 180000, 300000], const ['1min', '2min', '3min', '5min']),
      };

    String label;
    switch (_intervalUnit) {
      case _IntervalUnit.ms:
        label = '${ms.toInt()}ms';
      case _IntervalUnit.s:
        label = '${(ms / 1000).toStringAsFixed(1)}s';
      case _IntervalUnit.min:
        label = '${(ms / 60000).toStringAsFixed(2)}min';
    }

    // 左侧输入框的数值 = 实际毫秒 ÷ 单位倍率：输 100，选「秒」= 100 秒，选「毫秒」= 100 毫秒
    final factor = switch (_intervalUnit) {
      _IntervalUnit.ms => 1.0,
      _IntervalUnit.s => 1000.0,
      _IntervalUnit.min => 60000.0,
    };

    return Column(children: [
      Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
      const SizedBox(height: 4),
      // ── 当前单位下的快捷档位 ──
      Wrap(spacing: 4, runSpacing: 4, children: [
        for (var i = 0; i < chipMs.length; i++)
          _selectChip(
            chipLabels[i],
            (ms - chipMs[i]).abs() < 0.005,
            () => state.setClickerConfig(config.copyWith(intervalMs: chipMs[i]))),
      ]),
      const SizedBox(height: 8),
      // ── 精确输入框 + 单位下拉框（居中）──
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        SizedBox(width: 140, child: _DebouncedIntervalTextBox(
          value: ms / factor,
          onChanged: (v) => state.setClickerConfig(config.copyWith(intervalMs: (v * factor).roundToDouble())),
        )),
        const SizedBox(width: 10),
        SizedBox(width: 96, child: ComboBox<_IntervalUnit>(
          value: _intervalUnit,
          isExpanded: true,
          items: _IntervalUnit.values.map((unit) => ComboBoxItem<_IntervalUnit>(
            value: unit,
            child: Text(switch (unit) { _IntervalUnit.ms => '毫秒', _IntervalUnit.s => '秒', _IntervalUnit.min => '分' }),
          )).toList(),
          onChanged: (v) { if (v != null) setState(() => _intervalUnit = v); },
        )),
      ]),
    ]);
  }

  // ─── Repeat Mode ──────────────────────────────────────────

  Widget _buildRepeatModeSelector(ClickerConfig config, AppState state, FluentThemeData theme) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        _selectChip('无限重复', config.repeatMode == ClickRepeatMode.infinite, () => state.setClickerConfig(config.copyWith(repeatMode: ClickRepeatMode.infinite))),
        const SizedBox(width: 8),
        _selectChip('指定次数', config.repeatMode == ClickRepeatMode.count, () => state.setClickerConfig(config.copyWith(repeatMode: ClickRepeatMode.count))),
        const SizedBox(width: 8),
        _selectChip('定时关闭', config.repeatMode == ClickRepeatMode.duration, () => state.setClickerConfig(config.copyWith(repeatMode: ClickRepeatMode.duration))),
      ]),
      const SizedBox(height: 10),
      if (config.repeatMode == ClickRepeatMode.count)
        Row(children: [
          const Text('次数:', style: TextStyle(fontSize: 13)),
          const SizedBox(width: 8),
          DebouncedTextBox(
            value: config.repeatCount,
            min: 1, max: 999999,
            onChanged: (v) => state.setClickerConfig(config.copyWith(repeatCount: v)),
            width: 100,
          ),
        ])
      else if (config.repeatMode == ClickRepeatMode.duration)
        Row(children: [
          const Text('时长:', style: TextStyle(fontSize: 13)),
          const SizedBox(width: 8),
          DebouncedTextBox(
            value: config.durationSeconds,
            min: 1, max: 86400,
            onChanged: (v) => state.setClickerConfig(config.copyWith(durationSeconds: v)),
            width: 100,
          ),
          const Text(' 秒', style: TextStyle(fontSize: 12)),
        ]),
    ]);
  }

  // ─── Hold Trigger ─────────────────────────────────────────

  // ─── Background Click (from plugin) ────────────────────────

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
                color: fabColor.withValues(alpha: 0.4),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
              BoxShadow(
                color: (isDark ? const Color(0xFF1A1A2E) : const Color(0xFFF5F5FA)).withValues(alpha: 0.3),
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
    String fmtElapsed(Duration? elapsed) => elapsed != null
        ? (elapsed.inHours > 0 ? '${elapsed.inHours}h ${elapsed.inMinutes % 60}m' : (elapsed.inMinutes > 0 ? '${elapsed.inMinutes}m ${elapsed.inSeconds % 60}s' : '${elapsed.inSeconds}s'))
        : '';
    return ExcludeSemantics(
      child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: const Color(0xFF00E676).withValues(alpha: 0.08), borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF00E676).withValues(alpha: 0.3))),
      // 计数/CPS/耗时走独立 notifier 精准刷新，避免全页重建
      child: ValueListenableBuilder<int>(
        valueListenable: state.clickCountNotifier,
        builder: (_, count, __) => Row(children: [
          const Icon(FluentIcons.circle_fill, size: 8, color: Color(0xFF00E676)),
          const SizedBox(width: 8),
          Text('运行中 · ${isKeyboard ? "已按键" : "已点击"} $count 次', style: const TextStyle(color: Color(0xFF00E676), fontSize: 13)),
          if (showStats) ...[
            const SizedBox(width: 12),
            Text('${state.clickService.averageCps.toStringAsFixed(1)} CPS', style: TextStyle(color: const Color(0xFF00E676).withValues(alpha: 0.8), fontSize: 12)),
            const SizedBox(width: 8),
            Text(fmtElapsed(state.clickService.elapsedDuration), style: TextStyle(color: const Color(0xFF00E676).withValues(alpha: 0.7), fontSize: 12)),
          ],
          const Spacer(),
          Text('${state.clickerConfig.intervalMs}ms/次', style: TextStyle(color: const Color(0xFF00E676).withValues(alpha: 0.7), fontSize: 12)),
        ]),
      ),
    ));
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
          decoration: BoxDecoration(color: accent.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8), border: Border.all(color: accent.withValues(alpha: 0.4))),
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
                decoration: BoxDecoration(color: sel ? accent.withValues(alpha: 0.2) : unselectedBg,
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
          decoration: BoxDecoration(color: accent.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8), border: Border.all(color: accent.withValues(alpha: 0.4))),
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
                decoration: BoxDecoration(color: sel ? accent.withValues(alpha: 0.2) : unselectedBg,
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
                decoration: BoxDecoration(color: sel ? accent.withValues(alpha: 0.2) : unselectedBg,
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
                  decoration: BoxDecoration(color: sel ? accent.withValues(alpha: 0.2) : unselectedBg,
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

// ─── Mouse Action Picker Dialog ──────────────────────────────

class _MouseActionPickerDialog extends StatefulWidget {
  final ValueChanged<MouseActionItem> onConfirm;
  const _MouseActionPickerDialog({required this.onConfirm});
  @override
  State<_MouseActionPickerDialog> createState() => _MouseActionPickerDialogState();
}

class _MouseActionPickerDialogState extends State<_MouseActionPickerDialog> {
  MouseActionType _action = MouseActionType.click;
  MouseButton _button = MouseButton.left;
  int _delayMs = 50;

  static const _actionLabels = <MouseActionType, String>{
    MouseActionType.click: '单击',
    MouseActionType.doubleClick: '双击',
    MouseActionType.press: '按下',
    MouseActionType.release: '松开',
    MouseActionType.delay: '延迟',
  };
  static const _buttonLabels = <MouseButton, String>{
    MouseButton.left: '左键', MouseButton.right: '右键', MouseButton.middle: '中键',
    MouseButton.scrollUp: '滚轮上', MouseButton.scrollDown: '滚轮下',
    MouseButton.x1: '侧键1', MouseButton.x2: '侧键2',
  };

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = theme.accentColor;
    final unselectedBg = isDark ? const Color(0xFF303050) : const Color(0xFFE8E8F0);
    final unselectedBorder = isDark ? const Color(0xFF404060) : const Color(0xFFD0D0D8);
    final unselectedText = isDark ? const Color(0xFFC0C0D8) : const Color(0xFF5A5A70);
    return ContentDialog(
      title: const Text('添加动作'),
      content: SizedBox(width: 400, child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('动作类型', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 6, children: _actionLabels.entries.map((e) {
          final sel = _action == e.key;
          return GestureDetector(onTap: () => setState(() => _action = e.key),
            child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(color: sel ? accent.withValues(alpha: 0.2) : unselectedBg,
                borderRadius: BorderRadius.circular(4), border: Border.all(color: sel ? accent : unselectedBorder)),
              child: Text(e.value, style: TextStyle(fontSize: 12, color: sel ? accent : unselectedText, fontWeight: sel ? FontWeight.w600 : FontWeight.normal)),
            ),
          );
        }).toList()),
        const SizedBox(height: 14),
        if (_action != MouseActionType.delay) ...[
          const Text('鼠标按键', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 6, children: _buttonLabels.entries.map((e) {
            final sel = _button == e.key;
            return GestureDetector(onTap: () => setState(() => _button = e.key),
              child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(color: sel ? accent.withValues(alpha: 0.2) : unselectedBg,
                  borderRadius: BorderRadius.circular(4), border: Border.all(color: sel ? accent : unselectedBorder)),
                child: Text(e.value, style: TextStyle(fontSize: 12, color: sel ? accent : unselectedText, fontWeight: sel ? FontWeight.w600 : FontWeight.normal)),
              ),
            );
          }).toList()),
          const SizedBox(height: 14),
        ],
        const Text('步进延迟', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
        const SizedBox(height: 6),
        Row(children: [
          Text(_action == MouseActionType.delay ? '等待 ${_delayMs}ms' : '动作后延迟 ${_delayMs}ms', style: const TextStyle(fontSize: 12)),
          Expanded(child: Slider(value: _delayMs.toDouble(), min: 0, max: 2000, divisions: 80, onChanged: (v) => setState(() => _delayMs = v.round()))),
        ]),
      ])),
      actions: [FilledButton(onPressed: () {
        widget.onConfirm(MouseActionItem(action: _action, button: _button, delayMs: _delayMs));
      }, child: const Text('确认'))],
    );
  }
}

/// Debounced interval TextBox for double values (ms).
class _DebouncedIntervalTextBox extends StatefulWidget {
  final double value;
  final ValueChanged<double> onChanged;
  const _DebouncedIntervalTextBox({required this.value, required this.onChanged});

  @override
  State<_DebouncedIntervalTextBox> createState() => _DebouncedIntervalTextBoxState();
}

class _DebouncedIntervalTextBoxState extends State<_DebouncedIntervalTextBox> {
  late TextEditingController _controller;
  late FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _formatValue(widget.value));
    _focusNode = FocusNode();
    _focusNode.addListener(_onFocusChange);
  }

  static String _formatValue(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);

  @override
  void didUpdateWidget(covariant _DebouncedIntervalTextBox oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_focusNode.hasFocus && widget.value != oldWidget.value) {
      _controller.text = _formatValue(widget.value);
    }
  }

  void _onFocusChange() {
    if (!_focusNode.hasFocus) _commitValue();
  }

  void _commitValue() {
    final p = double.tryParse(_controller.text);
    if (p != null && p >= 1) {
      _controller.text = _formatValue(p);
      if (p != widget.value) widget.onChanged(p);
    } else {
      _controller.text = _formatValue(widget.value);
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextBox(
      controller: _controller,
      focusNode: _focusNode,
      placeholder: '自定义(ms)',
      textAlign: TextAlign.center,
      onSubmitted: (_) => _commitValue(),
    );
  }
}
