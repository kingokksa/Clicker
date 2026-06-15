/// Mobile app state — manages services and configuration for Android/iOS.
/// Reuses core services (ClickService, MacroService, StorageService) but
/// removes desktop-only dependencies (window_manager, system_tray, etc.).
library;

import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show Color, MethodChannel;
import '../models/clicker_config.dart';
import '../models/hold_trigger_key.dart';
import '../models/hotkey_config.dart';
import '../models/macro_model.dart';
import '../services/click_service.dart';
import '../services/macro_service.dart';
import '../services/system_tray_service.dart';
import '../services/hotkey_service.dart';
import '../services/storage_service.dart';
import '../services/platform/platform_input.dart';
import '../services/platform/android_input.dart';

class MobileAppState extends ChangeNotifier {
  static const _platformChannel = MethodChannel('com.clicker.pro/platform');
  // Emergency stop signal
  static final StreamController<void> _emergencyStopController =
      StreamController<void>.broadcast();
  static Stream<void> get onEmergencyStopSignal =>
      _emergencyStopController.stream;
  static void broadcastEmergencyStop() {
    _emergencyStopController.add(null);
  }

  // Services
  late final StorageService _storage;
  late final PlatformInput _platformInput;
  late final ClickService _clickService;
  late final MacroService _macroService;
  late final HotkeyService _hotkeyService;

  // Config
  ClickerConfig _clickerConfig = ClickerConfig(
    clickMode: ClickMode.touch,
    positionMode: PositionMode.pick,
  );
  HotkeyConfig _hotkeyConfig = HotkeyConfig();
  String _themeMode = 'dark';
  Color _accentColor = const Color(0xFF7C4DFF);
  bool _uiAnimations = true;

  // Status
  ClickerStatus _clickerStatus = ClickerStatus.idle;
  MacroStatus _macroStatus = MacroStatus.idle;
  int _clickCount = 0;
  int _recordingEventCount = 0;
  int _playbackEventIndex = 0;
  int _playbackTotalEvents = 0;
  String _macroError = '';
  bool _isInitialized = false;

  // Macro list
  List<MacroModel> _macros = [];
  List<String> _profiles = [];

  // Hold trigger keys
  List<HoldTriggerKey> _holdTriggerKeys = [];

  // Getters
  ClickerConfig get clickerConfig => _clickerConfig;
  HotkeyConfig get hotkeyConfig => _hotkeyConfig;
  String get themeMode => _themeMode;
  Color get accentColor => _accentColor;
  bool get uiAnimations => _uiAnimations;
  ClickService get clickService => _clickService;
  ClickerStatus get clickerStatus => _clickerStatus;
  MacroStatus get macroStatus => _macroStatus;
  int get clickCount => _clickCount;
  int get recordingEventCount => _recordingEventCount;
  int get playbackEventIndex => _playbackEventIndex;
  int get playbackTotalEvents => _playbackTotalEvents;
  String get macroError => _macroError;
  bool get isInitialized => _isInitialized;
  List<MacroModel> get macros => List.unmodifiable(_macros);
  List<String> get profiles => List.unmodifiable(_profiles);
  List<HoldTriggerKey> get holdTriggerKeys => List.unmodifiable(_holdTriggerKeys);
  bool get isClickerRunning => _clickerStatus == ClickerStatus.running;
  bool get isFloatingPanelVisible => _floatingPanelVisible;
  bool get isRecording =>
      _macroStatus == MacroStatus.recording ||
      _macroStatus == MacroStatus.paused;
  bool get isPaused => _macroStatus == MacroStatus.paused;
  bool get isPlaying => _macroStatus == MacroStatus.playing;
  PlatformInput get platformInput => _platformInput;

  // Floating panel state
  bool _floatingPanelVisible = false;

  void clearMacroError() {
    _macroError = '';
    notifyListeners();
  }

