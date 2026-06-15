/// Abstract platform input interface.
/// Implementations: Win32 SendInput (Windows), AccessibilityService (Android).
library;

import 'dart:async';

abstract class PlatformInput {
  /// Perform a mouse click at the given position.
  Future<void> mouseClick({
    required int x,
    required int y,
    String button = 'left', // left | right | middle
    bool doubleClick = false,
  });

  /// Synchronous fast click — no async overhead.
  /// Only for single clicks in high-speed mode.
  void syncClick({required int x, required int y, String button = 'left'});

  /// Move mouse cursor to position.
  Future<void> mouseMove(int x, int y);

  /// Mouse down/up for drag operations.
  Future<void> mouseDown({required int x, required int y, String button = 'left'});
  Future<void> mouseUp({required int x, required int y, String button = 'left'});

  /// Mouse drag: press at start, move to end, release.
  /// Default implementation uses mouseDown → mouseMove → mouseUp.
  Future<void> mouseDrag({
    required int startX, required int startY,
    required int endX, required int endY,
    int durationMs = 300,
  }) async {
    await mouseDown(x: startX, y: startY);
    // Interpolate movement over durationMs
    final steps = (durationMs / 16).ceil().clamp(1, 100);
    final dx = (endX - startX) / steps;
    final dy = (endY - startY) / steps;
    for (int i = 1; i <= steps; i++) {
      await mouseMove((startX + dx * i).round(), (startY + dy * i).round());
      if (i < steps) await Future.delayed(Duration(milliseconds: (durationMs / steps).round()));
    }
    await mouseUp(x: endX, y: endY);
  }

  /// Mouse swipe: fast drag with shorter duration.
  Future<void> mouseSwipe({
    required int startX, required int startY,
    required int endX, required int endY,
    int durationMs = 200,
  }) async {
    await mouseDrag(
      startX: startX, startY: startY,
      endX: endX, endY: endY,
      durationMs: durationMs,
    );
  }

  /// Scroll wheel.
  Future<void> mouseScroll({double dx = 0, double dy = 0});

  /// Touch gesture: long press at (x, y) for [durationMs].
  Future<void> touchLongPress({required int x, required int y, int durationMs = 500});

  /// Touch gesture: drag from (startX, startY) to (endX, endY) over [durationMs].
  Future<void> touchDrag({
    required int startX, required int startY,
    required int endX, required int endY,
    int durationMs = 300,
  });

  /// Touch gesture: swipe (fast drag) from (startX, startY) to (endX, endY) over [durationMs].
  Future<void> touchSwipe({
    required int startX, required int startY,
    required int endX, required int endY,
    int durationMs = 200,
  });

  /// Keyboard press/release.
  Future<void> keyPress(String key);
  Future<void> keyRelease(String key);

  /// Type a sequence of keys with delays.
  Future<void> keyType(String text, {int delayMs = 30});

  /// Check if platform supports the current operation.
  bool get isSupported;

  /// Get current screen size.
  Future<({int width, int height})> getScreenSize();

  /// Stream of global key events (for hotkeys).
  Stream<String> get globalKeyEvents;

  /// Register a global hotkey listener.
  void startListening();
  void stopListening();

  /// Callback for native fast clicker stopped event.
  void Function(int count, int generation)? onFastClickerStopped;

  /// Callback for key capture result (from C++ captureKey).
  void Function(String keyName)? onKeyCaptured;

  /// Invoke a platform channel method.
  Future<dynamic> invokeMethod(String method, [dynamic arguments]);

  void dispose();
}
