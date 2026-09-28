/// HoldTriggerKey / HotkeyConfig 模型测试。
library;

import 'package:clicker/models/hold_trigger_key.dart';
import 'package:clicker/models/hotkey_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('HoldTriggerKey', () {
    test('defaults are safe', () {
      final k = HoldTriggerKey(id: 'k1');
      expect(k.triggerKey, 'F5');
      expect(k.triggerType, HoldTriggerType.keyboard);
      expect(k.triggerMouseButton, 'left');
      expect(k.enabled, isTrue);
      expect(k.action, HoldTriggerAction.mouseClick);
      expect(k.mouseButton, 'left');
      expect(k.keyToRepeat, 'space');
      expect(k.comboKeys, isEmpty);
      expect(k.intervalMs, 50);
      expect(k.backgroundMode, isFalse);
      expect(k.targetHwnd, 0);
      expect(k.targetX, 0);
      expect(k.targetY, 0);
      expect(k.targetWindowTitle, '');
    });

    test('generates a non-empty id when omitted', () {
      final k = HoldTriggerKey();
      expect(k.id, isNotEmpty);
      // Two instances get distinct ids
      expect(HoldTriggerKey().id, isNot(HoldTriggerKey().id));
    });

    test('round-trips through toJson/fromJson', () {
      final original = HoldTriggerKey(
        id: 'k42',
        triggerKey: 'F8',
        triggerType: HoldTriggerType.mouse,
        triggerMouseButton: 'right',
        enabled: false,
        action: HoldTriggerAction.keyCombo,
        mouseButton: 'middle',
        keyToRepeat: 'a',
        comboKeys: ['ctrl', 'shift', 'a'],
        intervalMs: 120,
        backgroundMode: true,
        targetHwnd: 12345,
        targetX: 7,
        targetY: 9,
        targetWindowTitle: 'target',
      );

      final restored = HoldTriggerKey.fromJson(original.toJson());

      expect(restored.id, 'k42');
      expect(restored.triggerKey, 'F8');
      expect(restored.triggerType, HoldTriggerType.mouse);
      expect(restored.triggerMouseButton, 'right');
      expect(restored.enabled, isFalse);
      expect(restored.action, HoldTriggerAction.keyCombo);
      expect(restored.mouseButton, 'middle');
      expect(restored.keyToRepeat, 'a');
      expect(restored.comboKeys, ['ctrl', 'shift', 'a']);
      expect(restored.intervalMs, 120);
      expect(restored.backgroundMode, isTrue);
      expect(restored.targetHwnd, 12345);
      expect(restored.targetX, 7);
      expect(restored.targetY, 9);
      expect(restored.targetWindowTitle, 'target');
    });

    test('missing fields fall back to defaults', () {
      final k = HoldTriggerKey.fromJson({'id': 'k1'});
      expect(k.triggerKey, 'F5');
      expect(k.triggerType, HoldTriggerType.keyboard);
      expect(k.enabled, isTrue);
      expect(k.action, HoldTriggerAction.mouseClick);
      expect(k.intervalMs, 50);
      expect(k.backgroundMode, isFalse);
    });

    test('unknown enum values fall back to defaults', () {
      final k = HoldTriggerKey.fromJson({
        'id': 'k1',
        'triggerType': 'bogus',
        'action': 'notReal',
      });
      expect(k.triggerType, HoldTriggerType.keyboard);
      expect(k.action, HoldTriggerAction.mouseClick);
    });

    test('intervalMs as int is coerced to double', () {
      final k = HoldTriggerKey.fromJson({'id': 'k1', 'intervalMs': 25});
      expect(k.intervalMs, 25.0);
    });

    test('comboKeys with non-string entries throws (defensive against corrupt data)', () {
      expect(
        () => HoldTriggerKey.fromJson({
          'id': 'k1',
          'comboKeys': ['ctrl', 7],
        }),
        throwsA(isA<TypeError>()),
        reason: 'non-string comboKeys entries must be rejected, not silently accepted',
      );
    });

    test('copyWith preserves fields when not specified', () {
      final k = HoldTriggerKey(id: 'k1', triggerKey: 'F5', intervalMs: 50);
      final updated = k.copyWith(triggerKey: 'F6');
      expect(updated.triggerKey, 'F6');
      expect(updated.intervalMs, 50);
      expect(updated.id, 'k1');
      expect(k.triggerKey, 'F5', reason: 'original must not be mutated');
    });

    test('copyWith clamps intervalMs to a minimum of 10ms', () {
      final k = HoldTriggerKey(id: 'k1');
      final updated = k.copyWith(intervalMs: 1);
      expect(updated.intervalMs, 10);
    });

    test('copyWith keeps intervalMs above the clamp threshold', () {
      final k = HoldTriggerKey(id: 'k1');
      final updated = k.copyWith(intervalMs: 200);
      expect(updated.intervalMs, 200);
    });

    test('copyWith replaces comboKeys list', () {
      final k = HoldTriggerKey(id: 'k1', comboKeys: const ['ctrl', 'a']);
      final updated = k.copyWith(comboKeys: const ['alt']);
      expect(updated.comboKeys, ['alt']);
      expect(k.comboKeys, ['ctrl', 'a'], reason: 'original must not be mutated');
    });
  });

  group('HotkeyConfig', () {
    test('defaults match the documented bindings', () {
      final h = HotkeyConfig();
      expect(h.startStopClicker, 'Alt+F6');
      expect(h.startStopRecording, 'Alt+F8');
      expect(h.emergencyStop, 'Alt+F12');
      expect(h.playMacro, 'Alt+F9');
      expect(h.holdTrigger, 'F5');
      expect(h.backgroundClick, 'Alt+F7');
    });

    test('round-trips through toJson/fromJson', () {
      final original = HotkeyConfig(
        startStopClicker: 'Ctrl+Shift+Space',
        startStopRecording: 'Alt+F1',
        emergencyStop: 'F12',
        playMacro: 'Alt+F2',
        holdTrigger: 'F3',
        backgroundClick: 'Ctrl+F4',
      );
      final restored = HotkeyConfig.fromJson(original.toJson());
      expect(restored.startStopClicker, 'Ctrl+Shift+Space');
      expect(restored.startStopRecording, 'Alt+F1');
      expect(restored.emergencyStop, 'F12');
      expect(restored.playMacro, 'Alt+F2');
      expect(restored.holdTrigger, 'F3');
      expect(restored.backgroundClick, 'Ctrl+F4');
    });

    test('missing fields fall back to defaults', () {
      final h = HotkeyConfig.fromJson({});
      expect(h.startStopClicker, 'Alt+F6');
      expect(h.holdTrigger, 'F5');
    });

    test('copyWith preserves fields when not specified', () {
      final h = HotkeyConfig();
      final updated = h.copyWith(startStopClicker: 'Ctrl+Alt+F6');
      expect(updated.startStopClicker, 'Ctrl+Alt+F6');
      expect(updated.startStopRecording, 'Alt+F8');
      expect(h.startStopClicker, 'Alt+F6');
    });

    test('parseHotkey returns no modifiers and the vk for a bare key', () {
      final r = HotkeyConfig.parseHotkey('F6');
      expect(r.modifiers, 0);
      expect(r.vk, 0x75);
    });

    test('parseHotkey accumulates modifier flags', () {
      final r = HotkeyConfig.parseHotkey('Ctrl+Shift+F12');
      expect(r.modifiers & 0x0002, 0x0002, reason: 'MOD_CONTROL');
      expect(r.modifiers & 0x0004, 0x0004, reason: 'MOD_SHIFT');
      expect(r.modifiers & 0x0001, 0, reason: 'no ALT');
      expect(r.vk, 0x7B);
    });

    test('parseHotkey maps "win"/"super" to MOD_WIN', () {
      final r = HotkeyConfig.parseHotkey('Win+Space');
      expect(r.modifiers & 0x0008, 0x0008);
    });

    test('parseHotkey is case-insensitive for modifiers', () {
      final r = HotkeyConfig.parseHotkey('ALT+f6');
      expect(r.modifiers & 0x0001, 0x0001);
      expect(r.vk, 0x75);
    });

    test('parseHotkey maps letter keys via ASCII code (uppercased)', () {
      // _keyToVk uppercases the key, so 'a' maps to 'A' -> 0x41 (uppercase ASCII)
      expect(HotkeyConfig.parseHotkey('a').vk, 0x41);
      expect(HotkeyConfig.parseHotkey('Z').vk, 0x5A);
    });

    test('parseHotkey maps digit and special keys', () {
      expect(HotkeyConfig.parseHotkey('5').vk, 0x35);
      expect(HotkeyConfig.parseHotkey('Space').vk, 0x20);
      expect(HotkeyConfig.parseHotkey('Enter').vk, 0x0D);
      expect(HotkeyConfig.parseHotkey('Escape').vk, 0x1B);
      expect(HotkeyConfig.parseHotkey('Delete').vk, 0x2E);
      expect(HotkeyConfig.parseHotkey('Up').vk, 0x26);
    });

    test('parseHotkey returns 0 vk for unrecognized keys', () {
      expect(HotkeyConfig.parseHotkey('CapsLock').vk, 0);
      expect(HotkeyConfig.parseHotkey('PrtSc').vk, 0);
    });

    test('buildHotkey with no modifiers returns just the key', () {
      expect(HotkeyConfig.buildHotkey([], 'F6'), 'F6');
    });

    test('buildHotkey joins modifiers with +', () {
      expect(HotkeyConfig.buildHotkey(['Ctrl', 'Shift'], 'F12'), 'Ctrl+Shift+F12');
    });

    test('splitHotkey extracts modifiers and the key', () {
      final r = HotkeyConfig.splitHotkey('Ctrl+Shift+F12');
      expect(r.mods, ['Ctrl', 'Shift']);
      expect(r.key, 'F12');
    });

    test('splitHotkey on a bare key yields empty modifiers', () {
      final r = HotkeyConfig.splitHotkey('F6');
      expect(r.mods, isEmpty);
      expect(r.key, 'F6');
    });

    test('buildHotkey and splitHotkey are inverses', () {
      final original = 'Alt+Ctrl+F5';
      final r = HotkeyConfig.splitHotkey(original);
      expect(HotkeyConfig.buildHotkey(r.mods, r.key), original);
    });

    test('fieldToId and idToField are inverses for all fields', () {
      for (final field in [
        'startStopClicker',
        'startStopRecording',
        'emergencyStop',
        'playMacro',
        'holdTrigger',
        'backgroundClick',
      ]) {
        final id = HotkeyConfig.fieldToId(field);
        expect(id, greaterThan(0), reason: 'field $field must map to a positive id');
        expect(HotkeyConfig.idToField(id), field);
      }
    });

    test('fieldToId returns 0 for unknown fields', () {
      expect(HotkeyConfig.fieldToId('notAField'), 0);
      expect(HotkeyConfig.idToField(0), '');
      expect(HotkeyConfig.idToField(99), '');
    });
  });
}
