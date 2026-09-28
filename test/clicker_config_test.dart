/// ClickerConfig JSON 序列化/反序列化测试 — 守护用户配置兼容性。
library;

import 'package:clicker/models/clicker_config.dart';
import 'package:flutter_test/flutter_test.dart';

/// 构造一个「每个自定义字段都被设过」的配置，供 round-trip 断言复用。
ClickerConfig _buildFullConfig() => ClickerConfig(
      clickMode: ClickMode.keyboard,
      clickType: ClickType.double,
      mouseButton: MouseButton.right,
      positionMode: PositionMode.fixed,
      fixedX: 1234,
      fixedY: 567,
      intervalMs: 0.5,
      repeatMode: ClickRepeatMode.count,
      repeatCount: 42,
      durationSeconds: 300,
      keyToRepeat: 'a',
      holdKey: true,
      keyActionMode: KeyActionMode.text,
      textToType: 'hello world',
      textTypeDelayMs: 120,
      randomDelayMinMs: 10,
      randomDelayMaxMs: 30,
      jitterEnabled: true,
      jitterMinMs: 2,
      jitterMaxMs: 40,
      randomOffsetEnabled: true,
      randomOffsetMinPx: 3,
      randomOffsetMaxPx: 15,
      holdTriggerEnabled: true,
      holdTriggerKey: 'F9',
      humanLikeEnabled: true,
      humanLikeBezierCurve: true,
      humanLikePauseChance: 20,
      humanLikePauseMinMs: 100,
      humanLikePauseMaxMs: 500,
      soundFeedbackEnabled: true,
    );

