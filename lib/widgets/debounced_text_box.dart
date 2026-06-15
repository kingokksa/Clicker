/// Fluent UI TextBox that doesn't lose focus when parent rebuilds.
/// Only commits value on submit or focus loss, not on every keystroke.
library;

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';

class DebouncedTextBox extends StatefulWidget {
  final String? placeholder;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;
  final double? width;

  const DebouncedTextBox({
    super.key,
    this.placeholder,
    required this.value,
    this.min = 0,
    this.max = 999999,
    required this.onChanged,
    this.width,
  });

  @override
  State<DebouncedTextBox> createState() => _DebouncedTextBoxState();
}

class _DebouncedTextBoxState extends State<DebouncedTextBox> {
  late TextEditingController _controller;
  late FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value.toString());
    _focusNode = FocusNode();
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(DebouncedTextBox oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_focusNode.hasFocus && widget.value != oldWidget.value) {
      _controller.text = widget.value.toString();
    }
  }

  void _onFocusChange() {
    if (!_focusNode.hasFocus) _commitValue();
  }

  void _commitValue() {
    final val = int.tryParse(_controller.text);
    if (val != null) {
      final clamped = val.clamp(widget.min, widget.max);
      _controller.text = clamped.toString();
      if (clamped != widget.value) widget.onChanged(clamped);
    } else {
      _controller.text = widget.value.toString();
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
    return SizedBox(
      width: widget.width,
      child: TextBox(
        controller: _controller,
        focusNode: _focusNode,
        placeholder: widget.placeholder,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        onSubmitted: (_) => _commitValue(),
      ),
    );
  }
}
