/// Hotkey service — maps global key events to app actions.
/// Uses RegisterHotKey on Windows for system-level priority,
/// uses volume button combo on Android.
library;

import 'dart:async';
import 'dart:io';
import '../models/hotkey_config.dart';
import 'platform/platform_input.dart';
import 'platform/windows_input.dart';

class HotkeyService {
  final PlatformInput _input;
  HotkeyConfig _config = HotkeyConfig();
  StreamSubscription<String>? _subscription;

  // Hold-trigger state
  bool _holdTriggerActive = false;
  Timer? _holdTriggerPollTimer;

  // Action callbacks
  void Function()? onStartStopClicker;
  void Function()? onStartStopRecording;
  void Function()? onEmergencyStop;
  void Function()? onPlayMacro;
  void Function()? onHoldTriggerStart;
  void Function()? onHoldTriggerStop;
  void Function()? onStopImmediate; // Called from C++ for instant stop

  HotkeyService(this._input);

  HotkeyConfig get config => _config;

  void updateConfig(HotkeyConfig config) {
    _config = config;
    _registerSystemHotkeys();
  }

  void start() {
    _subscription?.cancel();
    _subscription = _input.globalKeyEvents.listen(_handleKeyEvent);
    _input.startListening();
    _registerSystemHotkeys();
  }

  /// Register all hotkeys at the system level (Windows only).
  Future<void> _registerSystemHotkeys() async {
    if (!Platform.isWindows) return;
    final winInput = _input as WindowsInput;

    await winInput.registerHotkey('startStopClicker', _config.startStopClicker);
    await winInput.registerHotkey(
        'startStopRecording', _config.startStopRecording);
    await winInput.registerHotkey('emergencyStop', _config.emergencyStop);
    await winInput.registerHotkey('playMacro', _config.playMacro);
    await winInput.registerHotkey('holdTrigger', _config.holdTrigger);
  }

  void _handleKeyEvent(String field) {
    switch (field) {
      case '__stop_immediate__':
        // C++ requested immediate stop — bypass toggle, just stop
        onStopImmediate?.call();
        break;
      case 'startStopClicker':
        onStartStopClicker?.call();
        break;
      case 'startStopRecording':
        onStartStopRecording?.call();
        break;
      case 'emergencyStop':
        onEmergencyStop?.call();
        break;
      case 'playMacro':
        onPlayMacro?.call();
        break;
      case 'holdTrigger':
        _handleHoldTrigger();
        break;
    }
  }

  /// Hold-trigger: when the hotkey fires, start clicking and poll key state.
  /// When the key is released, stop clicking.
  void _handleHoldTrigger() {
    if (_holdTriggerActive) return; // Already active, ignore repeat
    _holdTriggerActive = true;
    onHoldTriggerStart?.call();

    // Poll the physical key state to detect release
    _holdTriggerPollTimer?.cancel();
    _holdTriggerPollTimer = Timer.periodic(const Duration(milliseconds: 50), (_) async {
      if (!Platform.isWindows) return;
      final winInput = _input as WindowsInput;
      final stillHeld = await winInput.isHotkeyStillHeld(_config.holdTrigger);
      if (!stillHeld) {
        _holdTriggerActive = false;
        _holdTriggerPollTimer?.cancel();
        _holdTriggerPollTimer = null;
        onHoldTriggerStop?.call();
      }
    });
  }

  void stop() {
    _subscription?.cancel();
    _subscription = null;
    _holdTriggerPollTimer?.cancel();
    _holdTriggerPollTimer = null;
    _holdTriggerActive = false;
    _input.stopListening();
  }

  void dispose() {
    stop();
  }
}
