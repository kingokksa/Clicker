
import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import '../models/clicker_config.dart';
import '../models/macro_model.dart';
import 'platform/platform_input.dart';
import 'platform/windows_input.dart';
import 'platform/android_input.dart';
import 'plugin/plugin_manager.dart';

void _playSystemSound() {
  if (!Platform.isWindows) return;
  final user32 = DynamicLibrary.open('user32.dll');
  final messageBeep = user32.lookupFunction<Int32 Function(Int32), int Function(int)>('MessageBeep');
  messageBeep(0);
}

void _playWavFile(String path) {
  if (!Platform.isWindows) return;
  final winmm = DynamicLibrary.open('winmm.dll');
  final playSound = winmm.lookupFunction<
      Int32 Function(Pointer<Utf16> pszSound, IntPtr hmod, Uint32 fdwSound),
      int Function(Pointer<Utf16> pszSound, int hmod, int fdwSound)
  >('PlaySoundW');
  final pathPtr = path.toNativeUtf16();
  try {
    playSound(pathPtr, 0, 0x00020000 | 0x0001 | 0x0002);
  } finally {
    calloc.free(pathPtr);
  }
}

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
        _playWavFile(path);
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
  final Set<String> _heldKeys = {};
  final Set<String> _heldMouseButtons = {};

  void Function(MacroStatus status)? onStatusChanged;
  void Function(int eventCount)? onRecordingUpdate;
  void Function(int eventIndex, int totalEvents)? onPlaybackProgress;
  void Function(String message)? onError;
  Future<void> Function()? onRecordingStopRequest;

  ClickerConfig? Function()? getConfig;

  MacroService(this._input);

  MacroStatus get status => _status;
  List<MacroEvent> get recordingEvents => List.unmodifiable(_recordingBuffer);
  bool get isRecording => _status == MacroStatus.recording || _status == MacroStatus.paused;
  bool get isPaused => _status == MacroStatus.paused;
  bool get isPlaying => _status == MacroStatus.playing;


  Future<void> startRecording() async {
    if (_status != MacroStatus.idle) return;

    _recordingBuffer.clear();
    _heldKeys.clear();
    _heldMouseButtons.clear();
    _recordStartMs = DateTime.now().millisecondsSinceEpoch;

    _status = MacroStatus.recording;
    onStatusChanged?.call(_status);

    if (_input is WindowsInput) {
      final winInput = _input;
      winInput.onRecordEvent = _handleJournalEvent;
      winInput.onRecordingCancelled = () {
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
        _status = MacroStatus.idle;
        onStatusChanged?.call(_status);
        onError?.call('录制初始化失败，请检查权限');
      }
    } else if (_input is AndroidInput) {
      final andInput = _input;
      andInput.onRecordEvent = _handleAndroidRecordEvent;
      andInput.onStopRecordingRequested = () {
        onRecordingStopRequest?.call();
      };
      await andInput.startRecording();
    }
  }

  void _handleAndroidRecordEvent(Map<String, dynamic> data) {
    if (_status != MacroStatus.recording) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final time = now - _recordStartMs;
    final type = data['type'] as String?;
    switch (type) {
      case 'click':
        _addEvent(MacroEventType.click, time,
            button: 'left', x: data['x'] as int?, y: data['y'] as int?);
        break;
      case 'longPress':
        _recordingBuffer.add(MacroEvent(
          type: MacroEventType.click,
          timestampMs: time,
          button: 'longPress',
          x: data['x'] as int?,
          y: data['y'] as int?,
          holdMs: (data['durationMs'] as int?) ?? 1000,
        ));
        onRecordingUpdate?.call(_recordingBuffer.length);
        break;
      case 'drag':
        _recordingBuffer.add(MacroEvent(
          type: MacroEventType.drag,
          timestampMs: time,
          x: data['startX'] as int?,
          y: data['startY'] as int?,
          endX: data['endX'] as int?,
          endY: data['endY'] as int?,
          durationMs: (data['durationMs'] as int?) ?? 300,
        ));
        onRecordingUpdate?.call(_recordingBuffer.length);
        break;
    }
  }

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
      } else if (msg == WM_XBUTTONDOWN) {
        final mouseData = data['mouseData'] as int? ?? 0;
        final xbtn = (mouseData >> 16) == 2 ? 'x2' : 'x1';
        if (!_heldMouseButtons.contains(xbtn)) {
          _heldMouseButtons.add(xbtn);
          _addEvent(MacroEventType.mouseDown, time, button: xbtn, x: x, y: y);
        }
      } else if (msg == WM_XBUTTONUP) {
        final mouseData = data['mouseData'] as int? ?? 0;
        final xbtn = (mouseData >> 16) == 2 ? 'x2' : 'x1';
        _heldMouseButtons.remove(xbtn);
        _addEvent(MacroEventType.mouseUp, time, button: xbtn, x: x, y: y);
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
  static const int WM_XBUTTONDOWN = 0x020B;
  static const int WM_XBUTTONUP = 0x020C;
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
    if (vk >= 0x41 && vk <= 0x5A) return String.fromCharCode(vk);
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

  void pauseRecording() {
    if (_status != MacroStatus.recording) return;

    if (_input is WindowsInput) {
      final winInput = _input;
      winInput.onRecordEvent = null;
      winInput.onRecordingCancelled = null;
      winInput.stopJournalRecording();
    } else if (_input is AndroidInput) {
      final andInput = _input;
      andInput.onRecordEvent = null;
      andInput.stopRecording();
    }

    final elapsedNow = DateTime.now().millisecondsSinceEpoch - _recordStartMs;
    while (_recordingBuffer.isNotEmpty) {
      final last = _recordingBuffer.last;
      if (elapsedNow - last.timestampMs < 200) {
        _recordingBuffer.removeLast();
      } else {
        break;
      }
    }

    _removeOrphanedPresses();

    onRecordingUpdate?.call(_recordingBuffer.length);
    _status = MacroStatus.paused;
    onStatusChanged?.call(_status);
  }

  void _removeOrphanedPresses() {
    final heldKeySet = <String>{};
    final heldMouseSet = <String>{};

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

    if (heldKeySet.isEmpty && heldMouseSet.isEmpty) return;

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

    if (_input is WindowsInput) {
      final winInput = _input;
      if (winInput.onRecordEvent != null) {
        winInput.onRecordEvent = null;
        winInput.onRecordingCancelled = null;
        winInput.stopJournalRecording();
      }
    } else if (_input is AndroidInput) {
      final andInput = _input;
      if (andInput.onRecordEvent != null) {
        andInput.onRecordEvent = null;
        andInput.stopRecording();
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
    if (_input is WindowsInput) {
      final winInput = _input;
      winInput.onRecordEvent = null;
      winInput.onRecordingCancelled = null;
      winInput.stopJournalRecording();
    } else if (_input is AndroidInput) {
      final andInput = _input;
      andInput.onRecordEvent = null;
      andInput.stopRecording();
    }

    _status = MacroStatus.idle;
    _recordingBuffer.clear();
    _heldKeys.clear();
    _heldMouseButtons.clear();
    onStatusChanged?.call(_status);
  }


  final Set<String> _heldPlaybackKeys = {};
  final Set<String> _heldPlaybackMouseButtons = {};

  Future<void> playMacro(MacroModel macro) async {
    if (_status != MacroStatus.idle) return;

    _currentMacro = macro;
    _status = MacroStatus.playing;
    _heldPlaybackKeys.clear();
    _heldPlaybackMouseButtons.clear();

    final bgEnabled = PluginManager.instance.isEnabled('background_execution');
    if (_input is WindowsInput && macro.backgroundMode && bgEnabled) {
      int hwnd = macro.backgroundTargetHwnd;
      if (hwnd == 0) {
        final config = getConfig?.call();
        if (config != null) {
          hwnd = config.targetHwnd;
        }
      }
      if (hwnd != 0) {
        (_input).setBackgroundMode(true, hwnd: hwnd);
      }
    }

    onStatusChanged?.call(_status);
    _currentRepeat = 0;

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
    final totalRepeats = macro.repeatCount == 0 ? null : macro.repeatCount;

    final clock = Stopwatch()..start();
    int deadlineMs = 0;

    for (_currentRepeat = 0;
        totalRepeats == null || _currentRepeat < totalRepeats;
        _currentRepeat++) {
      if (_status != MacroStatus.playing) break;

      for (int i = 0; i < events.length; i++) {
        if (_status != MacroStatus.playing) break;

        onPlaybackProgress?.call(i + 1, events.length);

        final event = events[i];

        if (i > 0) {
          final prevEvent = events[i - 1];
          int delay;
          if (prevEvent.waitMs > 0) {
            delay = (prevEvent.waitMs * speedMultiplier).round();
          } else {
            delay = ((event.timestampMs - events[i - 1].timestampMs) *
                    speedMultiplier)
                .round();
          }
          deadlineMs += delay;
          deadlineMs += (prevEvent.holdMs / 2 * speedMultiplier).round();
        }

        final remainMs = deadlineMs - clock.elapsedMilliseconds;
        if (remainMs > 0) {
          await Future.delayed(Duration(milliseconds: remainMs));
        } else {
          deadlineMs = clock.elapsedMilliseconds;
        }

        if (_status != MacroStatus.playing) break;

        if (_input is WindowsInput && (_input).isBackgroundMode) {
          if (!(_input).isBackgroundWindowValid()) {
            onError?.call('目标窗口已关闭，宏已停止');
            stopPlayback();
            break;
          }
        }

        await _executeEvent(event);

        if (event.holdMs > 0) {
          deadlineMs += (event.holdMs / 2 * speedMultiplier).round();
        }

        if (_status != MacroStatus.playing) break;
      }
    }

    stopPlayback();
  }

  Future<void> _executeEvent(MacroEvent event) async {
    final isMobile = Platform.isAndroid || Platform.isIOS;
    switch (event.type) {
      case MacroEventType.mouseDown:
        final btn = event.button ?? 'left';
        if (isMobile && btn == 'longPress') {
          await _input.touchLongPress(
            x: event.x ?? -1,
            y: event.y ?? -1,
            durationMs: event.holdMs > 0 ? event.holdMs : 1000,
          );
        } else {
          _heldPlaybackMouseButtons.add(btn);
          await _input.mouseDown(
            x: event.x ?? -1,
            y: event.y ?? -1,
            button: btn,
          );
        }
        break;

      case MacroEventType.mouseUp:
        final btn = event.button ?? 'left';
        if (isMobile && btn == 'longPress') {
        } else {
          _heldPlaybackMouseButtons.remove(btn);
          await _input.mouseUp(
            x: event.x ?? -1,
            y: event.y ?? -1,
            button: btn,
          );
        }
        break;

      case MacroEventType.click:
        final btn = event.button ?? 'left';
        if (isMobile && btn == 'longPress') {
          await _input.touchLongPress(
            x: event.x ?? -1,
            y: event.y ?? -1,
            durationMs: event.holdMs > 0 ? event.holdMs : 1000,
          );
        } else {
          await _input.mouseClick(
            x: event.x ?? -1,
            y: event.y ?? -1,
            button: btn,
            holdMs: event.holdMs,
          );
        }
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

      case MacroEventType.drag:
        await _input.mouseDrag(
          startX: event.x ?? 0, startY: event.y ?? 0,
          endX: event.endX ?? 0, endY: event.endY ?? 0,
          durationMs: event.durationMs ?? 300,
        );
        break;

      case MacroEventType.swipe:
        await _input.mouseSwipe(
          startX: event.x ?? 0, startY: event.y ?? 0,
          endX: event.endX ?? 0, endY: event.endY ?? 0,
          durationMs: event.durationMs ?? 200,
        );
        break;

      case MacroEventType.wait:
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
    if (_input is WindowsInput) {
      (_input).setBackgroundMode(false);
    }
    if (wasPlaying) {
      _releaseAllKeys();
      if (macro?.soundEnabled ?? false) {
        final config = getConfig?.call();
        if (config != null && config.soundFeedbackEnabled) {
          _playMacroSound(config.soundFeedbackMacro, isStart: false);
        }
      }
      onStatusChanged?.call(_status);
    }
  }

  void _releaseAllKeys() {
    for (final key in _heldPlaybackKeys.toList()) {
      _input.keyRelease(key);
    }
    _heldPlaybackKeys.clear();
    const safetyKeys = [
      'Shift', 'Ctrl', 'Alt', 'Win',
      'Enter', 'Space', 'Tab', 'Escape', 'Backspace', 'Delete',
    ];
    for (final key in safetyKeys) {
      _input.keyRelease(key);
    }
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
