/// Macro service -- recording and playback of mouse/keyboard sequences.
/// Uses WH_JOURNALRECORD hook on Windows for real input capture.
library;

import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import '../models/clicker_config.dart';
import '../models/macro_model.dart';
import 'platform/platform_input.dart';
import 'platform/windows_input.dart';
import 'plugin_registry.dart';
import 'package:audioplayers/audioplayers.dart';

/// Play a system sound via Win32 MessageBeep
void _playSystemSound() {
  if (!Platform.isWindows) return;
  final user32 = DynamicLibrary.open('user32.dll');
  final messageBeep = user32.lookupFunction<Int32 Function(Int32), int Function(int)>('MessageBeep');
  messageBeep(0);
}

/// Shared audio player for macro sounds
final AudioPlayer _macroAudioPlayer = AudioPlayer();

/// Play a sound based on SoundConfig
Future<void> _playMacroSound(SoundConfig config, {required bool isStart}) async {
  final enabled = isStart ? config.startEnabled : config.endEnabled;
  if (!enabled) return;
  final path = isStart ? config.startPath : config.endPath;
  if (path.isEmpty) {
    _playSystemSound();
  } else {
    try {
      final file = File(path);
      if (await file.exists()) {
        await _macroAudioPlayer.play(DeviceFileSource(path));
      } else {
        _playSystemSound();
      }
    } catch (_) {
      _playSystemSound();
    }
  }
}

enum MacroStatus { idle, recording, paused, playing }

class MacroService {
  final PlatformInput _input;

  MacroStatus _status = MacroStatus.idle;
  final List<MacroEvent> _recordingBuffer = [];
  int _recordStartMs = 0;
  Timer? _playbackTimer;

  MacroModel? _currentMacro;
  int _currentRepeat = 0;
  final Set<String> _heldKeys = {}; // Track currently held keys to avoid repeat
  final Set<String> _heldMouseButtons = {}; // Track held mouse buttons

  void Function(MacroStatus status)? onStatusChanged;
  void Function(int eventCount)? onRecordingUpdate;
  void Function(int eventIndex, int totalEvents)? onPlaybackProgress;
  void Function(String message)? onError;

  /// Callback to get current clicker config (for background mode fallback target)
  ClickerConfig? Function()? getConfig;

  MacroService(this._input);

  MacroStatus get status => _status;
  List<MacroEvent> get recordingEvents => List.unmodifiable(_recordingBuffer);
  bool get isRecording => _status == MacroStatus.recording || _status == MacroStatus.paused;
  bool get isPaused => _status == MacroStatus.paused;
  bool get isPlaying => _status == MacroStatus.playing;

  // ─── Recording ─────────────────────────────────────────────

  Future<void> startRecording() async {
    if (_status != MacroStatus.idle) return;

    _recordingBuffer.clear();
    _heldKeys.clear();
    _heldMouseButtons.clear();
    _recordStartMs = DateTime.now().millisecondsSinceEpoch;

    // Set status immediately so UI updates
    _status = MacroStatus.recording;
    onStatusChanged?.call(_status);

    // Use WindowsInput journal recording hook if available.
    if (_input is WindowsInput) {
      final winInput = _input;
      winInput.onRecordEvent = _handleJournalEvent;
      winInput.onRecordingCancelled = () {
        // Low-level hooks are stable and shouldn't be cancelled by the system,
        // but keep this handler as a safety net.
        if (_status == MacroStatus.recording && _recordingBuffer.isNotEmpty) {
          stopRecording(name: '录制中断的宏');
          onError?.call('录制被系统中断，已自动保存已捕获的事件');
        } else {
          cancelRecording();
          onError?.call('录制被系统中断');
        }
      };
      final success = await winInput.startJournalRecording();
      if (!success) {
        // Roll back status on failure
        _status = MacroStatus.idle;
        onStatusChanged?.call(_status);
        onError?.call('录制初始化失败，请检查权限');
      }
    }
  }

