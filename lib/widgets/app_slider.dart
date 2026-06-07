import 'package:fluent_ui/fluent_ui.dart';

/// Drop-in replacement for fluent_ui Slider that avoids the
/// `showValueIndicator` NoSuchMethodError in fluent_ui 4.x.
///
/// Usage: same API as Slider but renders the label next to the slider
/// instead of using the broken overlay.
class AppSlider extends StatelessWidget {
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final String? label;
  final ValueChanged<double>? onChanged;
  final ValueChanged<double>? onChangeEnd;

  const AppSlider({
    super.key,
    required this.value,
    this.min = 0.0,
    this.max = 1.0,
    this.divisions,
    this.label,
    this.onChanged,
    this.onChangeEnd,
  });

  @override
  Widget build(BuildContext context) {
    // If there's a label, show it as a trailing text instead of overlay
    if (label != null) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Expanded(
            child: Slider(
              value: value,
              min: min,
              max: max,
              divisions: divisions,
              onChanged: onChanged,
              onChangeEnd: onChangeEnd,
            ),
          ),
          SizedBox(
            width: 48,
            child: Text(
              label!,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                color: FluentTheme.of(context).brightness == Brightness.dark
                  ? const Color(0xFFB0B0D0) : const Color(0xFF5A5A70)),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      );
    }
    return Slider(
      value: value,
      min: min,
      max: max,
      divisions: divisions,
      onChanged: onChanged,
      onChangeEnd: onChangeEnd,
    );
  }
}
