import 'package:clicker/models/click_settings.dart';
import 'package:clicker/models/clicker_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ClickSettings', () {
    test('默认值', () {
      final s = ClickSettings();
      expect(s.intervalMs, 200);
      expect(s.mouseButton, MouseButton.left);
      expect(s.doubleClick, isFalse);
      expect(s.holdMs, 0);
      expect(s.randomDelayEnabled, isFalse);
      expect(s.randomOffsetEnabled, isFalse);
      expect(s.humanLikeEnabled, isFalse);
      expect(s.humanLikeBezierCurve, isFalse);
    });

    test('json 往返', () {
      final s = ClickSettings(
        intervalMs: 350,
        mouseButton: MouseButton.right,
        doubleClick: true,
        holdMs: 40,
        randomDelayEnabled: true,
        randomDelayMinMs: 5,
        randomDelayMaxMs: 25,
        randomOffsetEnabled: true,
        randomOffsetMinPx: 2,
        randomOffsetMaxPx: 6,
        humanLikeEnabled: true,
        humanLikeBezierCurve: true,
      );
      final back = ClickSettings.fromJson(s.toJson());
      expect(back.intervalMs, 350);
      expect(back.mouseButton, MouseButton.right);
      expect(back.doubleClick, isTrue);
      expect(back.holdMs, 40);
      expect(back.randomDelayEnabled, isTrue);
      expect(back.randomDelayMinMs, 5);
      expect(back.randomDelayMaxMs, 25);
      expect(back.randomOffsetEnabled, isTrue);
      expect(back.randomOffsetMinPx, 2);
      expect(back.randomOffsetMaxPx, 6);
      expect(back.humanLikeEnabled, isTrue);
      expect(back.humanLikeBezierCurve, isTrue);
    });

    test('json 缺字段与未知枚举名回落默认', () {
      final back = ClickSettings.fromJson(const {'mouseButton': 'nope'});
      expect(back.intervalMs, 200);
      expect(back.mouseButton, MouseButton.left);
      expect(back.holdMs, 0);
    });

    test('copyWith 只改指定字段', () {
      final s = ClickSettings(intervalMs: 120, mouseButton: MouseButton.middle);
      final next = s.copyWith(intervalMs: 900, doubleClick: true);
      expect(next.intervalMs, 900);
      expect(next.doubleClick, isTrue);
      expect(next.mouseButton, MouseButton.middle);
      expect(next.holdMs, s.holdMs);
    });
  });
}
