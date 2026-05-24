/// Fullscreen position picker overlay — covers entire screen for picking.
/// Uses MouseRegion for smooth hover tracking, Listener for click.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class PositionPickerOverlay extends StatefulWidget {
  final int initialX;
  final int initialY;

  const PositionPickerOverlay({super.key, this.initialX = 0, this.initialY = 0});

  @override
  State<PositionPickerOverlay> createState() => _PositionPickerOverlayState();
}

class _PositionPickerOverlayState extends State<PositionPickerOverlay> {
  Offset _mousePos = Offset.zero;
  Offset? _pickedPos;
  bool _hasMouse = false;
  double _dpr = 1.0;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  bool _onKey(KeyEvent event) {
    if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.escape) {
      Navigator.of(context).pop();
      return true;
    }
    return false;
  }

  int _toScreenX(double logicalX) => (logicalX * _dpr).round();
  int _toScreenY(double logicalY) => (logicalY * _dpr).round();

  void _onHover(PointerHoverEvent event) {
    setState(() {
      _mousePos = event.position;
      _hasMouse = true;
    });
  }

  void _onTap() {
    if (!_hasMouse) return;
    setState(() => _pickedPos = _mousePos);
    final screenX = _toScreenX(_mousePos.dx);
    final screenY = _toScreenY(_mousePos.dy);
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) {
        Navigator.of(context).pop((x: screenX, y: screenY));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    _dpr = MediaQuery.of(context).devicePixelRatio;
    final theme = Theme.of(context);
    final screenSize = MediaQuery.of(context).size;

    return Material(
      type: MaterialType.transparency,
      child: MouseRegion(
        hitTestBehavior: HitTestBehavior.opaque,
        onHover: _onHover,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _onTap,
          child: Stack(
            children: [
              Container(color: Colors.black54),

              // Crosshair
              Positioned.fill(
                child: CustomPaint(
                  painter: _CrosshairPainter(
                    mousePos: _mousePos,
                    pickedPos: _pickedPos,
                    hasMouse: _hasMouse,
                  ),
                ),
              ),

              // Top instruction bar
              Positioned(
                top: 40, left: 0, right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface.withValues(alpha: 0.95),
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.4)),
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 12)],
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.crop_free, color: theme.colorScheme.primary, size: 18),
                      const SizedBox(width: 8),
                      Text('点击选取位置 · Esc 取消', style: TextStyle(
                        color: theme.colorScheme.onSurface, fontSize: 15, fontWeight: FontWeight.w500,
                      )),
                    ]),
                  ),
                ),
              ),

              // Live coordinate near cursor
              if (_hasMouse && _pickedPos == null)
                Positioned(
                  left: (_mousePos.dx + 20).clamp(0.0, screenSize.width - 180),
                  top: (_mousePos.dy - 40).clamp(0.0, screenSize.height - 40),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary,
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 6)],
                    ),
                    child: Text(
                      '(${_toScreenX(_mousePos.dx)}, ${_toScreenY(_mousePos.dy)})',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontFamily: 'monospace', fontSize: 13),
                    ),
                  ),
                ),

              // Picked position confirmation
              if (_pickedPos != null)
                Positioned(
                  left: (_pickedPos!.dx + 20).clamp(0.0, screenSize.width - 200),
                  top: (_pickedPos!.dy - 40).clamp(0.0, screenSize.height - 40),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00E676),
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 6)],
                    ),
                    child: Text(
                      '已选取 (${_toScreenX(_pickedPos!.dx)}, ${_toScreenY(_pickedPos!.dy)})',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CrosshairPainter extends CustomPainter {
  final Offset mousePos;
  final Offset? pickedPos;
  final bool hasMouse;

  _CrosshairPainter({required this.mousePos, this.pickedPos, required this.hasMouse});

  @override
  void paint(Canvas canvas, Size size) {
    if (!hasMouse) return;

    final paint = Paint()..color = const Color(0xFF6C63FF)..strokeWidth = 1.5..style = PaintingStyle.stroke;
    final pickedPaint = Paint()..color = const Color(0xFF00E676)..strokeWidth = 2.5..style = PaintingStyle.stroke;

    if (pickedPos != null) {
      canvas.drawLine(Offset(pickedPos!.dx, 0), Offset(pickedPos!.dx, size.height), pickedPaint);
      canvas.drawLine(Offset(0, pickedPos!.dy), Offset(size.width, pickedPos!.dy), pickedPaint);
      canvas.drawCircle(pickedPos!, 12, pickedPaint);
    } else {
      canvas.drawLine(Offset(mousePos.dx, 0), Offset(mousePos.dx, size.height), paint);
      canvas.drawLine(Offset(0, mousePos.dy), Offset(size.width, mousePos.dy), paint);
      canvas.drawCircle(mousePos, 8, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _CrosshairPainter old) => true;
}