  /// Handle events from low-level keyboard/mouse hooks.
  void _handleJournalEvent(Map<String, dynamic> data) {
    if (_status != MacroStatus.recording) return;

    final time = data['time'] as int? ?? 0;
    final source = data['source'] as String? ?? '';

    if (source == 'keyboard') {
      final msg = data['message'] as int? ?? 0;
      final vk = data['vk'] as int? ?? 0;
      final keyName = _vkToKeyName(vk);
      if (keyName == null) return;

      if (msg == WM_KEYDOWN || msg == WM_SYSKEYDOWN) {
        // Ignore auto-repeat when key is held down
        if (_heldKeys.contains(keyName)) return;
        _heldKeys.add(keyName);
        _addEvent(MacroEventType.keyPress, time, key: keyName);
      } else if (msg == WM_KEYUP || msg == WM_SYSKEYUP) {
        _heldKeys.remove(keyName);
        _addEvent(MacroEventType.keyRelease, time, key: keyName);
      }
    } else if (source == 'mouse') {
      final msg = data['message'] as int? ?? 0;
      final x = data['x'] as int? ?? 0;
      final y = data['y'] as int? ?? 0;

      if (msg == WM_LBUTTONDOWN) {
        if (!_heldMouseButtons.contains('left')) {
          _heldMouseButtons.add('left');
          _addEvent(MacroEventType.mouseDown, time, button: 'left', x: x, y: y);
        }
      } else if (msg == WM_LBUTTONUP) {
        _heldMouseButtons.remove('left');
        _addEvent(MacroEventType.mouseUp, time, button: 'left', x: x, y: y);
      } else if (msg == WM_RBUTTONDOWN) {
        if (!_heldMouseButtons.contains('right')) {
          _heldMouseButtons.add('right');
          _addEvent(MacroEventType.mouseDown, time, button: 'right', x: x, y: y);
        }
      } else if (msg == WM_RBUTTONUP) {
        _heldMouseButtons.remove('right');
        _addEvent(MacroEventType.mouseUp, time, button: 'right', x: x, y: y);
      } else if (msg == WM_MBUTTONDOWN) {
        if (!_heldMouseButtons.contains('middle')) {
          _heldMouseButtons.add('middle');
          _addEvent(MacroEventType.mouseDown, time, button: 'middle', x: x, y: y);
        }
      } else if (msg == WM_MBUTTONUP) {
        _heldMouseButtons.remove('middle');
        _addEvent(MacroEventType.mouseUp, time, button: 'middle', x: x, y: y);
      } else if (msg == WM_MOUSEWHEEL) {
        final mouseData = data['mouseData'] as int? ?? 0;
        final delta = mouseData >> 16;
        final dy = delta > 32767 ? (delta - 65536) / 120.0 : delta / 120.0;
        _addEvent(MacroEventType.scroll, time, scrollDx: 0, scrollDy: dy);
      }
    }
  }

  static const int WM_KEYDOWN = 0x0100;
  static const int WM_KEYUP = 0x0101;
  static const int WM_SYSKEYDOWN = 0x0104;
  static const int WM_SYSKEYUP = 0x0105;
  static const int WM_LBUTTONDOWN = 0x0201;
  static const int WM_LBUTTONUP = 0x0202;
  static const int WM_RBUTTONDOWN = 0x0204;
  static const int WM_RBUTTONUP = 0x0205;
  static const int WM_MBUTTONDOWN = 0x0207;
  static const int WM_MBUTTONUP = 0x0208;
  static const int WM_MOUSEWHEEL = 0x020A;

  void _addEvent(MacroEventType type, int timestampMs, {String? button, int? x, int? y, String? key, double? scrollDx, double? scrollDy}) {
    _recordingBuffer.add(MacroEvent(
      type: type,
      timestampMs: timestampMs,
      button: button,
      x: x,
      y: y,
      key: key,
      scrollDx: scrollDx,
      scrollDy: scrollDy,
    ));
    onRecordingUpdate?.call(_recordingBuffer.length);
  }

