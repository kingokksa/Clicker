/// Click engine service — runs auto-clicking in an isolate-like thread.
/// Supports both mouse and keyboard click modes with advanced features.
/// Fast mouse clicking uses a native Win32 thread for maximum speed
/// without blocking the Dart event loop.
library;

import 'dart:async';
import 'dart:math';
import 'package:flutter/services.dart';
import '../models/clicker_config.dart';
import 'platform/platform_input.dart';

enum ClickerStatus { idle, running, paused }

class ClickService {
  final PlatformInput _input;
  ClickerConfig _config = ClickerConfig();
  ClickerStatus _status = ClickerStatus.idle;

  int _clickCount = 0;
  int _targetCount = 0;
  Timer? _timer;
  Timer? _uiUpdateTimer;
  DateTime? _startTime;
  Duration? _durationLimit;
  final Random _random = Random();
  int _nativeGeneration = 0;

  // Native fast clicker channel
  static const _platformChannel = MethodChannel('com.clicker.pro/platform');
  bool _usingNativeClicker = false;

  static void _log(String msg) {
    print('[ClickService] $msg');
  }

  // Callbacks
  void Function(ClickerStatus status, int count)? onStatusChanged;
  void Function(String message)? onError;

  ClickService(this._input);

  ClickerStatus get status => _status;
  ClickerConfig get config => _config;
  int get clickCount => _clickCount;
  bool get isRunning => _status == ClickerStatus.running;

  /// Called from AppState when the native clicker thread reports it stopped.
  void handleNativeClickerStopped(int count, {int? generation}) {
    if (generation != null && generation != _nativeGeneration) {
      _log('ignoring stale onFastClickerStopped (gen=$generation, current=$_nativeGeneration)');
      return;
    }
    _clickCount = count;
    _usingNativeClicker = false;
    _timer?.cancel();
    _timer = null;
    _uiUpdateTimer?.cancel();
    _uiUpdateTimer = null;
    if (_status == ClickerStatus.running) {
      _status = ClickerStatus.idle;
      onStatusChanged?.call(_status, _clickCount);
    }
  }

  Future<int> _fetchNativeClickCount() async {
    try {
      final count = await _platformChannel.invokeMethod<int>('getClickCount');
      return count ?? _clickCount;
    } on PlatformException {
      return _clickCount;
    }
  }

  void updateConfig(ClickerConfig config) {
    _config = config;
  }

  Future<void> start() async {
    if (_status == ClickerStatus.running) return;
    if (!_config.autoClickEnabled) {
      onError?.call('自动连点功能未启用，请在功能管理中开启');
      return;
    }

    _clickCount = 0;
    _startTime = DateTime.now();

    switch (_config.repeatMode) {
      case ClickRepeatMode.count:
        _targetCount = _config.repeatCount;
        break;
      case ClickRepeatMode.duration:
        _targetCount = -1;
        _durationLimit = Duration(seconds: _config.durationSeconds);
        break;
      case ClickRepeatMode.infinite:
        _targetCount = -1;
        break;
    }

    _status = ClickerStatus.running;
    _startUiUpdateTimer();
    onStatusChanged?.call(_status, _clickCount);
    _log('start: interval=${_config.intervalMs}ms, mode=${_config.clickMode.name}, repeat=${_config.repeatMode.name}');

    _scheduleClick();
  }

