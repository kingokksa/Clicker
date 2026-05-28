/// Application state — manages all services and configuration.
/// Single ChangeNotifier for Provider-based state management.
library;

import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show Color, PlatformException;
import '../models/clicker_config.dart';
import '../models/hold_trigger_key.dart';
import '../models/hotkey_config.dart';
import '../models/macro_model.dart';
import '../services/click_service.dart';
import '../services/macro_service.dart';
import '../services/hotkey_service.dart';
import '../services/storage_service.dart';
import '../services/window_detect_service.dart';
import '../services/script_engine.dart';
import '../services/remote_control_service.dart';
import '../services/platform/platform_input.dart';
import '../services/platform/windows_input.dart';
import '../services/platform/android_input.dart';
import '../services/platform/linux_input.dart';
import '../services/system_tray_service.dart';
import 'package:window_manager/window_manager.dart';

class AppState extends ChangeNotifier {
  // Services
  late final StorageService _storage;
  late final PlatformInput _platformInput;
  late final ClickService _clickService;
  late final MacroService _macroService;
  late final HotkeyService _hotkeyService;
  late final WindowDetectService _windowDetectService;
  late final ScriptEngine _scriptEngine;
  late final RemoteControlService _remoteControlService;

  // Config
  ClickerConfig _clickerConfig = ClickerConfig();
  HotkeyConfig _hotkeyConfig = HotkeyConfig();
  String _themeMode = 'dark';
  Color _accentColor = const Color(0xFF7C4DFF);
  bool _alwaysOnTop = true;
  bool _minimizeToTray = true;
  bool _floatingAlwaysOnTop = true;
  bool _uiAnimations = true;

  // Status
  ClickerStatus _clickerStatus = ClickerStatus.idle;
  MacroStatus _macroStatus = MacroStatus.idle;
  int _clickCount = 0;
  int _recordingEventCount = 0;
  int _playbackEventIndex = 0;
  int _playbackTotalEvents = 0;
  bool _isInitialized = false;

  // Macro list
  List<MacroModel> _macros = [];
  List<String> _profiles = [];

  // Script list
  final List<ScriptModel> _scripts = [];

  // Window detect rules
  final List<WindowRule> _windowRules = [];

  // Hold trigger keys
  List<HoldTriggerKey> _holdTriggerKeys = [];

  // Remote control port
  int _remoteControlPort = 9876;

  // Getters
  ClickerConfig get clickerConfig => _clickerConfig;
  HotkeyConfig get hotkeyConfig => _hotkeyConfig;
  String get themeMode => _themeMode;
  Color get accentColor => _accentColor;
  bool get alwaysOnTop => _alwaysOnTop;
  bool get minimizeToTray => _minimizeToTray;
  bool get hasAskedMinimizeToTray => _storage.hasAskedMinimizeToTray;
  bool get floatingAlwaysOnTop => _floatingAlwaysOnTop;
  bool get uiAnimations => _uiAnimations;
  ClickService get clickService => _clickService;
  ClickerStatus get clickerStatus => _clickerStatus;
  MacroStatus get macroStatus => _macroStatus;
  int get clickCount => _clickCount;
  int get recordingEventCount => _recordingEventCount;
  int get playbackEventIndex => _playbackEventIndex;
  int get playbackTotalEvents => _playbackTotalEvents;
  bool get isInitialized => _isInitialized;
  List<MacroModel> get macros => List.unmodifiable(_macros);
  List<String> get profiles => List.unmodifiable(_profiles);
  bool get isClickerRunning => _clickerStatus == ClickerStatus.running;
  bool get isRecording => _macroStatus == MacroStatus.recording || _macroStatus == MacroStatus.paused;
  bool get isPaused => _macroStatus == MacroStatus.paused;
  bool get isPlaying => _macroStatus == MacroStatus.playing;
  PlatformInput get platformInput => _platformInput;
  WindowDetectService get windowDetectService => _windowDetectService;
  ScriptEngine get scriptEngine => _scriptEngine;
  RemoteControlService get remoteControlService => _remoteControlService;
  List<ScriptModel> get scripts => List.unmodifiable(_scripts);
  List<WindowRule> get windowRules => List.unmodifiable(_windowRules);
  List<HoldTriggerKey> get holdTriggerKeys => List.unmodifiable(_holdTriggerKeys);
  int get remoteControlPort => _remoteControlPort;
  bool get isRemoteControlRunning => _remoteControlService.isRunning;
  bool get isWindowDetectRunning => _windowDetectService.isRunning;
  ScriptStatus get scriptStatus => _scriptEngine.status;