  /// Convert virtual key code to a readable key name.
  String? _vkToKeyName(int vk) {
    const vkMap = <int, String>{
      0x08: 'Backspace', 0x09: 'Tab', 0x0D: 'Enter', 0x1B: 'Escape',
      0x10: 'Shift', 0x11: 'Ctrl', 0x12: 'Alt',
      0x20: 'Space', 0x21: 'PageUp', 0x22: 'PageDown', 0x23: 'End',
      0x24: 'Home', 0x25: 'Left', 0x26: 'Up', 0x27: 'Right', 0x28: 'Down',
      0x2D: 'Insert', 0x2E: 'Delete',
      0x70: 'F1', 0x71: 'F2', 0x72: 'F3', 0x73: 'F4',
      0x74: 'F5', 0x75: 'F6', 0x76: 'F7', 0x77: 'F8',
      0x78: 'F9', 0x79: 'F10', 0x7A: 'F11', 0x7B: 'F12',
    };
    if (vkMap.containsKey(vk)) return vkMap[vk];
    // Letters A-Z
    if (vk >= 0x41 && vk <= 0x5A) return String.fromCharCode(vk);
    // Digits 0-9
    if (vk >= 0x30 && vk <= 0x39) return String.fromCharCode(vk);
    return null;
  }

  void recordEvent({
    required MacroEventType type,
    String? button,
    int? x,
    int? y,
    String? key,
    double? scrollDx,
    double? scrollDy,
  }) {
    if (_status != MacroStatus.recording) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    _recordingBuffer.add(MacroEvent(
      type: type,
      timestampMs: now - _recordStartMs,
      button: button,
      x: x,
      y: y,
      key: key,
      scrollDx: scrollDx,
      scrollDy: scrollDy,
    ));
    onRecordingUpdate?.call(_recordingBuffer.length);
  }

  /// Pause recording — stops the hook immediately but keeps the buffer.
  /// Discards the last few events that were likely triggered by clicking
  /// the stop button itself.
  void pauseRecording() {
    if (_status != MacroStatus.recording) return;

    // Stop hooks immediately so no more events are captured
    if (_input is WindowsInput) {
      final winInput = _input;
      winInput.onRecordEvent = null;
      winInput.onRecordingCancelled = null;
      winInput.stopJournalRecording();
    }

    // Remove trailing events that were likely from clicking the stop button
    // or pressing the stop hotkey. Remove events within 200ms of now.
    final elapsedNow = DateTime.now().millisecondsSinceEpoch - _recordStartMs;
    while (_recordingBuffer.isNotEmpty) {
      final last = _recordingBuffer.last;
      if (elapsedNow - last.timestampMs < 200) {
        _recordingBuffer.removeLast();
      } else {
        break;
      }
    }

    // Remove orphaned keyPress/mouseDown events that have no matching release.
    // When the user presses a hotkey to stop recording, the keydown is captured
    // but the keyup is not (because the hook was already stopped).
    // Playing back these orphaned presses causes stuck keys and system shortcuts.
    _removeOrphanedPresses();

    onRecordingUpdate?.call(_recordingBuffer.length);
    _status = MacroStatus.paused;
    onStatusChanged?.call(_status);
  }

  /// Remove keyPress/mouseDown events that have no matching keyRelease/mouseUp.
  void _removeOrphanedPresses() {
    final heldKeySet = <String>{};
    final heldMouseSet = <String>{};

    // First pass: find which keys/buttons are held at the end
    for (final event in _recordingBuffer) {
      if (event.type == MacroEventType.keyPress && event.key != null) {
        heldKeySet.add(event.key!);
      } else if (event.type == MacroEventType.keyRelease && event.key != null) {
        heldKeySet.remove(event.key!);
      } else if (event.type == MacroEventType.mouseDown && event.button != null) {
        heldMouseSet.add(event.button!);
      } else if (event.type == MacroEventType.mouseUp && event.button != null) {
        heldMouseSet.remove(event.button!);
      }
    }

    // If no orphans, nothing to do
    if (heldKeySet.isEmpty && heldMouseSet.isEmpty) return;

    // Second pass: remove the orphaned press events (from the end, since they're likely last)
    _recordingBuffer.removeWhere((event) {
      if (event.type == MacroEventType.keyPress && event.key != null && heldKeySet.contains(event.key!)) {
        return true;
      }
      if (event.type == MacroEventType.mouseDown && event.button != null && heldMouseSet.contains(event.button!)) {
        return true;
      }
      return false;
    });
  }

