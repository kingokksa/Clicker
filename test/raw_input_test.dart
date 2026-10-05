import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:clicker/models/clicker_config.dart';
import 'package:clicker/services/raw_input_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.clicker.pro/rawinput');

  void platformCall(String method, [Object? args]) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(MethodCall(method, args)),
      (_) {},
    );
  }

  group('RawInputService', () {
    test('forwards raw mouse moves', () async {
      final events = <(int, int)>[];
      final sub = RawInputService.instance.mouseMoves.listen(events.add);
      platformCall('onRawMouseMove', {'dx': 7, 'dy': -4, 'buttons': 0});
      await Future<void>.delayed(Duration.zero);
      expect(events, [(7, -4)]);
      await sub.cancel();
    });

    test('forwards raw key events', () async {
      final keys = <(int, bool)>[];
      RawInputService.instance.onRawKey = (vk, down) => keys.add((vk, down));
      platformCall('onRawKey', {'vk': 65, 'down': true, 'scan': 30});
      platformCall('onRawKey', {'vk': 65, 'down': false, 'scan': 30});
      await Future<void>.delayed(Duration.zero);
      expect(keys, [(65, true), (65, false)]);
      RawInputService.instance.onRawKey = null;
    });

    test('forwards user input notifications', () async {
      final seen = <String>[];
      RawInputService.instance.onUserInput = (kind, vk, message, delta) {
        seen.add('$kind:$vk:$message:$delta');
      };
      platformCall('onUserInput', {'kind': 'keyboard', 'vk': 9, 'down': true});
      platformCall('onUserInput', {'kind': 'mouse', 'message': 512, 'dx': 12});
      await Future<void>.delayed(Duration.zero);
      expect(seen, ['keyboard:9:0:0', 'mouse:0:512:12']);
      RawInputService.instance.onUserInput = null;
    });

    test('tolerates malformed payloads', () async {
      final seen = <String>[];
      RawInputService.instance.onUserInput = (kind, vk, message, delta) {
        seen.add('$kind:$vk:$message:$delta');
      };
      platformCall('onRawMouseMove');
      platformCall('onRawKey', <Object?>[]);
      platformCall('onUserInput', {'kind': 5});
      await Future<void>.delayed(Duration.zero);
      expect(seen, [':0:0:0']);
      RawInputService.instance.onUserInput = null;
    });

    test('round trips monitor and raw input toggles', () async {
      final calls = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        calls.add('${call.method}:${call.arguments}');
        final args = call.arguments as List<Object?>;
        return args.first as bool;
      });

      expect(await RawInputService.instance.setUserInputMonitor(true), isTrue);
      expect(RawInputService.instance.monitoring, isTrue);
      expect(await RawInputService.instance.setRawInputEnabled(true), isTrue);
      expect(RawInputService.instance.rawInputEnabled, isTrue);
      expect(calls, ['setUserInputMonitor:[true]', 'setRawInputEnabled:[true]']);

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('reports unavailable when the platform call fails', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        throw PlatformException(code: 'RAW_INPUT_FAILED');
      });
      expect(await RawInputService.instance.setUserInputMonitor(true), isFalse);
      expect(RawInputService.instance.monitoring, isFalse);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });
  });

  group('ClickerConfig user intervention', () {
    test('defaults are off with pause mode', () {
      final config = ClickerConfig();
      expect(config.userInterventionEnabled, isFalse);
      expect(config.userInterventionStop, isFalse);
      expect(config.userInterventionResumeMs, 1500);
    });

    test('survives a json round trip', () {
      final config = ClickerConfig(
        userInterventionEnabled: true,
        userInterventionStop: true,
        userInterventionResumeMs: 800,
      );
      final restored = ClickerConfig.fromJson(config.toJson());
      expect(restored.userInterventionEnabled, isTrue);
      expect(restored.userInterventionStop, isTrue);
      expect(restored.userInterventionResumeMs, 800);
    });

    test('copyWith updates individual fields', () {
      final config = ClickerConfig();
      final updated = config.copyWith(
        userInterventionEnabled: true,
        userInterventionResumeMs: 2500,
      );
      expect(updated.userInterventionEnabled, isTrue);
      expect(updated.userInterventionStop, isFalse);
      expect(updated.userInterventionResumeMs, 2500);
    });
  });
}