  Future<void> init() async {
    try {
      _storage = StorageService();
      await _storage.init();

      // Platform-specific input
      if (Platform.isWindows) {
        _platformInput = WindowsInput();
      } else if (Platform.isLinux) {
        _platformInput = LinuxInput();
      } else if (Platform.isAndroid) {
        _platformInput = AndroidInput();
      } else {
        _platformInput = WindowsInput(); // fallback
      }

      // Load configs
      _clickerConfig = _storage.loadClickerConfig();
      _hotkeyConfig = _storage.loadHotkeyConfig();
      _themeMode = _storage.themeMode;
      _accentColor = Color(_storage.accentColorValue);
      _alwaysOnTop = _storage.alwaysOnTop;
      _minimizeToTray = _storage.minimizeToTray;
      _floatingAlwaysOnTop = _storage.floatingAlwaysOnTop;
      _uiAnimations = _storage.uiAnimations;
      _profiles = _storage.listProfiles();

      // Apply always-on-top setting on startup
      if (_alwaysOnTop) {
        windowManager.setAlwaysOnTop(true);
      }

      // Init services
      _clickService = ClickService(_platformInput);
      _clickService.updateConfig(_clickerConfig);

      _macroService = MacroService(_platformInput);

      _hotkeyService = HotkeyService(_platformInput);
      _hotkeyService.updateConfig(_hotkeyConfig);

      // Init extension services
      _windowDetectService = WindowDetectService();
      _windowDetectService.onRuleMatched = (rule) {
        // Auto-load profile when window rule matches
        loadProfile(rule.profileName);
        notifyListeners();
      };
      _windowDetectService.onWindowChanged = (_) {
        notifyListeners();
      };

      _scriptEngine = ScriptEngine();
      _scriptEngine.doClick = (x, y, button) => _platformInput.mouseClick(x: x, y: y, button: button);
      _scriptEngine.doMove = (x, y) => _platformInput.mouseMove(x, y);
      _scriptEngine.doKeyPress = (key) => _platformInput.keyPress(key);
      _scriptEngine.doKeyRelease = (key) => _platformInput.keyRelease(key);
      _scriptEngine.doScroll = (dx, dy) => _platformInput.mouseScroll(dx: dx, dy: dy);
      _scriptEngine.doType = (text, delayMs) => _platformInput.keyType(text, delayMs: delayMs);
      _scriptEngine.doStartClicker = () async => _clickService.start();
      _scriptEngine.doStopClicker = () async => _clickService.stop();
      _scriptEngine.onStatusChanged = (_) => notifyListeners();
      _scriptEngine.onLog = (_) {};
      _scriptEngine.onError = (_) {};

      _remoteControlService = RemoteControlService();
      _remoteControlService.onStartClicker = () => _clickService.start();
      _remoteControlService.onStopClicker = () => _clickService.stop();
      _remoteControlService.onToggleClicker = () => _clickService.toggle();
      _remoteControlService.onPlayMacro = () {
        if (_macros.isNotEmpty && !_macroService.isPlaying) {
          _macroService.playMacro(_macros.first);
        }
      };
      _remoteControlService.onStopMacro = () => _macroService.stopPlayback();
      _remoteControlService.onGetStatus = () => {
        'clickerRunning': _clickerStatus == ClickerStatus.running,
        'macroStatus': _macroStatus.name,
        'clickCount': _clickCount,
      };
      _remoteControlService.onLog = (_) {};
      _remoteControlService.onError = (_) {};

      // Wire callbacks
      _clickService.onStatusChanged = (status, count) {
        _clickerStatus = status;
        _clickCount = count;
        notifyListeners();
      };

      // Native fast clicker stop callback
      _platformInput.onFastClickerStopped = (count, generation) {
        _clickService.handleNativeClickerStopped(count, generation: generation);
      };

      // Wire platform input reference to system tray service for callback forwarding
      SystemTrayService().platformInput = _platformInput;

      _macroService.onStatusChanged = (status) {
        _macroStatus = status;
        notifyListeners();
      };

      _macroService.onRecordingUpdate = (count) {
        _recordingEventCount = count;
        notifyListeners();
      };

      _macroService.onPlaybackProgress = (index, total) {
        _playbackEventIndex = index;
        _playbackTotalEvents = total;
        notifyListeners();
      };

      _macroService.onError = (message) {
        // Propagate error — UI can listen to this
        notifyListeners();
      };

      // Hotkey actions
      _hotkeyService.onStartStopClicker = () {
        _clickService.toggle();
      };
      _hotkeyService.onStartStopRecording = () async {
        if (_macroService.isRecording) {
          // Pause hook immediately so no more events captured
          _macroService.pauseRecording();
          notifyListeners();
        } else {
          await _macroService.startRecording();
          notifyListeners();
        }
      };
      _hotkeyService.onEmergencyStop = () {
        _clickService.stop();
        _macroService.stopPlayback();
        _macroService.cancelRecording();
        notifyListeners();
      };
      _hotkeyService.onPlayMacro = () {
        if (_macros.isNotEmpty && !_macroService.isPlaying) {
          _macroService.playMacro(_macros.first);
        }
      };
      _hotkeyService.onPlayMacroById = (macroId) {
        if (_macroService.isPlaying) return;
        final macro = _macros.where((m) => m.id == macroId).firstOrNull;
        if (macro != null) {
          _macroService.playMacro(macro);
        }
      };
      _hotkeyService.onHoldTriggerStart = () {
        if (_clickerConfig.holdTriggerEnabled && !_clickService.isRunning) {
          _clickService.start();
        }
      };
      _hotkeyService.onHoldTriggerStop = () {
        if (_clickerConfig.holdTriggerEnabled && _clickService.isRunning) {
          _clickService.stop();
        }
      };

      _hotkeyService.start();

      // Load hold trigger keys
      _holdTriggerKeys = _storage.loadHoldTriggerKeys();
      _registerHoldTriggerKeys();

      // Key capture callback
      _platformInput.onKeyCaptured = (keyName) {
        // Forward to any active listener
        _keyCaptureCompleter?.complete(keyName);
        _keyCaptureCompleter = null;
      };

      // Load macros
      _macros = await _storage.loadAllMacros();

      // Register per-macro hotkeys
      await _hotkeyService.reregisterAllMacroHotkeys(_macros);

      _isInitialized = true;
      notifyListeners();
    } catch (e) {
      // If initialization fails, still mark as initialized so the UI renders
      _isInitialized = true;
      notifyListeners();
    }
  }