  void _startUiUpdateTimer() {
    _uiUpdateTimer?.cancel();
    _uiUpdateTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (_status == ClickerStatus.running) {
        if (_usingNativeClicker) {
          _fetchNativeClickCount().then((count) {
            _clickCount = count;
          });
        }
        onStatusChanged?.call(_status, _clickCount);
      }
    });
  }

  void _scheduleClick() {
    if (_status != ClickerStatus.running) return;

    final baseUs = (_config.intervalMs * 1000).round();

    if (baseUs <= 50000) {
      _log('using native fast clicker (base=${baseUs}us)');
      _startNativeFastClicker();
      return;
    }

    final delayUs = _getDelayUs();
    _log('using Dart timer mode (delay=${delayUs}us)');

    _timer = Timer(Duration(microseconds: delayUs), () async {
      if (_status != ClickerStatus.running) return;
      try {
        await _performAction();
      } catch (e) {
        _log('action error: $e');
      }
      // stop() may have been called inside _performAction (e.g. text mode)
      if (_status != ClickerStatus.running) return;
      _clickCount++;
      if (_shouldStop()) { stop(); return; }
      _scheduleClick();
    });
  }

  /// Start native fast clicker via platform channel.
  /// Runs on a separate Win32 thread — does NOT block Dart event loop.
  /// Supports both mouse and keyboard modes. Minimum interval: 10ms.
  void _startNativeFastClicker() {
    _usingNativeClicker = true;
    _nativeGeneration++;
    final myGen = _nativeGeneration;
    _log('starting native clicker, dart gen=$myGen');
    int x = _config.positionMode == PositionMode.fixed ? _config.fixedX : -1;
    int y = _config.positionMode == PositionMode.fixed ? _config.fixedY : -1;
    int button = _config.mouseButton == MouseButton.right ? 1
        : (_config.mouseButton == MouseButton.middle ? 2 : 0);
    int targetCount = _targetCount > 0 ? _targetCount : -1;
    int intervalUs = (_config.intervalMs * 1000).round();
    if (intervalUs < 10000) intervalUs = 10000;

    try {
      final bgMode = _config.backgroundExecutionEnabled;
      final hwnd = _config.targetHwnd;
      final cx = _config.targetClientX;
      final cy = _config.targetClientY;

      final isKeyboard = _config.clickMode == ClickMode.keyboard;
      int keyVk = 0;
      int keyActionMode = 0;
      List<int> comboKeys = [];

      if (isKeyboard) {
        keyVk = _keyToVk(_config.keyToRepeat);
        switch (_config.keyActionMode) {
          case KeyActionMode.repeat:
            keyActionMode = 0;
            break;
          case KeyActionMode.hold:
            keyActionMode = 1;
            break;
          case KeyActionMode.combo:
            keyActionMode = 2;
            comboKeys = _config.comboKeys.map((k) => _keyToVk(k)).toList();
            break;
          default:
            keyActionMode = 0;
        }
      }

      _platformChannel.invokeMethod<int>('startFastClicker', [
        intervalUs, x, y, button, targetCount,
        bgMode, hwnd, cx, cy,
        isKeyboard, keyVk, keyActionMode,
        ...comboKeys,
        myGen,
      ]).then((gen) {
        _log('native clicker started, cpp gen=$gen');
      });
    } on PlatformException catch (e) {
      _usingNativeClicker = false;
      onError?.call('原生点击器启动失败: ${e.message}');
      stop();
    }
  }

  /// Convert a key name string to a Windows virtual key code.
  static int _keyToVk(String key) {
    const vkMap = <String, int>{
      'enter': 0x0D, 'tab': 0x09, 'escape': 0x1B, 'backspace': 0x08,
      'space': 0x20, 'left': 0x25, 'right': 0x27, 'up': 0x26, 'down': 0x28,
      'shift': 0x10, 'ctrl': 0x11, 'alt': 0x12, 'delete': 0x2E, 'insert': 0x2D,
      'home': 0x24, 'end': 0x23, 'pageup': 0x21, 'pagedown': 0x22,
      'printscreen': 0x2C, 'scrolllock': 0x91, 'pause': 0x13,
      'capslock': 0x14, 'numlock': 0x90, 'win': 0x5B, 'apps': 0x5D,
      'f1': 0x70, 'f2': 0x71, 'f3': 0x72, 'f4': 0x73, 'f5': 0x74,
      'f6': 0x75, 'f7': 0x76, 'f8': 0x77, 'f9': 0x78, 'f10': 0x79,
      'f11': 0x7A, 'f12': 0x7B, 'f13': 0x7C, 'f14': 0x7D, 'f15': 0x7E,
      'f16': 0x7F, 'f17': 0x80, 'f18': 0x81, 'f19': 0x82, 'f20': 0x83,
      'f21': 0x84, 'f22': 0x85, 'f23': 0x86, 'f24': 0x87,
      '0': 0x30, '1': 0x31, '2': 0x32, '3': 0x33, '4': 0x34,
      '5': 0x35, '6': 0x36, '7': 0x37, '8': 0x38, '9': 0x39,
      'a': 0x41, 'b': 0x42, 'c': 0x43, 'd': 0x44, 'e': 0x45,
      'f': 0x46, 'g': 0x47, 'h': 0x48, 'i': 0x49, 'j': 0x4A,
      'k': 0x4B, 'l': 0x4C, 'm': 0x4D, 'n': 0x4E, 'o': 0x4F,
      'p': 0x50, 'q': 0x51, 'r': 0x52, 's': 0x53, 't': 0x54,
      'u': 0x55, 'v': 0x56, 'w': 0x57, 'x': 0x58, 'y': 0x59, 'z': 0x5A,
      'multiply': 0x6A, 'add': 0x6B, 'subtract': 0x6D,
      'decimal': 0x6E, 'divide': 0x6F,
    };
    final lower = key.toLowerCase();
    if (vkMap.containsKey(lower)) return vkMap[lower]!;
    // Single character: use its uppercase code point as VK
    if (key.length == 1) return key.toUpperCase().codeUnitAt(0);
    return 0;
  }

  int _getDelayUs() {
    final baseUs = (_config.intervalMs * 1000).round();

    // Smart delay: add human-like random variation
    if (_config.smartDelayEnabled) {
      final variation = (baseUs * 0.3).round();
      return baseUs + _random.nextInt(variation * 2 + 1) - variation;
    }

    // Human-like mode: more pronounced variation with occasional pauses
    if (_config.humanLikeEnabled) {
      final variation = (baseUs * 0.4).round();
      final delay = baseUs + _random.nextInt(variation * 2 + 1) - variation;
      if (_random.nextInt(100) < 5) {
        return delay + baseUs + _random.nextInt(baseUs * 2);
      }
      return delay;
    }

    if (_config.randomDelayMinMs > 0 && _config.randomDelayMaxMs > 0) {
      final randomExtraMs = _config.randomDelayMinMs +
          _random.nextInt(_config.randomDelayMaxMs - _config.randomDelayMinMs + 1);
      return baseUs + randomExtraMs * 1000;
    }
    return baseUs;
  }

  Future<void> _performAction() async {
    if (_config.clickMode == ClickMode.keyboard) {
      await _performKeyAction();
    } else {
      await _performMouseClick();
    }
  }

  Future<void> _performMouseClick() async {
    int x = _config.positionMode == PositionMode.fixed
        ? _config.fixedX
        : -1;
    int y = _config.positionMode == PositionMode.fixed ? _config.fixedY : -1;

    // Apply random offset if enabled
    if (x >= 0 && y >= 0 && _config.randomOffsetEnabled) {
      final offsetMin = _config.randomOffsetMinPx;
      final offsetMax = _config.randomOffsetMaxPx;
      final range = offsetMax - offsetMin + 1;
      final offsetX = offsetMin + _random.nextInt(range) * (_random.nextBool() ? 1 : -1);
      final offsetY = offsetMin + _random.nextInt(range) * (_random.nextBool() ? 1 : -1);
      x += offsetX;
      y += offsetY;
    }

    // mouseClick already handles SetCursorPos for fixed positions,
    // no need to call mouseMove separately
    await _input.mouseClick(
      x: x,
      y: y,
      button: _config.mouseButton.name,
      doubleClick: _config.clickType == ClickType.double,
    );
  }

  Future<void> _performKeyAction() async {
    switch (_config.keyActionMode) {
      case KeyActionMode.repeat:
        await _performKeyRepeat();
        break;
      case KeyActionMode.hold:
        // Hold mode is handled by native thread for fast intervals.
        // For slow intervals, press once and the stop() will release it.
        if (!_usingNativeClicker) {
          await _input.keyPress(_config.keyToRepeat);
        }
        break;
      case KeyActionMode.sequence:
        await _performKeySequence();
        break;
      case KeyActionMode.combo:
        await _performComboAction();
        break;
      case KeyActionMode.text:
        await _performTextType();
        break;
    }
  }

  Future<void> _performKeyRepeat() async {
    final key = _config.keyToRepeat;
    if (_config.clickType == ClickType.double) {
      await _input.keyPress(key);
      await _input.keyRelease(key);
      await Future.delayed(const Duration(milliseconds: 30));
      await _input.keyPress(key);
      await _input.keyRelease(key);
    } else {
      await _input.keyPress(key);
      await _input.keyRelease(key);
    }
  }

  Future<void> _performKeySequence() async {
    for (int i = 0; i < _config.keySequence.length; i++) {
      if (_status != ClickerStatus.running) break;
      final item = _config.keySequence[i];
      await _input.keyPress(item.key);
      await _input.keyRelease(item.key);
      if (_config.jitterEnabled) {
        final jitter = _config.jitterMinMs +
            _random.nextInt(_config.jitterMaxMs - _config.jitterMinMs + 1);
        await Future.delayed(Duration(milliseconds: item.delayMs + jitter));
      } else if (i < _config.keySequence.length - 1 && item.delayMs > 0) {
        await Future.delayed(Duration(milliseconds: item.delayMs));
      }
    }
  }

  Future<void> _performComboAction() async {
    final keys = _config.comboKeys;
    if (keys.isEmpty) return;
    // Press all keys
    for (final key in keys) {
      await _input.keyPress(key);
    }
    await Future.delayed(const Duration(milliseconds: 50));
    // Release all keys in reverse order
    for (final key in keys.reversed) {
      await _input.keyRelease(key);
    }
  }

  Future<void> _performTextType() async {
    final text = _config.textToType;
    if (text.isEmpty) return;
    await _input.keyType(text, delayMs: _config.textTypeDelayMs);
  }

  bool _shouldStop() {
    if (_targetCount > 0 && _clickCount >= _targetCount) return true;
    if (_durationLimit != null && _startTime != null) {
      if (DateTime.now().difference(_startTime!) >= _durationLimit!) {
        return true;
      }
    }
    return false;
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _uiUpdateTimer?.cancel();
    _uiUpdateTimer = null;

    if (_usingNativeClicker) {
      _usingNativeClicker = false;
      _platformChannel.invokeMethod<bool>('stopFastClicker');
      _fetchNativeClickCount().then((count) {
        _clickCount = count;
      });
    }

    if (_config.clickMode == ClickMode.keyboard &&
        _config.keyActionMode == KeyActionMode.hold) {
      _input.keyRelease(_config.keyToRepeat);
    }

    if (_config.clickMode == ClickMode.keyboard &&
        _config.keyActionMode == KeyActionMode.combo) {
      for (final key in _config.comboKeys.reversed) {
        _input.keyRelease(key);
      }
    }

    if (_config.soundFeedbackEnabled && _clickCount > 0) {
      SystemSound.play(SystemSoundType.click);
    }

    _status = ClickerStatus.idle;
    onStatusChanged?.call(_status, _clickCount);
  }

  /// Get elapsed time since start (for stats display)
  Duration? get elapsedDuration {
    if (_startTime == null) return null;
    return DateTime.now().difference(_startTime!);
  }

  /// Get average clicks per second
  double get averageCps {
    if (_startTime == null || _clickCount == 0) return 0;
    final elapsed = DateTime.now().difference(_startTime!).inMilliseconds;
    if (elapsed == 0) return 0;
    return _clickCount / (elapsed / 1000);
  }

  void toggle() {
    _log('toggle: current status=$_status');
    if (_status == ClickerStatus.running) {
      stop();
    } else {
      start();
    }
  }

  void dispose() {
    stop();
  }
}