void main() {
  group('ClickerConfig defaults', () {
    test('has safe defaults', () {
      final c = ClickerConfig();
      expect(c.clickMode, ClickMode.mouse);
      expect(c.clickType, ClickType.single);
      expect(c.mouseButton, MouseButton.left);
      expect(c.positionMode, PositionMode.current);
      expect(c.intervalMs, 100);
      expect(c.repeatMode, ClickRepeatMode.infinite);
      expect(c.repeatCount, 100);
      expect(c.durationSeconds, 60);
      expect(c.keyToRepeat, 'space');
      expect(c.keyActionMode, KeyActionMode.repeat);
      expect(c.touchAction, TouchAction.tap);
      expect(c.longPressDurationMs, 500);
      expect(c.swipeDurationMs, 300);
      expect(c.textTypeDelayMs, 50);
      expect(c.randomDelayMinMs, 0);
      expect(c.randomDelayMaxMs, 0);
      expect(c.jitterEnabled, isFalse);
      expect(c.jitterMinMs, 5);
      expect(c.jitterMaxMs, 30);
      expect(c.randomOffsetEnabled, isFalse);
      expect(c.randomOffsetMinPx, 1);
      expect(c.randomOffsetMaxPx, 5);
      expect(c.holdTriggerEnabled, isFalse);
      expect(c.holdTriggerKey, 'F5');
      expect(c.humanLikePauseChance, 5);
      expect(c.humanLikePauseMinMs, 200);
      expect(c.humanLikePauseMaxMs, 800);
      expect(c.autoClickEnabled, isTrue);
      expect(c.humanLikeEnabled, isFalse);
      expect(c.soundFeedbackEnabled, isFalse);
      expect(c.statsEnabled, isTrue);
    });
  });

  group('ClickerConfig JSON round-trip', () {
    test('defaults survive a round-trip', () {
      final original = ClickerConfig();
      final restored = ClickerConfig.fromJson(original.toJson());
      expect(restored.intervalMs, original.intervalMs);
      expect(restored.clickMode, original.clickMode);
      expect(restored.clickType, original.clickType);
      expect(restored.mouseButton, original.mouseButton);
      expect(restored.keyToRepeat, original.keyToRepeat);
    });

    // 按字段分组断言：某个字段回归时能直接从测试名定位，
    // 而不是挤在一个 30+ 断言的大测试里逐行排查。
    late ClickerConfig restored;
    setUp(() {
      restored = ClickerConfig.fromJson(_buildFullConfig().toJson());
    });

    test('click mode and position fields survive', () {
      expect(restored.clickMode, ClickMode.keyboard);
      expect(restored.clickType, ClickType.double);
      expect(restored.mouseButton, MouseButton.right);
      expect(restored.positionMode, PositionMode.fixed);
      expect(restored.fixedX, 1234);
      expect(restored.fixedY, 567);
      expect(restored.intervalMs, closeTo(0.5, 1e-9));
    });

    test('repeat fields survive', () {
      expect(restored.repeatMode, ClickRepeatMode.count);
      expect(restored.repeatCount, 42);
      expect(restored.durationSeconds, 300);
    });

    test('keyboard and text fields survive', () {
      expect(restored.keyToRepeat, 'a');
      expect(restored.holdKey, isTrue);
      expect(restored.keyActionMode, KeyActionMode.text);
      expect(restored.textToType, 'hello world');
      expect(restored.textTypeDelayMs, 120);
    });

    test('randomization fields survive', () {
      expect(restored.randomDelayMinMs, 10);
      expect(restored.randomDelayMaxMs, 30);
      expect(restored.jitterEnabled, isTrue);
      expect(restored.jitterMinMs, 2);
      expect(restored.jitterMaxMs, 40);
      expect(restored.randomOffsetEnabled, isTrue);
      expect(restored.randomOffsetMinPx, 3);
      expect(restored.randomOffsetMaxPx, 15);
    });

    test('hold-trigger and human-like fields survive', () {
      expect(restored.holdTriggerEnabled, isTrue);
      expect(restored.holdTriggerKey, 'F9');
      expect(restored.humanLikeEnabled, isTrue);
      expect(restored.humanLikeBezierCurve, isTrue);
      expect(restored.humanLikePauseChance, 20);
      expect(restored.humanLikePauseMinMs, 100);
      expect(restored.humanLikePauseMaxMs, 500);
    });

    test('sound field survives', () {
      expect(restored.soundFeedbackEnabled, isTrue);
    });

    test('keySequence and mouseSequence survive a round-trip', () {
      final original = ClickerConfig(
        keySequence: const [
          KeySequenceItem(key: 'a', delayMs: 30),
          KeySequenceItem(key: 'b', delayMs: 500),
        ],
        mouseSequence: const [
          MouseActionItem(
              action: MouseActionType.click, button: MouseButton.right, delayMs: 10),
          MouseActionItem(action: MouseActionType.press, delayMs: 5),
          MouseActionItem(
              action: MouseActionType.release, button: MouseButton.right, delayMs: 0),
        ],
      );
      final restored = ClickerConfig.fromJson(original.toJson());

      expect(restored.keySequence, hasLength(2));
      expect(restored.keySequence[0].key, 'a');
      expect(restored.keySequence[0].delayMs, 30);
      expect(restored.keySequence[1].key, 'b');
      expect(restored.keySequence[1].delayMs, 500);

      expect(restored.mouseSequence, hasLength(3));
      expect(restored.mouseSequence[0].action, MouseActionType.click);
      expect(restored.mouseSequence[0].button, MouseButton.right);
      expect(restored.mouseSequence[1].action, MouseActionType.press);
      expect(restored.mouseSequence[2].action, MouseActionType.release);
    });
  });

  group('ClickerConfig copyWith', () {
    test('overwrites only the specified field', () {
      final c = ClickerConfig(intervalMs: 100, keyToRepeat: 'space');
      final updated = c.copyWith(intervalMs: 250);
      expect(updated.intervalMs, 250);
      expect(updated.keyToRepeat, 'space');
      // original is not mutated
      expect(c.intervalMs, 100);
    });

    test('clamps intervalMs to at least 1.0', () {
      final c = ClickerConfig(intervalMs: 100);
      final updated = c.copyWith(intervalMs: 0);
      expect(updated.intervalMs, 1.0);
    });
  });

  group('ClickerSchedule legacy migration', () {
    test('new schedules list is parsed', () {
      final json = {
        'schedules': [
          {'enabled': true, 'action': 'startClick', 'hour': 8, 'minute': 30},
        ],
      };
      final c = ClickerConfig.fromJson(json);
      expect(c.schedules, hasLength(1));
      expect(c.schedules[0].enabled, isTrue);
      expect(c.schedules[0].action, ScheduleAction.startClick);
      expect(c.schedules[0].hour, 8);
      expect(c.schedules[0].minute, 30);
    });

    test('legacy startSchedule/stopSchedule slots migrate to the list', () {
      final json = {
        'startSchedule': {'enabled': true, 'hour': 9},
        'stopSchedule': {'enabled': true, 'hour': 17},
      };
      final c = ClickerConfig.fromJson(json);
      expect(c.schedules, hasLength(2));
      expect(c.schedules[0].action, ScheduleAction.startClick);
      expect(c.schedules[1].action, ScheduleAction.stopClick);
      expect(c.schedules[0].hour, 9);
      expect(c.schedules[1].hour, 17);
    });

    test('new list takes precedence over legacy slots when both are present', () {
      final json = {
        'schedules': [
          {'enabled': true, 'action': 'playMacro', 'macroId': 'm1'},
        ],
        'startSchedule': {'enabled': false},
      };
      final c = ClickerConfig.fromJson(json);
      expect(c.schedules, hasLength(1));
      expect(c.schedules[0].action, ScheduleAction.playMacro);
      expect(c.schedules[0].macroId, 'm1');
    });

    test('schedule id round-trips', () {
      final s = ClickerSchedule(
          id: 'abc123', enabled: true, hour: 12, minute: 0);
      final restored =
          ClickerSchedule.fromJson(s.toJson());
      expect(restored.id, 'abc123');
      expect(restored.enabled, isTrue);
    });

    test('schedule with fireAtEpochMs == 0 omits the field', () {
      final s = ClickerSchedule(id: 'x');
      final json = s.toJson();
      expect(json.containsKey('fireAtEpochMs'), isFalse);
    });

    test('schedule with fireAtEpochMs != 0 includes the field', () {
      final s = ClickerSchedule(id: 'x', fireAtEpochMs: 1700000000000);
      final json = s.toJson();
      expect(json['fireAtEpochMs'], 1700000000000);
    });
  });

  group('ClickerConfig enum fallback', () {
    test('unknown enum strings fall back to defaults', () {
      final c = ClickerConfig.fromJson({
        'clickMode': 'unknown',
        'clickType': 'nonsense',
        'mouseButton': 'bad',
        'repeatMode': 'nope',
        'keyActionMode': 'bad',
      });
      expect(c.clickMode, ClickMode.mouse);
      expect(c.clickType, ClickType.single);
      expect(c.mouseButton, MouseButton.left);
      expect(c.repeatMode, ClickRepeatMode.infinite);
      expect(c.keyActionMode, KeyActionMode.repeat);
    });

    test('intervalMs as int is coerced to double', () {
      final c = ClickerConfig.fromJson({'intervalMs': 250});
      expect(c.intervalMs, 250.0);
    });

    test('intervalMs = 0 is NOT clamped on fromJson (documents current behavior)', () {
      // fromJson (lib/models/clicker_config.dart:466) 不做 clamp，只有 copyWith 才 clamp 到 1.0。
      // 这意味着 corrupt 配置里 intervalMs=0 会原样透传——潜在除零风险。
      // 如果生产代码日后补上 clamp，此测试应改为 expect(c.intervalMs, 1.0)。
      final c = ClickerConfig.fromJson({'intervalMs': 0});
      expect(c.intervalMs, 0.0);
    });

    test('intervalMs = negative is NOT clamped on fromJson (documents current behavior)', () {
      final c = ClickerConfig.fromJson({'intervalMs': -5});
      expect(c.intervalMs, -5.0);
    });

    test('missing keys fall back to defaults', () {
      final c = ClickerConfig.fromJson({});
      expect(c.intervalMs, 100);
      expect(c.keyToRepeat, 'space');
      expect(c.schedules, isEmpty);
    });
  });

  group('SoundConfig', () {
    test('empty paths are omitted from JSON', () {
      final s = SoundConfig(startEnabled: true);
      final json = s.toJson();
      expect(json.containsKey('startPath'), isFalse);
      expect(json.containsKey('endPath'), isFalse);
      expect(json['startEnabled'], isTrue);
      expect(json['endEnabled'], isFalse);
    });

    test('paths are preserved through a round-trip', () {
      final s = SoundConfig(
          startEnabled: true, endEnabled: true, startPath: 'C:/a.wav', endPath: 'C:/b.wav');
      final restored = SoundConfig.fromJson(s.toJson());
      expect(restored.startPath, 'C:/a.wav');
      expect(restored.endPath, 'C:/b.wav');
      expect(restored.startEnabled, isTrue);
      expect(restored.endEnabled, isTrue);
    });

    test('enabled getter', () {
      expect(SoundConfig(startEnabled: false, endEnabled: false).enabled, isFalse);
      expect(SoundConfig(startEnabled: true, endEnabled: false).enabled, isTrue);
      expect(SoundConfig(startEnabled: false, endEnabled: true).enabled, isTrue);
    });
  });
}
