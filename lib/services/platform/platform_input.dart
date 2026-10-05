
import 'dart:async';

abstract class PlatformInput {
  Future<void> mouseClick({
    required int x,
    required int y,
    String button = 'left',
    bool doubleClick = false,
    int holdMs = 0,
  });

  void syncClick({required int x, required int y, String button = 'left'});

  Future<void> mouseMove(int x, int y);

  Future<void> mouseMoveBy(int dx, int dy) async {}

  Future<void> mouseDown({required int x, required int y, String button = 'left'});
  Future<void> mouseUp({required int x, required int y, String button = 'left'});

  Future<void> mouseDrag({
    required int startX, required int startY,
    required int endX, required int endY,
    int durationMs = 300,
  }) async {
    await mouseDown(x: startX, y: startY);
    final steps = (durationMs / 16).ceil().clamp(1, 100);
    final dx = (endX - startX) / steps;
    final dy = (endY - startY) / steps;
    for (int i = 1; i <= steps; i++) {
      await mouseMove((startX + dx * i).round(), (startY + dy * i).round());
      if (i < steps) await Future.delayed(Duration(milliseconds: (durationMs / steps).round()));
    }
    await mouseUp(x: endX, y: endY);
  }

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

  Future<void> mouseScroll({double dx = 0, double dy = 0});

  Future<void> touchLongPress({required int x, required int y, int durationMs = 500});

  Future<void> touchDrag({
    required int startX, required int startY,
    required int endX, required int endY,
    int durationMs = 300,
  });

  Future<void> touchSwipe({
    required int startX, required int startY,
    required int endX, required int endY,
    int durationMs = 200,
  });

  Future<void> keyPress(String key);
  Future<void> keyRelease(String key);

  Future<void> keyType(String text, {int delayMs = 30});

  bool get isSupported;

  Future<({int width, int height})> getScreenSize();

  Stream<String> get globalKeyEvents;

  void startListening();
  void stopListening();

  void Function(int count, int generation)? onFastClickerStopped;

  void Function(String keyName)? onKeyCaptured;

  Future<dynamic> invokeMethod(String method, [dynamic arguments]);

  void dispose();
}