  // ─── Clicker Actions ──────────────────────────────────────

  void setClickerConfig(ClickerConfig config) {
    _clickerConfig = config;
    _clickService.updateConfig(config);
    _storage.saveClickerConfig(config);
    notifyListeners();
  }

  void toggleClicker() {
    if (!_clickerConfig.autoClickEnabled && !_clickService.isRunning) return;
    _clickService.toggle();
  }

  void stopClicker() => _clickService.stop();

  // ─── Extension Feature Actions ────────────────────────────

  /// Toggle window auto-detect
  Future<void> setWindowAutoDetectEnabled(bool enabled) async {
    _clickerConfig = _clickerConfig.copyWith(windowAutoDetectEnabled: enabled);
    _storage.saveClickerConfig(_clickerConfig);
    if (enabled) {
      _windowDetectService.start();
    } else {
      _windowDetectService.stop();
    }
    notifyListeners();
  }

  /// Add a window detect rule
  void addWindowRule(WindowRule rule) {
    _windowRules.add(rule);
    _windowDetectService.addRule(rule);
    notifyListeners();
  }

  /// Remove a window detect rule
  void removeWindowRule(String id) {
    _windowRules.removeWhere((r) => r.id == id);
    _windowDetectService.removeRule(id);
    notifyListeners();
  }

  /// Toggle image recognition
  void setImageRecognitionEnabled(bool enabled) {
    _clickerConfig = _clickerConfig.copyWith(imageRecognitionEnabled: enabled);
    _storage.saveClickerConfig(_clickerConfig);
    notifyListeners();
  }

  /// Toggle script engine
  void setScriptEngineEnabled(bool enabled) {
    _clickerConfig = _clickerConfig.copyWith(scriptEngineEnabled: enabled);
    _storage.saveClickerConfig(_clickerConfig);
    if (!enabled && _scriptEngine.status == ScriptStatus.running) {
      _scriptEngine.stop();
    }
    notifyListeners();
  }

  /// Add a script
  void addScript(ScriptModel script) {
    _scripts.add(script);
    notifyListeners();
  }

  /// Remove a script
  void removeScript(String id) {
    _scripts.removeWhere((s) => s.id == id);
    notifyListeners();
  }

  /// Run a script
  Future<void> runScript(ScriptModel script) async {
    await _scriptEngine.run(script);
  }

  /// Stop script execution
  void stopScript() {
    _scriptEngine.stop();
  }

  /// Toggle remote control
  Future<void> setRemoteControlEnabled(bool enabled) async {
    _clickerConfig = _clickerConfig.copyWith(remoteControlEnabled: enabled);
    _storage.saveClickerConfig(_clickerConfig);
    if (enabled) {
      await _remoteControlService.start(port: _remoteControlPort);
    } else {
      await _remoteControlService.stop();
    }
    notifyListeners();
  }

