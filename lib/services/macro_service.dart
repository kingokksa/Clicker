/// Macro service -- recording and playback of mouse/keyboard sequences.
/// Uses WH_JOURNALRECORD hook on Windows for real input capture.
library;

import 'dart:async';
import '../models/macro_model.dart';
import 'platform/platform_input.dart';
import 'platform/windows_input.dart';

enum MacroStatus { idle, recording, playing }

class MacroService {
  final PlatformInput _input;

  MacroStatus _status = MacroStatus.idle;
  final List<MacroEvent> _recordingBuffer = [];
  int _recordStartMs = 0;
  Timer? _playbackTimer;

  MacroModel? _currentMacro;
  int _currentRepeat = 0;

  void Function(MacroStatus status)? onStatusChanged;
  void Function(int eventCount)? onRecordingUpdate;
  void Function(int eventIndex, int totalEvents)? onPlaybackProgress;
  void Function(String message)? onError;

  MacroService(this._input);

  MacroStatus get status => _status;
  List<MacroEvent> get recordingEvents => List.unmodifiable(_recordingBuffer);
  bool get isRecording => _status == MacroStatus.recording;
  bool get isPlaying => _status == MacroStatus.playing;

  // ─── Recording ─────────────────────────────────────────────

  Future<void> startRecording() async {
    if (_status != MacroStatus.idle) return;

    _recordingBuffer.clear();
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
        _addEvent(MacroEventType.keyPress, time, key: keyName);
      } else if (msg == WM_KEYUP || msg == WM_SYSKEYUP) {
        _addEvent(MacroEventType.keyRelease, time, key: keyName);
      }
    } else if (source == 'mouse') {
      final msg = data['message'] as int? ?? 0;
      final x = data['x'] as int? ?? 0;
      final y = data['y'] as int? ?? 0;

      if (msg == WM_LBUTTONDOWN) {
        _addEvent(MacroEventType.click, time, button: 'left', x: x, y: y);
      } else if (msg == WM_RBUTTONDOWN) {
        _addEvent(MacroEventType.click, time, button: 'right', x: x, y: y);
      } else if (msg == WM_MBUTTONDOWN) {
        _addEvent(MacroEventType.click, time, button: 'middle', x: x, y: y);
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
  static const int WM_RBUTTONDOWN = 0x0204;
  static const int WM_MBUTTONDOWN = 0x0207;
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

    // Remove trailing click/key events that were likely from clicking the
    // stop button. Remove events within 500ms of now.
    final elapsedNow = DateTime.now().millisecondsSinceEpoch - _recordStartMs;
    while (_recordingBuffer.isNotEmpty) {
      final last = _recordingBuffer.last;
      if (elapsedNow - last.timestampMs < 500) {
        _recordingBuffer.removeLast();
      } else {
        break;
      }
    }

    onRecordingUpdate?.call(_recordingBuffer.length);
    // Keep status as recording so UI knows we have pending data
    // but no more events will come in.
  }

  MacroModel stopRecording({String name = 'Recorded Macro'}) {
    if (_status != MacroStatus.recording) {
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
    onStatusChanged?.call(_status);
  }

  // ─── Playback ──────────────────────────────────────────────

  Future<void> playMacro(MacroModel macro) async {
    if (_status != MacroStatus.idle) return;

    _currentMacro = macro;
    _status = MacroStatus.playing;
    onStatusChanged?.call(_status);
    _currentRepeat = 0;

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
          final delay = ((event.timestampMs - events[i - 1].timestampMs) *
                  speedMultiplier)
              .round();
          if (delay > 0) {
            await Future.delayed(Duration(milliseconds: delay));
          }
        }

        if (_status != MacroStatus.playing) break;

        // Execute event
        await _executeEvent(event);
      }
    }

    stopPlayback();
  }

  Future<void> _executeEvent(MacroEvent event) async {
    switch (event.type) {
      case MacroEventType.click:
        await _input.mouseClick(
          x: event.x ?? -1,
          y: event.y ?? -1,
          button: event.button ?? 'left',
        );
        break;

      case MacroEventType.keyPress:
        if (event.key != null) {
          await _input.keyPress(event.key!);
        }
        break;

      case MacroEventType.keyRelease:
        if (event.key != null) {
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
    _currentMacro = null;
    _currentRepeat = 0;
    final wasPlaying = _status == MacroStatus.playing;
    _status = MacroStatus.idle;
    if (wasPlaying) {
      onStatusChanged?.call(_status);
    }
  }

  void dispose() {
    stopPlayback();
    cancelRecording();
  }
}
