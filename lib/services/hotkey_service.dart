
import 'dart:async';
import 'dart:io';
import '../models/hotkey_config.dart';
import '../models/macro_model.dart';
import 'platform/platform_input.dart';
import 'platform/windows_input.dart';
import 'app_logger.dart';

class HotkeyService {
  final PlatformInput _input;
  HotkeyConfig _config = HotkeyConfig();
  StreamSubscription<String>? _subscription;

  bool _holdTriggerActive = false;
  Timer? _holdTriggerPollTimer;
  DateTime? _lastHoldTriggerTime;

  final Map<int, String> _macroHotkeyIds = {};
  final Map<String, String> _macroHotkeys = {};
  static const int _macroHotkeyBaseId = 100;

  void Function()? onStartStopClicker;
  void Function()? onStartStopRecording;
  void Function()? onEmergencyStop;
  void Function()? onPlayMacro;
  void Function()? onHoldTriggerStart;
  void Function()? onHoldTriggerStop;
  void Function(String macroId)? onPlayMacroById;
  void Function()? onBackgroundClick;

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

  Future<void> _registerSystemHotkeys() async {
    if (Platform.isWindows) {
      final winInput = _input as WindowsInput;
      await winInput.registerHotkey('startStopClicker', _config.startStopClicker);
      await winInput.registerHotkey('startStopRecording', _config.startStopRecording);
      await winInput.registerHotkey('emergencyStop', _config.emergencyStop);
      await winInput.registerHotkey('playMacro', _config.playMacro);
      await winInput.registerHotkey('holdTrigger', _config.holdTrigger);
      await winInput.registerHotkey('backgroundClick', _config.backgroundClick);
    }
  }

  void _handleKeyEvent(String field) {
    AppLogger.instance.log('HotkeyService', 'received: $field');
    final fieldId = int.tryParse(field);
    if (fieldId != null && fieldId >= _macroHotkeyBaseId) {
      final macroId = _macroHotkeyIds[fieldId];
      if (macroId != null) {
        AppLogger.instance.log('HotkeyService', 'playMacroById: $macroId');
        onPlayMacroById?.call(macroId);
        return;
      }
    }
    switch (field) {
      case 'startStopClicker':
        AppLogger.instance.log('HotkeyService', 'toggle clicker');
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
      case 'backgroundClick':
        onBackgroundClick?.call();
        break;
    }
  }

  void _handleHoldTrigger() {
    _lastHoldTriggerTime = DateTime.now();

    if (_holdTriggerActive) return;
    _holdTriggerActive = true;
    onHoldTriggerStart?.call();

    _holdTriggerPollTimer?.cancel();
    _holdTriggerPollTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!_holdTriggerActive) return;
      final elapsed = DateTime.now().difference(_lastHoldTriggerTime!);
      if (elapsed.inMilliseconds > 300) {
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

  Future<void> registerMacroHotkey(String macroId, String hotkey) async {
    await unregisterMacroHotkey(macroId);

    if (Platform.isWindows) {
      final winInput = _input as WindowsInput;
      int id = _macroHotkeyBaseId;
      while (_macroHotkeyIds.containsKey(id)) {
        id++;
      }
      await winInput.registerHotkey(id.toString(), hotkey);
      _macroHotkeyIds[id] = macroId;
      _macroHotkeys[macroId] = hotkey;
    }
  }

  Future<void> unregisterMacroHotkey(String macroId) async {
    final hotkey = _macroHotkeys[macroId];
    if (hotkey == null) return;

    if (Platform.isWindows) {
      final winInput = _input as WindowsInput;
      final entry = _macroHotkeyIds.entries.firstWhere(
        (e) => e.value == macroId,
        orElse: () => const MapEntry(-1, ''),
      );
      if (entry.key >= _macroHotkeyBaseId) {
        await winInput.unregisterHotkey(entry.key.toString());
        _macroHotkeyIds.remove(entry.key);
      }
    }
    _macroHotkeys.remove(macroId);
  }

  Future<void> reregisterAllMacroHotkeys(List<MacroModel> macros) async {
    if (Platform.isWindows) {
      final winInput = _input as WindowsInput;
      for (final id in _macroHotkeyIds.keys.toList()) {
        await winInput.unregisterHotkey(id.toString());
      }
      _macroHotkeyIds.clear();
      _macroHotkeys.clear();

      int nextId = _macroHotkeyBaseId;
      for (final macro in macros) {
        if (macro.enabled && macro.hotkey != null && macro.hotkey!.isNotEmpty) {
          await winInput.registerHotkey(nextId.toString(), macro.hotkey!);
          _macroHotkeyIds[nextId] = macro.id;
          _macroHotkeys[macro.id] = macro.hotkey!;
          nextId++;
        }
      }
    }
  }

  void dispose() {
    stop();
  }
}