  /// Set remote control port
  void setRemoteControlPort(int port) {
    _remoteControlPort = port;
    if (_remoteControlService.isRunning) {
      _remoteControlService.stop().then((_) {
        _remoteControlService.start(port: port);
      });
    }
    notifyListeners();
  }

  // ─── Macro Actions ────────────────────────────────────────

  Future<void> startRecording() => _macroService.startRecording();

  /// Pause recording hook immediately (stops capturing events).
  void pauseRecording() => _macroService.pauseRecording();

  Future<void> stopRecording({String name = '录制的宏'}) async {
    final macro = _macroService.stopRecording(name: name);
    await _storage.saveMacro(macro);
    _macros.insert(0, macro);
    await _hotkeyService.reregisterAllMacroHotkeys(_macros);
    notifyListeners();
  }

  void cancelRecording() => _macroService.cancelRecording();

  Future<void> playMacro(MacroModel macro) async {
    await _macroService.playMacro(macro);
  }

  void stopMacro() => _macroService.stopPlayback();

  Future<void> deleteMacro(MacroModel macro) async {
    await _storage.deleteMacro(macro.id);
    _macros.removeWhere((m) => m.id == macro.id);
    await _hotkeyService.reregisterAllMacroHotkeys(_macros);
    notifyListeners();
  }

  Future<void> renameMacro(MacroModel macro, String newName) async {
    final updated = macro.copyWith(name: newName);
    await _storage.saveMacro(updated);
    final idx = _macros.indexWhere((m) => m.id == macro.id);
    if (idx >= 0) {
      _macros[idx] = updated;
      notifyListeners();
    }
  }

  Future<void> saveMacroFromBuilder(MacroModel macro) async {
    await _storage.saveMacro(macro);
    _macros.insert(0, macro);
    notifyListeners();
  }

  Future<void> updateMacro(MacroModel macro) async {
    final idx = _macros.indexWhere((m) => m.id == macro.id);
    if (idx >= 0) {
      _macros[idx] = macro;
    } else {
      _macros.insert(0, macro);
    }
    await _storage.saveMacro(macro);
    await _hotkeyService.reregisterAllMacroHotkeys(_macros);
    notifyListeners();
  }

  // ─── Hotkey Actions ───────────────────────────────────────

  void setHotkeyConfig(HotkeyConfig config) {
    _hotkeyConfig = config;
    _hotkeyService.updateConfig(config);
    _storage.saveHotkeyConfig(config);
    notifyListeners();
  }

  // ─── Settings Actions ─────────────────────────────────────

  void setThemeMode(String mode) {
    _themeMode = mode;
    _storage.setThemeMode(mode);
    notifyListeners();
  }

  void setAccentColor(Color color) {
    _accentColor = color;
    _storage.setAccentColorValue(color.toARGB32());
    notifyListeners();
  }

  void setAlwaysOnTop(bool value) {
    _alwaysOnTop = value;
    _storage.setAlwaysOnTop(value);
    windowManager.setAlwaysOnTop(value);
    notifyListeners();
  }

  void setMinimizeToTray(bool value) {
    _minimizeToTray = value;
    _storage.setMinimizeToTray(value);
    notifyListeners();
  }

  void setFloatingAlwaysOnTop(bool value) {
    _floatingAlwaysOnTop = value;
    _storage.setFloatingAlwaysOnTop(value);
    notifyListeners();
  }

  void setUiAnimations(bool value) {
    _uiAnimations = value;
    _storage.setUiAnimations(value);
    notifyListeners();
  }

  // ─── Profile Actions ──────────────────────────────────────

  Future<void> saveProfile(String name) async {
    await _storage.saveProfile(name, _clickerConfig);
    if (!_profiles.contains(name)) {
      _profiles.add(name);
    }
    notifyListeners();
  }

  void loadProfile(String name) {
    final config = _storage.loadProfile(name);
    if (config != null) {
      _clickerConfig = config;
      _clickService.updateConfig(config);
      notifyListeners();
    }
  }

  Future<void> deleteProfile(String name) async {
    await _storage.deleteProfile(name);
    _profiles.remove(name);
    notifyListeners();
  }

  // ─── Import / Export ──────────────────────────────────────

  Future<bool> exportConfig() => _storage.exportConfigToFile(
    clickerConfig: _clickerConfig,
    hotkeyConfig: _hotkeyConfig,
    themeMode: _themeMode,
    alwaysOnTop: _alwaysOnTop,
  );

