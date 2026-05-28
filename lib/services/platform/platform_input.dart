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

  /// Scroll wheel.
  Future<void> mouseScroll({double dx = 0, double dy = 0});

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