  MacroModel stopRecording({String name = 'Recorded Macro'}) {
    if (_status != MacroStatus.recording && _status != MacroStatus.paused) {
      throw StateError('Not recording');
    }

    // Stop journal hook if not already paused.
    if (_input is WindowsInput) {
      final winInput = _input;
      if (winInput.onRecordEvent != null) {
        winInput.onRecordEvent = null;
        winInput.onRecordingCancelled = null;
        winInput.stopJournalRecording();
      }
    }

    _status = MacroStatus.idle;
    onStatusChanged?.call(_status);

    final macro = MacroModel(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      events: List.from(_recordingBuffer),
    );
    _recordingBuffer.clear();
    _heldKeys.clear();
    _heldMouseButtons.clear();
    return macro;
  }

  void cancelRecording() {
    // Stop journal hook if using WindowsInput.
    if (_input is WindowsInput) {
      final winInput = _input;
      winInput.onRecordEvent = null;
      winInput.onRecordingCancelled = null;
      winInput.stopJournalRecording();
    }

    _status = MacroStatus.idle;
    _recordingBuffer.clear();
    _heldKeys.clear();
    _heldMouseButtons.clear();
    onStatusChanged?.call(_status);
  }

  // ─── Playback ──────────────────────────────────────────────

  // Track keys held during playback for cleanup
  final Set<String> _heldPlaybackKeys = {};
  final Set<String> _heldPlaybackMouseButtons = {};

  Future<void> playMacro(MacroModel macro) async {
    if (_status != MacroStatus.idle) return;

    _currentMacro = macro;
    _status = MacroStatus.playing;
    _heldPlaybackKeys.clear();
    _heldPlaybackMouseButtons.clear();

    // Set background mode on WindowsInput if macro has background mode enabled and plugin is available
    final bgPlugin = PluginRegistry.instance.getPlugin('background_execution');
    final bgPluginAvailable = bgPlugin != null && bgPlugin.installed && bgPlugin.enabled;
    if (_input is WindowsInput && macro.backgroundMode && bgPluginAvailable) {
      int hwnd = macro.backgroundTargetHwnd;
      // Fallback to plugin config if macro has no target set
      if (hwnd == 0) {
        final config = getConfig?.call();
        if (config != null) {
          hwnd = config.targetHwnd;
        }
      }
      if (hwnd != 0) {
        // For macros, only set hwnd — coordinates come from each event
        (_input as WindowsInput).setBackgroundMode(true, hwnd: hwnd);
      }
    }

    onStatusChanged?.call(_status);
    _currentRepeat = 0;

    // Play macro start sound
    if (macro.soundEnabled) {
      final config = getConfig?.call();
      if (config != null && config.soundFeedbackEnabled) {
        _playMacroSound(config.soundFeedbackMacro, isStart: true);
      }
    }

    await _executePlayback();
  }

  Future<void> _executePlayback() async {
    if (_status != MacroStatus.playing || _currentMacro == null) return;

    final macro = _currentMacro!;
    final events = macro.events;
    final speedMultiplier = 1.0 / macro.speed;

    for (_currentRepeat = 0;
        _currentRepeat < (macro.repeatCount == 0 ? 1 : macro.repeatCount);
        _currentRepeat++) {
      if (_status != MacroStatus.playing) break;

      for (int i = 0; i < events.length; i++) {
        if (_status != MacroStatus.playing) break;

        onPlaybackProgress?.call(i + 1, events.length);

        final event = events[i];

        // Calculate delay from previous event
        if (i > 0) {
          final prevEvent = events[i - 1];
          // Use waitMs from previous event if set, otherwise fall back to timestampMs difference
          int delay;
          if (prevEvent.waitMs > 0) {
            delay = (prevEvent.waitMs * speedMultiplier).round();
          } else {
            delay = ((event.timestampMs - events[i - 1].timestampMs) *
                    speedMultiplier)
                .round();
          }
          if (delay > 0) {
            await Future.delayed(Duration(milliseconds: delay));
          }
        }

        if (_status != MacroStatus.playing) break;

        // Check if background target window still exists
        if (_input is WindowsInput && (_input as WindowsInput).isBackgroundMode) {
          if (!(_input as WindowsInput).isBackgroundWindowValid()) {
            onError?.call('目标窗口已关闭，宏已停止');
            stopPlayback();
            break;
          }
        }

        // Execute event with hold duration
        await _executeEvent(event);

        // Hold duration: wait after executing, before the next step's delay
        if (event.holdMs > 0) {
          final holdDelay = (event.holdMs * speedMultiplier).round();
          if (holdDelay > 0) {
            await Future.delayed(Duration(milliseconds: holdDelay));
          }
        }
      }
    }

    stopPlayback();
  }

