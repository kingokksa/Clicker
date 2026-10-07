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
      expect(s.humanLikeRandomPause, isTrue);
      expect(s.humanLikePauseChance, 5);
      expect(s.humanLikePauseMinMs, 200);
      expect(s.humanLikePauseMaxMs, 800);
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
        humanLikeRandomPause: false,
        humanLikePauseChance: 12,
        humanLikePauseMinMs: 300,
        humanLikePauseMaxMs: 900,
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
      expect(back.humanLikeRandomPause, isFalse);
      expect(back.humanLikePauseChance, 12);
      expect(back.humanLikePauseMinMs, 300);
      expect(back.humanLikePauseMaxMs, 900);
    });

    test('json 缺字段与未知枚举名回落默认', () {
      final back = ClickSettings.fromJson(const {'mouseButton': 'nope'});
      expect(back.intervalMs, 200);
      expect(back.mouseButton, MouseButton.left);
      expect(back.holdMs, 0);
      expect(back.humanLikeRandomPause, isTrue);
      expect(back.humanLikePauseChance, 5);
    });

    test('copyWith 只改指定字段', () {
      final s = ClickSettings(intervalMs: 120, mouseButton: MouseButton.middle);
      final next = s.copyWith(intervalMs: 900, doubleClick: true);
      expect(next.intervalMs, 900);
      expect(next.doubleClick, isTrue);
      expect(next.mouseButton, MouseButton.middle);
      expect(next.holdMs, s.holdMs);
    });

    test('fromConfig 与 applyTo 往返', () {
      final config = ClickerConfig(
        intervalMs: 250,
        mouseButton: MouseButton.x2,
        clickType: ClickType.single,
        clickHoldMs: 30,
        randomDelayMinMs: 15,
        randomDelayMaxMs: 45,
        randomOffsetEnabled: true,
        randomOffsetMinPx: 3,
        randomOffsetMaxPx: 9,
        humanLikeEnabled: true,
        humanLikeBezierCurve: true,
        humanLikeRandomPause: false,
        humanLikePauseChance: 8,
        humanLikePauseMinMs: 150,
        humanLikePauseMaxMs: 700,
      );
      final settings = ClickSettings.fromConfig(config);
      expect(settings.intervalMs, 250);
      expect(settings.mouseButton, MouseButton.x2);
      expect(settings.doubleClick, isFalse);
      expect(settings.holdMs, 30);
      expect(settings.randomDelayEnabled, isTrue);
      expect(settings.randomDelayMinMs, 15);
      expect(settings.randomDelayMaxMs, 45);
      expect(settings.randomOffsetEnabled, isTrue);
      expect(settings.randomOffsetMinPx, 3);
      expect(settings.randomOffsetMaxPx, 9);
      expect(settings.humanLikeEnabled, isTrue);
      expect(settings.humanLikeBezierCurve, isTrue);
      expect(settings.humanLikeRandomPause, isFalse);
      expect(settings.humanLikePauseChance, 8);
      expect(settings.humanLikePauseMinMs, 150);
      expect(settings.humanLikePauseMaxMs, 700);

      final applied = settings.applyTo(config);
      expect(applied.intervalMs, 250);
      expect(applied.mouseButton, MouseButton.x2);
      expect(applied.clickType, ClickType.single);
      expect(applied.clickHoldMs, 30);
      expect(applied.randomDelayMinMs, 15);
      expect(applied.randomDelayMaxMs, 45);
      expect(applied.randomOffsetEnabled, isTrue);
      expect(applied.randomOffsetMinPx, 3);
      expect(applied.randomOffsetMaxPx, 9);
      expect(applied.humanLikeEnabled, isTrue);
      expect(applied.humanLikeBezierCurve, isTrue);
      expect(applied.humanLikeRandomPause, isFalse);
      expect(applied.humanLikePauseChance, 8);
      expect(applied.humanLikePauseMinMs, 150);
      expect(applied.humanLikePauseMaxMs, 700);
    });

    test('applyTo 不改拖拽扫过序列且关闭随机延迟时归零', () {
      final config = ClickerConfig(
        clickType: ClickType.drag,
        randomDelayMinMs: 20,
        randomDelayMaxMs: 60,
      );
      final settings = ClickSettings.fromConfig(config).copyWith(randomDelayEnabled: false);
      final applied = settings.applyTo(config);
      expect(applied.clickType, ClickType.drag);
      expect(applied.randomDelayMinMs, 0);
      expect(applied.randomDelayMaxMs, 0);
    });
  });
}
