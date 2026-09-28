/// MacroModel / MacroEvent 序列化测试 — 守护宏数据的兼容性。
library;

import 'package:clicker/models/macro_model.dart';
import 'package:flutter_test/flutter_test.dart';

/// 每种事件类型一个样例，key 只用于生成测试名。
final Map<String, MacroEvent> _eventCases = {
  'mouseDown': MacroEvent(
      type: MacroEventType.mouseDown,
      timestampMs: 100,
      button: 'left',
      x: 1,
      y: 2),
  'mouseUp': MacroEvent(
      type: MacroEventType.mouseUp,
      timestampMs: 200,
      button: 'right',
      x: 3,
      y: 4),
  'click': MacroEvent(
      type: MacroEventType.click,
      timestampMs: 300,
      button: 'middle',
      holdMs: 150),
  'keyPress': MacroEvent(
      type: MacroEventType.keyPress,
      timestampMs: 400,
      key: 'a',
      holdMs: 50),
  'keyRelease': MacroEvent(
      type: MacroEventType.keyRelease, timestampMs: 500, key: 'b'),
  'scroll': MacroEvent(
      type: MacroEventType.scroll,
      timestampMs: 600,
      scrollDx: 1.5,
      scrollDy: -3.25),
  'wait': MacroEvent(type: MacroEventType.wait, timestampMs: 700, waitMs: 500),
  'drag': MacroEvent(
      type: MacroEventType.drag,
      timestampMs: 800,
      x: 0,
      y: 0,
      endX: 100,
      endY: 50,
      durationMs: 300),
  'swipe': MacroEvent(
      type: MacroEventType.swipe,
      timestampMs: 900,
      x: 0,
      y: 0,
      endX: 200,
      endY: 100,
      durationMs: 400),
};

