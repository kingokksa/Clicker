
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class DebouncedNumberField extends StatefulWidget {
  final String label;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;
  final bool isDark;

  const DebouncedNumberField({
    super.key,
    required this.label,
    required this.value,
    this.min = 0,
    this.max = 999999,
    required this.onChanged,
    required this.isDark,
  });

  @override
  State<DebouncedNumberField> createState() => _DebouncedNumberFieldState();
}

class _DebouncedNumberFieldState extends State<DebouncedNumberField> {
  late TextEditingController _controller;
  late FocusNode _focusNode;
  Timer? _commitDebounce;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value.toString());
    _focusNode = FocusNode();
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(DebouncedNumberField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_focusNode.hasFocus && widget.value != oldWidget.value) {
      _controller.text = widget.value.toString();
    }
  }

  void _onFocusChange() {
    if (!_focusNode.hasFocus) {
      _commitValue();
    }
  }

  void _onTyping(String _) {
    _commitDebounce?.cancel();
    _commitDebounce = Timer(const Duration(milliseconds: 600), _commitValue);
  }

  void _commitValue() {
    _commitDebounce?.cancel();
    _commitDebounce = null;
    final val = int.tryParse(_controller.text);
    if (val != null) {
      final clamped = val.clamp(widget.min, widget.max);
      _controller.text = clamped.toString();
      if (clamped != widget.value) {
        widget.onChanged(clamped);
      }
    } else {
      _controller.text = widget.value.toString();
    }
  }

  @override
  void dispose() {
    _commitDebounce?.cancel();
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      focusNode: _focusNode,
      decoration: InputDecoration(
        labelText: widget.label,
        labelStyle: TextStyle(color: widget.isDark ? Colors.grey : null),
        border: const OutlineInputBorder(),
      ),
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      onChanged: _onTyping,
      onSubmitted: (_) => _commitValue(),
    );
  }
}
