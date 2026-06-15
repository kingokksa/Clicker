/// Full-screen overlay for picking a position on screen by tapping.
/// Returns (x, y) screen coordinates when user taps.
library;

import 'package:flutter/material.dart';

class PositionPickerOverlay extends StatelessWidget {
  final String title;

  const PositionPickerOverlay({super.key, this.title = '选择位置'});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black.withValues(alpha: 0.7),
      body: Stack(children: [
        // Tap area — entire screen
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (details) {
            final renderBox = context.findRenderObject() as RenderBox;
            final localPos = details.localPosition;
            final screenSize = MediaQuery.of(context).size;
            // Convert to screen coordinates (approximate)
            final x = (localPos.dx / screenSize.width * screenSize.width).round();
            final y = (localPos.dy / screenSize.height * screenSize.height).round();
            Navigator.of(context).pop((x, y));
          },
          child: const SizedBox.expand(),
        ),

        // Top instruction bar
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              color: Colors.black54,
              child: Row(children: [
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                const SizedBox(width: 8),
                Text(title,
                    style: const TextStyle(
                        color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                const Spacer(),
                const Text('点击屏幕选择位置',
                    style: TextStyle(color: Colors.white70, fontSize: 13)),
              ]),
            ),
          ),
        ),

        // Center crosshair hint
        Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.add_circle_outline, size: 48,
                color: Colors.white.withValues(alpha: 0.5)),
            const SizedBox(height: 8),
            const Text('点击任意位置',
                style: TextStyle(color: Colors.white70, fontSize: 14)),
          ]),
        ),
      ]),
    );
  }
}