void main() {
  group('MacroEvent', () {
    // 每种事件类型一个具名 test：某一类型失败时能直接从测试名看出是哪个，
    // 而不是挤在一个 "all event types" 里靠 reason 猜。
    for (final entry in _eventCases.entries) {
      test('round-trips ${entry.key}', () {
        final event = entry.value;
        final restored = MacroEvent.fromJson(event.toJson());
        expect(restored.type, event.type);
        expect(restored.timestampMs, event.timestampMs);
        expect(restored.holdMs, event.holdMs);
        expect(restored.waitMs, event.waitMs);
        expect(restored.button, event.button);
        expect(restored.x, event.x);
        expect(restored.y, event.y);
        expect(restored.key, event.key);
        expect(restored.scrollDx, event.scrollDx);
        expect(restored.scrollDy, event.scrollDy);
        expect(restored.endX, event.endX);
        expect(restored.endY, event.endY);
        expect(restored.durationMs, event.durationMs);
      });
    }

    test('omits zero/nul value fields from JSON (compact form)', () {
      final event = MacroEvent(type: MacroEventType.click, timestampMs: 0);
      final json = event.toJson();
      expect(json.containsKey('holdMs'), isFalse,
          reason: 'holdMs == 0 should be omitted');
      expect(json.containsKey('waitMs'), isFalse,
          reason: 'waitMs == 0 should be omitted');
      expect(json.containsKey('button'), isFalse);
      expect(json.containsKey('x'), isFalse);
      expect(json.containsKey('y'), isFalse);
      expect(json.containsKey('key'), isFalse);
      expect(json.containsKey('scrollDx'), isFalse);
      expect(json.containsKey('scrollDy'), isFalse);
      expect(json.containsKey('endX'), isFalse);
      expect(json.containsKey('endY'), isFalse);
      expect(json.containsKey('durationMs'), isFalse);
      expect(json['type'], 'click');
      expect(json['timestampMs'], 0);
    });

    test('unknown type throws (no fallback) - protects against corrupt data', () {
      expect(
        () => MacroEvent.fromJson({'type': 'notARealType', 'timestampMs': 0}),
        throwsA(isA<Error>()),
      );
    });

    test('missing optional fields default to null/zero', () {
      final event = MacroEvent.fromJson({'type': 'click', 'timestampMs': 5});
      expect(event.holdMs, 0);
      expect(event.waitMs, 0);
      expect(event.button, isNull);
      expect(event.x, isNull);
      expect(event.y, isNull);
      expect(event.key, isNull);
      expect(event.scrollDx, isNull);
      expect(event.scrollDy, isNull);
      expect(event.endX, isNull);
      expect(event.endY, isNull);
      expect(event.durationMs, isNull);
    });

    test('scrollDx as int is coerced to double', () {
      final event = MacroEvent.fromJson({
        'type': 'scroll',
        'timestampMs': 0,
        'scrollDx': 2,
        'scrollDy': -3,
      });
      expect(event.scrollDx, 2.0);
      expect(event.scrollDy, -3.0);
    });

    test('copyWith preserves fields when not specified', () {
      final event = MacroEvent(
          type: MacroEventType.click, timestampMs: 100, button: 'left', x: 5, y: 6);
      final updated = event.copyWith(timestampMs: 200);
      expect(updated.timestampMs, 200);
      expect(updated.type, MacroEventType.click);
      expect(updated.button, 'left');
      expect(updated.x, 5);
      expect(updated.y, 6);
      expect(event.timestampMs, 100, reason: 'original must not be mutated');
    });

    test('copyWith can clear a nullable field', () {
      final event = MacroEvent(
          type: MacroEventType.click, timestampMs: 0, button: 'left', key: 'a');
      final cleared = event.copyWith(button: null, key: null);
      expect(cleared.button, isNull);
      expect(cleared.key, isNull);
    });
  });

  group('MacroModel', () {
    test('defaults are safe', () {
      final m = MacroModel(id: 'm1');
      expect(m.name, '未命名宏');
      expect(m.events, isEmpty);
      expect(m.repeatCount, 1);
      expect(m.speed, 1.0);
      expect(m.hotkey, isNull);
      expect(m.backgroundMode, isFalse);
      expect(m.backgroundTargetHwnd, 0);
      expect(m.backgroundTargetX, 0);
      expect(m.backgroundTargetY, 0);
      expect(m.backgroundTargetWindowTitle, '');
      expect(m.soundEnabled, isTrue);
      expect(m.enabled, isTrue);
    });

    test('totalDurationMs is the last event timestamp', () {
      final m = MacroModel(id: 'm1', events: const [
        MacroEvent(type: MacroEventType.click, timestampMs: 0),
        MacroEvent(type: MacroEventType.click, timestampMs: 150),
        MacroEvent(type: MacroEventType.click, timestampMs: 900),
      ]);
      expect(m.totalDurationMs, 900);
    });

    test('totalDurationMs is 0 for an empty macro', () {
      expect(MacroModel(id: 'm1').totalDurationMs, 0);
    });

    test('round-trips through toJson/fromJson', () {
      final created = DateTime.utc(2025, 6, 7, 12, 0, 0);
      final original = MacroModel(
        id: 'm42',
        name: 'my macro',
        events: const [
          MacroEvent(type: MacroEventType.keyPress, timestampMs: 0, key: 'a', holdMs: 80),
          MacroEvent(type: MacroEventType.click, timestampMs: 500, button: 'right', waitMs: 200),
        ],
        repeatCount: 3,
        speed: 2.0,
        createdAt: created,
        hotkey: 'Alt+F3',
        backgroundMode: true,
        backgroundTargetHwnd: 456789,
        backgroundTargetX: 12,
        backgroundTargetY: 34,
        backgroundTargetWindowTitle: 'target',
        soundEnabled: false,
        enabled: false,
      );

      final restored = MacroModel.fromJson(original.toJson());

      expect(restored.id, 'm42');
      expect(restored.name, 'my macro');
      expect(restored.events, hasLength(2));
      expect(restored.events[0].key, 'a');
      expect(restored.events[0].holdMs, 80);
      expect(restored.events[1].button, 'right');
      expect(restored.events[1].waitMs, 200);
      expect(restored.repeatCount, 3);
      expect(restored.speed, 2.0);
      expect(restored.createdAt, created);
      expect(restored.hotkey, 'Alt+F3');
      expect(restored.backgroundMode, isTrue);
      expect(restored.backgroundTargetHwnd, 456789);
      expect(restored.backgroundTargetX, 12);
      expect(restored.backgroundTargetY, 34);
      expect(restored.backgroundTargetWindowTitle, 'target');
      expect(restored.soundEnabled, isFalse);
      expect(restored.enabled, isFalse);
    });

    test('round-trips through toJsonString/fromJsonString', () {
      final original = MacroModel(id: 'm1', name: 'string round-trip', repeatCount: 5, speed: 0.5);
      final restored = MacroModel.fromJsonString(original.toJsonString());
      expect(restored.id, 'm1');
      expect(restored.name, 'string round-trip');
      expect(restored.repeatCount, 5);
      expect(restored.speed, 0.5);
    });

    test('omits default booleans from JSON (compact form)', () {
      final json = MacroModel(id: 'm1').toJson();
      // soundEnabled == true and enabled == true are the default, so omitted
      expect(json.containsKey('soundEnabled'), isFalse);
      expect(json.containsKey('enabled'), isFalse);
      expect(json.containsKey('hotkey'), isFalse, reason: 'hotkey is null');
    });

    test('includes non-default booleans in JSON', () {
      final json = MacroModel(id: 'm1', soundEnabled: false, enabled: false).toJson();
      expect(json['soundEnabled'], isFalse);
      expect(json['enabled'], isFalse);
    });

    test('missing fields fall back to defaults on fromJson', () {
      final m = MacroModel.fromJson({'id': 'm1'});
      expect(m.name, '未命名宏');
      expect(m.events, isEmpty);
      expect(m.repeatCount, 1);
      expect(m.speed, 1.0);
      expect(m.backgroundMode, isFalse);
      expect(m.soundEnabled, isTrue);
      expect(m.enabled, isTrue);
    });

    test('speed as int is coerced to double', () {
      final m = MacroModel.fromJson({'id': 'm1', 'speed': 2});
      expect(m.speed, 2.0);
    });

    test('copyWith copies events list (shallow copy, new list)', () {
      final original = MacroModel(id: 'm1', events: const [
        MacroEvent(type: MacroEventType.click, timestampMs: 0),
      ]);
      final updated = original.copyWith(name: 'renamed');
      expect(updated.name, 'renamed');
      expect(updated.events, isNot(same(original.events)));
      expect(updated.events, hasLength(1));
    });

    test('copyWith can clear hotkey', () {
      final m = MacroModel(id: 'm1', hotkey: 'Alt+F3');
      final cleared = m.copyWith(hotkey: null);
      expect(cleared.hotkey, isNull);
    });
  });
}
