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
  DateTime? _startTime;
  Duration? _durationLimit;
  final Random _random = Random();

  // Native fast clicker channel
  static const _platformChannel = MethodChannel('com.clicker.pro/platform');
  bool _usingNativeClicker = false;

  // Callbacks
  void Function(ClickerStatus status, int count)? onStatusChanged;
  void Function(String message)? onError;

  ClickService(this._input);

  ClickerStatus get status => _status;
  ClickerConfig get config => _config;
  int get clickCount => _clickCount;
  bool get isRunning => _status == ClickerStatus.running;

  /// Called from AppState when the native clicker thread reports it stopped.
  void handleNativeClickerStopped(int count) {
    _clickCount = count;
    _usingNativeClicker = false;
    _timer?.cancel();
    _timer = null;
    _status = ClickerStatus.idle;
    onStatusChanged?.call(_status, _clickCount);
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
    onStatusChanged?.call(_status, _clickCount);

    // Keyboard hold mode: press and hold the key
    if (_config.clickMode == ClickMode.keyboard &&
        _config.keyActionMode == KeyActionMode.hold) {
      await _input.keyPress(_config.keyToRepeat);
      _timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
        if (_shouldStop()) {
          stop();
        }
      });
      return;
    }

    // Keyboard combo mode: press all combo keys together
    if (_config.clickMode == ClickMode.keyboard &&
        _config.keyActionMode == KeyActionMode.combo) {
      _scheduleCombo();
      return;
    }

    _scheduleClick();
  }

  int _uiUpdateCounter = 0;

  void _scheduleClick() {
    if (_status != ClickerStatus.running) return;

    final delayUs = _getDelayUs();

    // Fast mouse clicking: use native Win32 thread for maximum speed
    // This avoids blocking the Dart event loop, so hotkeys remain responsive.
    if (delayUs < 50000 && _config.clickMode == ClickMode.mouse) {
      _startNativeFastClicker();
      return;
    }

    if (delayUs >= 50000) {
      // Slow mode (>= 50ms): one-shot timer, await each action
      _timer = Timer(Duration(microseconds: delayUs), () async {
        if (_status != ClickerStatus.running) return;
        await _performAction();
        _clickCount++;
        onStatusChanged?.call(_status, _clickCount);
        if (_shouldStop()) { stop(); return; }
        _scheduleClick();
      });
    } else {
      // Fast keyboard mode: batch clicks per 1ms timer tick
      final clicksPerTick = (1000.0 / _config.intervalMs).ceil();
      final batch = clicksPerTick.clamp(1, 200);

      _timer = Timer.periodic(const Duration(milliseconds: 1), (_) {
        if (_status != ClickerStatus.running) return;
        for (int i = 0; i < batch; i++) {
          if (_shouldStop()) break;
          _performFastKeyAction();
          _clickCount++;
        }
        _uiUpdateCounter++;
        if (_uiUpdateCounter >= 10) {
          _uiUpdateCounter = 0;
          onStatusChanged?.call(_status, _clickCount);
        }
        if (_shouldStop()) {
          onStatusChanged?.call(_status, _clickCount);
          stop();
        }
      });
    }
  }

  /// Start native fast clicker via platform channel.
  /// Runs on a separate Win32 thread with multimedia timer —
  /// does NOT block Dart event loop, so hotkeys remain responsive.
  Future<void> _startNativeFastClicker() async {
    _usingNativeClicker = true;
    int x = _config.positionMode == PositionMode.fixed ? _config.fixedX : -1;
    int y = _config.positionMode == PositionMode.fixed ? _config.fixedY : -1;
    int button = _config.mouseButton == MouseButton.right ? 1
        : (_config.mouseButton == MouseButton.middle ? 2 : 0);
    int targetCount = _targetCount > 0 ? _targetCount : -1;
    int intervalUs = (_config.intervalMs * 1000).round();

    // UI update timer for count display
    _timer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (_status == ClickerStatus.running) {
        onStatusChanged?.call(_status, _clickCount);
      }
    });

    try {
      final bgMode = _config.backgroundExecutionEnabled;
      final hwnd = _config.targetHwnd;
      final cx = _config.targetClientX;
      final cy = _config.targetClientY;
      await _platformChannel.invokeMethod<bool>('startFastClicker', [
        intervalUs, x, y, button, targetCount,
        bgMode, hwnd, cx, cy,
      ]);
    } on PlatformException catch (e) {
      _usingNativeClicker = false;
      onError?.call('原生点击器启动失败: ${e.message}');
      stop();
    }
  }

  /// Synchronous fast keyboard action — bypasses all async/await overhead.
  void _performFastKeyAction() {
    final key = _config.keyToRepeat;
    _input.keyPress(key);
    _input.keyRelease(key);
  }

  void _scheduleCombo() {
    if (_status != ClickerStatus.running) return;

    final delayUs = _getDelayUs();

    if (delayUs >= 50000) {
      _timer = Timer(Duration(microseconds: delayUs), () async {
        if (_status != ClickerStatus.running) return;
        await _performComboAction();
        _clickCount++;
        onStatusChanged?.call(_status, _clickCount);
        if (_shouldStop()) { stop(); return; }
        _scheduleCombo();
      });
    } else {
      final clicksPerTick = (1000.0 / _config.intervalMs).ceil();
      final batch = clicksPerTick.clamp(1, 500);

      _timer = Timer.periodic(const Duration(milliseconds: 1), (_) {
        if (_status != ClickerStatus.running) return;
        for (int i = 0; i < batch; i++) {
          if (_shouldStop()) break;
          _performComboAction();
          _clickCount++;
        }
        _uiUpdateCounter++;
        if (_uiUpdateCounter >= 10) {
          _uiUpdateCounter = 0;
          onStatusChanged?.call(_status, _clickCount);
        }
        if (_shouldStop()) {
          onStatusChanged?.call(_status, _clickCount);
          stop();
        }
      });
    }
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
        // Handled in start()
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
    _uiUpdateCounter = 0;

    // Stop native fast clicker if running
    if (_usingNativeClicker) {
      _usingNativeClicker = false;
      _platformChannel.invokeMethod<bool>('stopFastClicker');
    }

    // Release held key if in keyboard hold mode
    if (_config.clickMode == ClickMode.keyboard &&
        _config.keyActionMode == KeyActionMode.hold) {
      _input.keyRelease(_config.keyToRepeat);
    }

    // Release combo keys if still held
    if (_config.clickMode == ClickMode.keyboard &&
        _config.keyActionMode == KeyActionMode.combo) {
      for (final key in _config.comboKeys.reversed) {
        _input.keyRelease(key);
      }
    }

    // Sound feedback on stop
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
