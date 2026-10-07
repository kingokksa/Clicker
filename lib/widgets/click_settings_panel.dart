import 'package:fluent_ui/fluent_ui.dart';
import '../models/clicker_config.dart';
import '../models/click_settings.dart';
import 'debounced_text_box.dart';

enum ClickSettingGroup { interval, mouseButton, clickType, holdMs, randomDelay, randomOffset, humanLike }

const Map<MouseButton, String> kMouseButtonLabels = {
  MouseButton.left: '左键',
  MouseButton.right: '右键',
  MouseButton.middle: '中键',
  MouseButton.scrollUp: '滚轮上',
  MouseButton.scrollDown: '滚轮下',
  MouseButton.x1: '侧键1',
  MouseButton.x2: '侧键2',
};

class ClickSettingsPanel extends StatelessWidget {
  final ClickSettings settings;
  final ValueChanged<ClickSettings> onChanged;
  final List<ClickSettingGroup> groups;
  final String intervalLabel;

  const ClickSettingsPanel({
    super.key,
    required this.settings,
    required this.onChanged,
    this.groups = ClickSettingGroup.values,
    this.intervalLabel = '间隔',
  });

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    for (final group in groups) {
      if (children.isNotEmpty) children.add(const SizedBox(height: 8));
      switch (group) {
        case ClickSettingGroup.interval:
          children.add(_row(intervalLabel, _number(
            value: settings.intervalMs,
            min: 10,
            max: 60000,
            onChanged: (v) => onChanged(settings.copyWith(intervalMs: v)),
          )));
        case ClickSettingGroup.mouseButton:
          children.add(Wrap(spacing: 6, runSpacing: 4, children: [
            for (final btn in MouseButton.values)
              _chip(
                kMouseButtonLabels[btn]!,
                settings.mouseButton == btn,
                () => onChanged(settings.copyWith(mouseButton: btn)),
              ),
          ]));
        case ClickSettingGroup.clickType:
          children.add(Wrap(spacing: 6, runSpacing: 4, children: [
            _chip('单击', !settings.doubleClick,
              () => onChanged(settings.copyWith(doubleClick: false))),
            _chip('双击', settings.doubleClick,
              () => onChanged(settings.copyWith(doubleClick: true))),
          ]));
        case ClickSettingGroup.holdMs:
          children.add(Wrap(spacing: 6, runSpacing: 4, children: [
            for (final ms in const [0, 10, 20, 30, 50, 100])
              _chip(
                ms == 0 ? '不保持' : '${ms}ms',
                settings.holdMs == ms,
                () => onChanged(settings.copyWith(holdMs: ms)),
              ),
          ]));
          children.add(const SizedBox(height: 8));
          children.add(_number(
            value: settings.holdMs,
            min: 0,
            max: 5000,
            width: 100,
            onChanged: (v) => onChanged(settings.copyWith(holdMs: v)),
          ));
        case ClickSettingGroup.randomDelay:
          children.add(_toggle('随机延迟', settings.randomDelayEnabled,
            (v) => onChanged(settings.copyWith(randomDelayEnabled: v))));
          if (settings.randomDelayEnabled) {
            children.add(const SizedBox(height: 6));
            children.add(_range('延迟范围', 'ms',
              settings.randomDelayMinMs,
              settings.randomDelayMaxMs,
              (v) => onChanged(settings.copyWith(randomDelayMinMs: v)),
              (v) => onChanged(settings.copyWith(randomDelayMaxMs: v)),
            ));
          }
        case ClickSettingGroup.randomOffset:
          children.add(_toggle('随机偏移', settings.randomOffsetEnabled,
            (v) => onChanged(settings.copyWith(randomOffsetEnabled: v))));
          if (settings.randomOffsetEnabled) {
            children.add(const SizedBox(height: 6));
            children.add(_range('偏移范围', 'px',
              settings.randomOffsetMinPx,
              settings.randomOffsetMaxPx,
              (v) => onChanged(settings.copyWith(randomOffsetMinPx: v)),
              (v) => onChanged(settings.copyWith(randomOffsetMaxPx: v)),
            ));
          }
        case ClickSettingGroup.humanLike:
          children.add(_toggle('拟人化移动', settings.humanLikeEnabled,
            (v) => onChanged(settings.copyWith(humanLikeEnabled: v))));
          if (settings.humanLikeEnabled) {
            children.add(const SizedBox(height: 6));
            children.add(_toggle('贝塞尔轨迹', settings.humanLikeBezierCurve,
              (v) => onChanged(settings.copyWith(humanLikeBezierCurve: v))));
            children.add(const SizedBox(height: 6));
            children.add(_toggle('随机暂停', settings.humanLikeRandomPause,
              (v) => onChanged(settings.copyWith(humanLikeRandomPause: v))));
            if (settings.humanLikeRandomPause) {
              children.add(const SizedBox(height: 6));
              children.add(_row('暂停概率', Row(mainAxisSize: MainAxisSize.min, children: [
                _number(
                  value: settings.humanLikePauseChance,
                  min: 1,
                  max: 100,
                  width: 70,
                  unit: '%',
                  onChanged: (v) => onChanged(settings.copyWith(humanLikePauseChance: v)),
                ),
              ])));
              children.add(const SizedBox(height: 6));
              children.add(_range('暂停时长', 'ms',
                settings.humanLikePauseMinMs,
                settings.humanLikePauseMaxMs,
                (v) => onChanged(settings.copyWith(humanLikePauseMinMs: v)),
                (v) => onChanged(settings.copyWith(humanLikePauseMaxMs: v)),
              ));
            }
          }
      }
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: children);
  }

  Widget _row(String label, Widget control) {
    return Row(children: [
      Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
      control,
    ]);
  }

  Widget _toggle(String label, bool value, ValueChanged<bool> onChanged) {
    return Row(children: [
      Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
      ToggleSwitch(checked: value, onChanged: onChanged),
    ]);
  }

  Widget _range(
    String label,
    String unit,
    int minValue,
    int maxValue,
    ValueChanged<int> onMinChanged,
    ValueChanged<int> onMaxChanged,
  ) {
    return _row(label, Row(mainAxisSize: MainAxisSize.min, children: [
      _number(value: minValue, min: 0, max: 10000, width: 70, unit: '', onChanged: onMinChanged),
      const Padding(
        padding: EdgeInsets.symmetric(horizontal: 6),
        child: Text('~', style: TextStyle(fontSize: 13)),
      ),
      _number(value: maxValue, min: 0, max: 10000, width: 70, unit: '', onChanged: onMaxChanged),
      const SizedBox(width: 6),
      Text(unit, style: const TextStyle(fontSize: 12)),
    ]));
  }

  Widget _number({
    required int value,
    required int min,
    required int max,
    required ValueChanged<int> onChanged,
    double width = 90,
    String unit = 'ms',
  }) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      SizedBox(
        width: width,
        child: DebouncedTextBox(value: value, min: min, max: max, onChanged: onChanged),
      ),
      if (unit.isNotEmpty) ...[
        const SizedBox(width: 6),
        Text(unit, style: const TextStyle(fontSize: 12)),
      ],
    ]);
  }

  Widget _chip(String label, bool selected, VoidCallback onTap) {
    return Builder(builder: (context) {
      final isDark = FluentTheme.of(context).brightness == Brightness.dark;
      final accent = FluentTheme.of(context).accentColor;
      final unselectedBg = isDark ? const Color(0xFF303050) : const Color(0xFFE8E8F0);
      final unselectedBorder = isDark ? const Color(0xFF404060) : const Color(0xFFD0D0D8);
      final unselectedText = isDark ? const Color(0xFFC0C0D8) : const Color(0xFF5A5A70);
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
            child: Text(label, style: TextStyle(
              fontSize: 13,
              fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
              color: selected ? accent : unselectedText,
            )),
          ),
        ),
      );
    });
  }
}