  Future<void> _executeEvent(MacroEvent event) async {
    switch (event.type) {
      case MacroEventType.mouseDown:
        final btn = event.button ?? 'left';
        _heldPlaybackMouseButtons.add(btn);
        await _input.mouseDown(
          x: event.x ?? -1,
          y: event.y ?? -1,
          button: btn,
        );
        break;

      case MacroEventType.mouseUp:
        final btn = event.button ?? 'left';
        _heldPlaybackMouseButtons.remove(btn);
        await _input.mouseUp(
          x: event.x ?? -1,
          y: event.y ?? -1,
          button: btn,
        );
        break;

      case MacroEventType.click:
        await _input.mouseClick(
          x: event.x ?? -1,
          y: event.y ?? -1,
          button: event.button ?? 'left',
        );
        break;

      case MacroEventType.keyPress:
        if (event.key != null) {
          _heldPlaybackKeys.add(event.key!);
          await _input.keyPress(event.key!);
        }
        break;

      case MacroEventType.keyRelease:
        if (event.key != null) {
          _heldPlaybackKeys.remove(event.key!);
          await _input.keyRelease(event.key!);
        }
        break;

      case MacroEventType.scroll:
        await _input.mouseScroll(
          dx: event.scrollDx ?? 0,
          dy: event.scrollDy ?? 0,
        );
        break;

      case MacroEventType.wait:
        // Wait events are handled by timestamp calculation above
        break;
    }
  }

  void stopPlayback() {
    _playbackTimer?.cancel();
    _playbackTimer = null;
    final macro = _currentMacro;
    _currentMacro = null;
    _currentRepeat = 0;
    final wasPlaying = _status == MacroStatus.playing;
    _status = MacroStatus.idle;
    // Restore foreground mode on WindowsInput
    if (_input is WindowsInput) {
      (_input as WindowsInput).setBackgroundMode(false);
    }
    if (wasPlaying) {
      // Release all keys that may be stuck after playback
      _releaseAllKeys();
      // Play macro end sound
      if (macro?.soundEnabled ?? false) {
        final config = getConfig?.call();
        if (config != null && config.soundFeedbackEnabled) {
          _playMacroSound(config.soundFeedbackMacro, isStart: false);
        }
      }
      onStatusChanged?.call(_status);
    }
  }

  /// Release all keys that are still held after playback, plus common modifier keys.
  void _releaseAllKeys() {
    // Release keys tracked as held during playback
    for (final key in _heldPlaybackKeys.toList()) {
      _input.keyRelease(key);
    }
    _heldPlaybackKeys.clear();
    // Also release common modifier keys as a safety net
    const safetyKeys = [
      'Shift', 'Ctrl', 'Alt', 'Win',
      'Enter', 'Space', 'Tab', 'Escape', 'Backspace', 'Delete',
    ];
    for (final key in safetyKeys) {
      _input.keyRelease(key);
    }
    // Only release mouse buttons that were actually pressed during playback
    for (final btn in _heldPlaybackMouseButtons.toList()) {
      _input.mouseUp(x: -1, y: -1, button: btn);
    }
    _heldPlaybackMouseButtons.clear();
  }

  void dispose() {
    stopPlayback();
    cancelRecording();
  }
}