  Future<ImportResult> importConfig() async {
    final result = await _storage.importConfigFromFile();
    if (result.success) {
      if (result.clickerConfig != null) {
        _clickerConfig = result.clickerConfig!;
        _clickService.updateConfig(_clickerConfig);
      }
      if (result.hotkeyConfig != null) {
        _hotkeyConfig = result.hotkeyConfig!;
        _hotkeyService.updateConfig(_hotkeyConfig);
      }
      if (result.themeMode != null) _themeMode = result.themeMode!;
      if (result.alwaysOnTop != null) _alwaysOnTop = result.alwaysOnTop!;
      _macros = await _storage.loadAllMacros();
      _profiles = _storage.listProfiles();
      notifyListeners();
    }
    return result;
  }

  @override
  void dispose() {
    _clickService.dispose();
    _macroService.dispose();
    _hotkeyService.dispose();
    _windowDetectService.dispose();
    _scriptEngine.dispose();
    _remoteControlService.dispose();
    _unregisterHoldTriggerKeys();
    super.dispose();
  }

  // ─── Hold Trigger ──────────────────────────────────────

  Completer<String?>? _keyCaptureCompleter;

  /// Start capturing a key press. Returns the key name when captured.
  Future<String?> captureKey() async {
    if (_keyCaptureCompleter != null && !_keyCaptureCompleter!.isCompleted) {
      _keyCaptureCompleter!.completeError('Cancelled');
    }
    _keyCaptureCompleter = Completer<String?>();
    try {
      await _platformInput.invokeMethod('captureKey');
      // Wait for onKeyCaptured callback with 10s timeout
      return await _keyCaptureCompleter!.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () => null,
      );
    } on PlatformException {
      return null;
    }
  }

  void setHoldTriggerKeys(List<HoldTriggerKey> keys) {
    _holdTriggerKeys = keys;
    _storage.saveHoldTriggerKeys(keys);
    _registerHoldTriggerKeys();
    notifyListeners();
  }

  void addHoldTriggerKey(HoldTriggerKey key) {
    _holdTriggerKeys = [..._holdTriggerKeys, key];
    _storage.saveHoldTriggerKeys(_holdTriggerKeys);
    _registerHoldTriggerKeys();
    notifyListeners();
  }

  void updateHoldTriggerKey(String id, HoldTriggerKey key) {
    _holdTriggerKeys = [
      for (final k in _holdTriggerKeys)
        if (k.id == id) key else k,
    ];
    _storage.saveHoldTriggerKeys(_holdTriggerKeys);
    _registerHoldTriggerKeys();
    notifyListeners();
  }

  void removeHoldTriggerKey(String id) {
    _holdTriggerKeys = _holdTriggerKeys.where((k) => k.id != id).toList();
    _storage.saveHoldTriggerKeys(_holdTriggerKeys);
    _registerHoldTriggerKeys();
    notifyListeners();
  }

  void _registerHoldTriggerKeys() {
    final enabledKeys = _holdTriggerKeys.where((k) => k.enabled).toList();
    if (enabledKeys.isEmpty) {
      _unregisterHoldTriggerKeys();
      return;
    }

    final configs = enabledKeys.map((k) {
      // action: 0=mouseClick, 1=keyRepeat, 2=keyCombo
      int action;
      dynamic actionParam;
      switch (k.action) {
        case HoldTriggerAction.mouseClick:
          action = 0;
          int mb = 0;
          if (k.mouseButton == 'right') mb = 1;
          else if (k.mouseButton == 'middle') mb = 2;
          actionParam = mb;
          break;
        case HoldTriggerAction.keyRepeat:
          action = 1;
          actionParam = k.keyToRepeat;
          break;
        case HoldTriggerAction.keyCombo:
          action = 2;
          actionParam = k.comboKeys;
          break;
      }

      return [
        k.triggerKey,       // trigger key name
        action,             // action type
        k.intervalMs.toInt(), // interval ms
        actionParam,        // action-specific param
        k.backgroundMode,   // background mode
        k.targetHwnd,       // target hwnd
        k.targetX,          // client x
        k.targetY,          // client y
        k.triggerType.name, // trigger type: "keyboard" or "mouse"
        k.triggerType == HoldTriggerType.mouse
          ? (k.triggerMouseButton == 'right' ? 1 : (k.triggerMouseButton == 'middle' ? 2 : 0))
          : 0,              // mouse trigger button: 0=left, 1=right, 2=middle
      ];
    }).toList();

    _platformInput.invokeMethod('registerHoldTriggerKeys', configs);
  }

  void _unregisterHoldTriggerKeys() {
    _platformInput.invokeMethod('unregisterHoldTriggerKeys');
  }
}
