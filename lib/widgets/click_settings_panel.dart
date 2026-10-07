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
          children.add(_row('鼠标按键', SizedBox(
            width: 140,
            child: ComboBox<MouseButton>(
              value: settings.mouseButton,
              items: MouseButton.values
                  .map((b) => ComboBoxItem<MouseButton>(value: b, child: Text(kMouseButtonLabels[b]!)))
                  .toList(),
              onChanged: (v) {
                if (v != null) onChanged(settings.copyWith(mouseButton: v));
              },
            ),
          )));
        case ClickSettingGroup.clickType:
          children.add(_row('点击方式', SizedBox(
            width: 140,
            child: ComboBox<bool>(
              value: settings.doubleClick,
              items: [
                const ComboBoxItem<bool>(value: false, child: Text('单击')),
                const ComboBoxItem<bool>(value: true, child: Text('双击')),
              ],
              onChanged: (v) {
                if (v != null) onChanged(settings.copyWith(doubleClick: v));
              },
            ),
          )));
        case ClickSettingGroup.holdMs:
          children.add(_row('按住时长', _number(
            value: settings.holdMs,
            min: 0,
            max: 5000,
            onChanged: (v) => onChanged(settings.copyWith(holdMs: v)),
          )));
        case ClickSettingGroup.randomDelay:
          children.add(_toggle('随机延迟', settings.randomDelayEnabled,
            (v) => onChanged(settings.copyWith(randomDelayEnabled: v))));
          if (settings.randomDelayEnabled) {
            children.add(const SizedBox(height: 6));
            children.add(_row('延迟范围', Row(mainAxisSize: MainAxisSize.min, children: [
              _number(
                value: settings.randomDelayMinMs,
                min: 0,
                max: 10000,
                width: 70,
                unit: '',
                onChanged: (v) => onChanged(settings.copyWith(randomDelayMinMs: v)),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 6),
                child: Text('~', style: TextStyle(fontSize: 13)),
              ),
              _number(
                value: settings.randomDelayMaxMs,
                min: 0,
                max: 10000,
                width: 70,
                unit: '',
                onChanged: (v) => onChanged(settings.copyWith(randomDelayMaxMs: v)),
              ),
              const SizedBox(width: 6),
              const Text('ms', style: TextStyle(fontSize: 12)),
            ])));
          }
        case ClickSettingGroup.randomOffset:
          children.add(_toggle('随机偏移', settings.randomOffsetEnabled,
            (v) => onChanged(settings.copyWith(randomOffsetEnabled: v))));
          if (settings.randomOffsetEnabled) {
            children.add(const SizedBox(height: 6));
            children.add(_row('偏移范围', Row(mainAxisSize: MainAxisSize.min, children: [
              _number(
                value: settings.randomOffsetMinPx,
                min: 0,
                max: 500,
                width: 70,
                unit: '',
                onChanged: (v) => onChanged(settings.copyWith(randomOffsetMinPx: v)),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 6),
                child: Text('~', style: TextStyle(fontSize: 13)),
              ),
              _number(
                value: settings.randomOffsetMaxPx,
                min: 0,
                max: 500,
                width: 70,
                unit: '',
                onChanged: (v) => onChanged(settings.copyWith(randomOffsetMaxPx: v)),
              ),
              const SizedBox(width: 6),
              const Text('px', style: TextStyle(fontSize: 12)),
            ])));
          }
        case ClickSettingGroup.humanLike:
          children.add(_toggle('拟人化移动', settings.humanLikeEnabled,
            (v) => onChanged(settings.copyWith(humanLikeEnabled: v))));
          if (settings.humanLikeEnabled) {
            children.add(const SizedBox(height: 6));
            children.add(_toggle('贝塞尔轨迹', settings.humanLikeBezierCurve,
              (v) => onChanged(settings.copyWith(humanLikeBezierCurve: v))));
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
}