  Future<void> init() async {
    try {
      _storage = StorageService();
      await _storage.init();

      // Listen for native method calls (floating panel toggle, etc.)
      // Use SystemTrayService's external handler registry to avoid overwriting the channel handler
      SystemTrayService().registerExternalHandler((call) async {
        switch (call.method) {
          case 'onFloatingToggle':
            toggleClicker();
            break;
          case 'onConfigChange':
            final args = call.arguments as Map?;
            if (args != null) {
              _handleFloatingConfigChange(args);
            }
            break;
          case 'onFloatingPickResult':
            final args = call.arguments as Map?;
            if (args != null) {
              final x = args['x'] as int;
              final y = args['y'] as int;
              _handleFloatingPickResult(x, y);
            }
            break;
          case 'onFloatingAreaResult':
            final args = call.arguments as Map?;
            if (args != null) {
              final x1 = args['x1'] as int;
              final y1 = args['y1'] as int;
              final x2 = args['x2'] as int;
              final y2 = args['y2'] as int;
              _handleFloatingAreaResult(x1, y1, x2, y2);
            }
            break;
          case 'onEmergencyStop':
            emergencyStop();
            break;
          case 'onFloatingPause':
            ClickService.floatingPanelPaused = true;
            break;
          case 'onFloatingResume':
            ClickService.floatingPanelPaused = false;
            break;
        }
        return null;
      });

      // Platform input
      if (Platform.isAndroid) {
        _platformInput = AndroidInput();
      } else if (Platform.isIOS) {
        _platformInput = AndroidInput(); // reuse AndroidInput for iOS for now
      } else {
        _platformInput = AndroidInput();
      }

      // Load configs — force touch mode on mobile
      _clickerConfig = _storage.loadClickerConfig().copyWith(
        clickMode: ClickMode.touch,
      );
      _hotkeyConfig = _storage.loadHotkeyConfig();
      _themeMode = _storage.themeMode;
      _accentColor = Color(_storage.accentColorValue);
      _uiAnimations = _storage.uiAnimations;
      _profiles = _storage.listProfiles();

      // Init services
      _clickService = ClickService(_platformInput);
      _clickService.updateConfig(_clickerConfig);

      _macroService = MacroService(_platformInput);
      _macroService.getConfig = () => _clickerConfig;

      _hotkeyService = HotkeyService(_platformInput);
      _hotkeyService.updateConfig(_hotkeyConfig);

      // Wire callbacks
      _clickService.onStatusChanged = (status, count) {
        _clickerStatus = status;
        _clickCount = count;
        _updateFloatingPanel();
        notifyListeners();
      };

      _platformInput.onFastClickerStopped = (count, generation) {
        _clickService.handleNativeClickerStopped(count, generation: generation);
      };

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
        _macroError = message;
        notifyListeners();
        Future.delayed(const Duration(seconds: 5), () {
          if (_macroError == message) {
            _macroError = '';
            notifyListeners();
          }
        });
      };

      // Hotkey actions (volume keys on mobile)
      _hotkeyService.onStartStopClicker = () {
        _clickService.toggle();
      };
      _hotkeyService.onStartStopRecording = () async {
        if (_macroService.isRecording) {
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
        broadcastEmergencyStop();
        notifyListeners();
      };
      _hotkeyService.onPlayMacro = () {
        if (_macros.isNotEmpty && !_macroService.isPlaying) {
          _macroService.playMacro(_macros.first);
        }
      };

      _hotkeyService.start();

      // Load macros
      _macros = await _storage.loadAllMacros();
      await _hotkeyService.reregisterAllMacroHotkeys(_macros);

      // Load hold trigger keys
      _holdTriggerKeys = _storage.loadHoldTriggerKeys();

      _isInitialized = true;
      notifyListeners();

      // Restore floating panel if it was visible before
      if (Platform.isAndroid && _storage.floatingPanelVisible) {
        Future.delayed(const Duration(milliseconds: 500), () {
          showFloatingPanel();
        });
      }
    } catch (e) {
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

  void emergencyStop() {
    _clickService.stop();
    _macroService.stopPlayback();
    broadcastEmergencyStop();
  }

  // ─── Floating Panel ──────────────────────────────────────

  Future<bool> checkOverlayPermission() async {
    try {
      final result = await _platformChannel.invokeMethod<bool>('checkOverlayPermission');
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> requestOverlayPermission() async {
    try {
      await _platformChannel.invokeMethod('requestOverlayPermission');
    } catch (_) {}
  }

  Future<void> showFloatingPanel() async {
    try {
      await _platformChannel.invokeMethod('showFloatingPanel');
      _floatingPanelVisible = true;
      _storage.setFloatingPanelVisible(true);
      _updateFloatingPanel();
      notifyListeners();
    } catch (_) {}
  }

  Future<void> hideFloatingPanel() async {
    try {
      await _platformChannel.invokeMethod('hideFloatingPanel');
      _floatingPanelVisible = false;
      _storage.setFloatingPanelVisible(false);
      notifyListeners();
    } catch (_) {}
  }

  Future<void> _updateFloatingPanel() async {
    if (!_floatingPanelVisible) return;
    try {
      await _platformChannel.invokeMethod('updateFloatingPanel', {
        'running': isClickerRunning,
      });
      // Sync full config to floating panel
      await _platformChannel.invokeMethod('updateFloatingPanelConfig', {
        'touchAction': _clickerConfig.touchAction.name,
        'intervalMs': _clickerConfig.intervalMs.round(),
        'repeatMode': _clickerConfig.repeatMode.name,
        'repeatCount': _clickerConfig.repeatCount,
        'themeColor': _accentColor.value,
      });
    } catch (_) {}
  }

  void _handleFloatingConfigChange(Map args) {
    var config = _clickerConfig;
    if (args.containsKey('touchAction')) {
      final action = TouchAction.values.firstWhere(
        (a) => a.name == args['touchAction'],
        orElse: () => TouchAction.tap,
      );
      config = config.copyWith(touchAction: action);
    }
    if (args.containsKey('intervalMs')) {
      config = config.copyWith(intervalMs: (args['intervalMs'] as num).toDouble());
    }
    if (args.containsKey('repeatMode')) {
      final mode = ClickRepeatMode.values.firstWhere(
        (m) => m.name == args['repeatMode'],
        orElse: () => ClickRepeatMode.infinite,
      );
      config = config.copyWith(repeatMode: mode);
    }
    if (args.containsKey('repeatCount')) {
      config = config.copyWith(repeatCount: (args['repeatCount'] as num).toInt());
    }
    if (config != _clickerConfig) {
      _clickerConfig = config;
      _clickService.updateConfig(config);
      _storage.saveClickerConfig(config);
      notifyListeners();
    }
  }

  void _handleFloatingPickResult(int x, int y) {
    var config = _clickerConfig;
    // Update the appropriate coordinates based on current touch action
    switch (config.touchAction) {
      case TouchAction.tap:
      case TouchAction.longPress:
        config = config.copyWith(fixedX: x, fixedY: y);
        break;
      case TouchAction.drag:
        // First pick sets start, second pick sets end
        if (config.dragStartX == 0 && config.dragStartY == 0) {
          config = config.copyWith(dragStartX: x, dragStartY: y);
        } else {
          config = config.copyWith(dragEndX: x, dragEndY: y);
        }
        break;
      case TouchAction.swipe:
        if (config.swipeStartX == 0 && config.swipeStartY == 0) {
          config = config.copyWith(swipeStartX: x, swipeStartY: y);
        } else {
          config = config.copyWith(swipeEndX: x, swipeEndY: y);
        }
        break;
    }
    if (config != _clickerConfig) {
      _clickerConfig = config;
      _clickService.updateConfig(config);
      _storage.saveClickerConfig(config);
      notifyListeners();
    }
  }

  void _handleFloatingAreaResult(int x1, int y1, int x2, int y2) {
    var config = _clickerConfig;
    switch (config.touchAction) {
      case TouchAction.drag:
        config = config.copyWith(
          dragStartX: x1, dragStartY: y1,
          dragEndX: x2, dragEndY: y2,
        );
        break;
      case TouchAction.swipe:
        config = config.copyWith(
          swipeStartX: x1, swipeStartY: y1,
          swipeEndX: x2, swipeEndY: y2,
        );
        break;
      default:
        // For tap/longPress, use center of area
        config = config.copyWith(
          fixedX: (x1 + x2) ~/ 2, fixedY: (y1 + y2) ~/ 2,
        );
        break;
    }
    if (config != _clickerConfig) {
      _clickerConfig = config;
      _clickService.updateConfig(config);
      _storage.saveClickerConfig(config);
      notifyListeners();
    }
  }

  // ─── Macro Actions ────────────────────────────────────────

  Future<void> startRecording() => _macroService.startRecording();

  void pauseRecording() => _macroService.pauseRecording();

  Future<void> stopRecording({String name = '录制的宏'}) async {
    final macro = _macroService.stopRecording(name: name);
    await _storage.saveMacro(macro);
    _macros.insert(0, macro);
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
    _updateFloatingPanel();
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
        alwaysOnTop: false,
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
      _macros = await _storage.loadAllMacros();
      _profiles = _storage.listProfiles();
      notifyListeners();
    }
    return result;
  }

  // ─── Hold Trigger Actions ─────────────────────────────────

  void setHoldTriggerKeys(List<HoldTriggerKey> keys) {
    _holdTriggerKeys = keys;
    _storage.saveHoldTriggerKeys(keys);
    notifyListeners();
  }

  void addHoldTriggerKey(HoldTriggerKey key) {
    _holdTriggerKeys = [..._holdTriggerKeys, key];
    _storage.saveHoldTriggerKeys(_holdTriggerKeys);
    notifyListeners();
  }

  void updateHoldTriggerKey(String id, HoldTriggerKey key) {
    _holdTriggerKeys = [
      for (final k in _holdTriggerKeys)
        if (k.id == id) key else k,
    ];
    _storage.saveHoldTriggerKeys(_holdTriggerKeys);
    notifyListeners();
  }

  void removeHoldTriggerKey(String id) {
    _holdTriggerKeys = _holdTriggerKeys.where((k) => k.id != id).toList();
    _storage.saveHoldTriggerKeys(_holdTriggerKeys);
    notifyListeners();
  }

  // ─── Key Capture ──────────────────────────────────────────

  Completer<String?>? _keyCaptureCompleter;

  Future<String?> captureKey() async {
    _keyCaptureCompleter = Completer<String?>();
    return _keyCaptureCompleter!.future;
  }

  @override
  void dispose() {
    _clickService.dispose();
    _macroService.dispose();
    _hotkeyService.dispose();
    super.dispose();
  }
}
