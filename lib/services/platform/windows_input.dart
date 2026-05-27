/// Windows platform input using win32 FFI (SendInput + SetCursorPos).
/// Uses RegisterHotKey via MethodChannel for system-level hotkey priority.
library;

import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart';
import 'package:win32/win32.dart';
import 'platform_input.dart';
import '../../models/hotkey_config.dart';

class WindowsInput extends PlatformInput {
  final StreamController<String> _keyController =
      StreamController<String>.broadcast();
  bool _listening = false;

  static const _channel = MethodChannel('clicker/hotkeys');
  static const _recordChannel = MethodChannel('com.clicker.pro/record');
  static const _platformChannel = MethodChannel('com.clicker.pro/platform');

  // Track registered hotkey field -> ID mapping
  final Map<String, int> _registeredHotkeys = {};

  // Recording callback
  void Function(Map<String, dynamic> event)? onRecordEvent;
  void Function()? onRecordingCancelled;

  WindowsInput() {
    _channel.setMethodCallHandler(_handleMethodCall);
    _recordChannel.setMethodCallHandler(_handleRecordCall);
  }

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    if (call.method == 'onHotkey') {
      final id = call.arguments as int;
      final field = HotkeyConfig.idToField(id);
      if (field.isNotEmpty) {
        _keyController.add(field);
      } else {
        // Numeric IDs (100+) are used for per-macro hotkeys
        _keyController.add(id.toString());
      }
    } else if (call.method == 'onStopClickerImmediate') {
      // C++ requests immediate stop (for keyboard mode which uses Dart Timers).
      // Emit a special event that the click service listens to.
      _keyController.add('__stop_immediate__');
    }
  }

  Future<dynamic> _handleRecordCall(MethodCall call) async {
    if (call.method == 'onRecordEvent') {
      final args = call.arguments as Map<dynamic, dynamic>;
      onRecordEvent?.call(args.cast<String, dynamic>());
    } else if (call.method == 'onRecordingCancelled') {
      onRecordingCancelled?.call();
    }
  }

  // ── Recording ────────────────────────────────────────────

  Future<bool> startJournalRecording() async {
    try {
      final result = await _recordChannel.invokeMethod<bool>('startRecording');
      return result ?? false;
    } on PlatformException {
      return false;
    }
  }

  Future<void> stopJournalRecording() async {
    try {
      await _recordChannel.invokeMethod<void>('stopRecording');
    } on PlatformException {
      // ignore
    }
  }

  // ── Mouse ────────────────────────────────────────────────

  @override
  bool get isSupported => Platform.isWindows;

  @override
  Future<void> mouseMove(int x, int y) async {
    if (x < 0 || y < 0) return;
    SetCursorPos(x, y);
  }

  @override
  Future<void> mouseClick({
    required int x,
    required int y,
    String button = 'left',
    bool doubleClick = false,
  }) async {
    if (x >= 0 && y >= 0) {
      SetCursorPos(x, y);
    }
    final down = _down(button);
    final up = _up(button);
    _sendMouseInput(down);
    _sendMouseInput(up);
    if (doubleClick) {
      await Future.delayed(Duration(milliseconds: GetDoubleClickTime() ~/ 2));
      _sendMouseInput(down);
      _sendMouseInput(up);
    }
  }

  @override
  void syncClick({required int x, required int y, String button = 'left'}) {
    if (x >= 0 && y >= 0) {
      SetCursorPos(x, y);
    }
    _sendMouseInput(_down(button));
    _sendMouseInput(_up(button));
  }

  @override
  Future<void> mouseDown({
    required int x,
    required int y,
    String button = 'left',
  }) async {
    if (x >= 0 && y >= 0) {
      SetCursorPos(x, y);
    }
    _sendMouseInput(_down(button));
  }

  @override
  Future<void> mouseUp({
    required int x,
    required int y,
    String button = 'left',
  }) async {
    if (x >= 0 && y >= 0) {
      SetCursorPos(x, y);
    }
    _sendMouseInput(_up(button));
  }

  @override
  Future<void> mouseScroll({double dx = 0, double dy = 0}) async {
    if (dy != 0) {
      final p = calloc<INPUT>();
      p.ref.type = INPUT_MOUSE;
      p.ref.mi.dwFlags = MOUSEEVENTF_WHEEL;
      p.ref.mi.mouseData = (dy * 120).round();
      SendInput(1, p, sizeOf<INPUT>());
      calloc.free(p);
    }
  }

  MOUSE_EVENT_FLAGS _down(String b) => switch (b) {
        'right' => MOUSEEVENTF_RIGHTDOWN,
        'middle' => MOUSEEVENTF_MIDDLEDOWN,
        _ => MOUSEEVENTF_LEFTDOWN,
      };

  MOUSE_EVENT_FLAGS _up(String b) => switch (b) {
        'right' => MOUSEEVENTF_RIGHTUP,
        'middle' => MOUSEEVENTF_MIDDLEUP,
        _ => MOUSEEVENTF_LEFTUP,
      };

  void _sendMouseInput(MOUSE_EVENT_FLAGS flags) {
    final p = calloc<INPUT>();
    p.ref.type = INPUT_MOUSE;
    p.ref.mi.dwFlags = flags;
    SendInput(1, p, sizeOf<INPUT>());
    calloc.free(p);
  }

  // ── Keyboard ─────────────────────────────────────────────

  static const _vk = <String, int>{
    'enter': 0x0D,
    'tab': 0x09,
    'escape': 0x1B,
    'backspace': 0x08,
    'space': 0x20,
    'left': 0x25,
    'right': 0x27,
    'up': 0x26,
    'down': 0x28,
    'shift': 0x10,
    'ctrl': 0x11,
    'alt': 0x12,
    'delete': 0x2E,
    'insert': 0x2D,
    'home': 0x24,
    'end': 0x23,
    'pageup': 0x21,
    'pagedown': 0x22,
    'printscreen': 0x2C,
    'scrolllock': 0x91,
    'pause': 0x13,
    'capslock': 0x14,
    'numlock': 0x90,
    'win': 0x5B,
    'apps': 0x5D,
    'f1': 0x70,
    'f2': 0x71,
    'f3': 0x72,
    'f4': 0x73,
    'f5': 0x74,
    'f6': 0x75,
    'f7': 0x76,
    'f8': 0x77,
    'f9': 0x78,
    'f10': 0x79,
    'f11': 0x7A,
    'f12': 0x7B,
    'numpad0': 0x60,
    'numpad1': 0x61,
    'numpad2': 0x62,
    'numpad3': 0x63,
    'numpad4': 0x64,
    'numpad5': 0x65,
    'numpad6': 0x66,
    'numpad7': 0x67,
    'numpad8': 0x68,
    'numpad9': 0x69,
    'multiply': 0x6A,
    'add': 0x6B,
    'subtract': 0x6D,
    'decimal': 0x6E,
    'divide': 0x6F,
  };

  @override
  Future<void> keyPress(String key) async {
    final vk = _vk[key.toLowerCase()] ??
        (key.length == 1 ? key.toUpperCase().codeUnitAt(0) : null);
    if (vk == null) return;
    _sendKey(vk, KEYBD_EVENT_FLAGS(0));
  }

  @override
  Future<void> keyRelease(String key) async {
    final vk = _vk[key.toLowerCase()] ??
        (key.length == 1 ? key.toUpperCase().codeUnitAt(0) : null);
    if (vk == null) return;
    _sendKey(vk, KEYEVENTF_KEYUP);
  }

  @override
  Future<void> keyType(String text, {int delayMs = 30}) async {
    for (final c in text.split('')) {
      final p = calloc<INPUT>();
      p.ref.type = INPUT_KEYBOARD;
      p.ref.ki.wScan = c.codeUnitAt(0);
      p.ref.ki.dwFlags = KEYEVENTF_UNICODE;
      SendInput(1, p, sizeOf<INPUT>());
      p.ref.ki.dwFlags = KEYEVENTF_UNICODE | KEYEVENTF_KEYUP;
      SendInput(1, p, sizeOf<INPUT>());
      calloc.free(p);
      await Future.delayed(Duration(milliseconds: delayMs));
    }
  }

  void _sendKey(int vk, KEYBD_EVENT_FLAGS flags) {
    final p = calloc<INPUT>();
    p.ref.type = INPUT_KEYBOARD;
    p.ref.ki.wVk = VIRTUAL_KEY(vk);
    p.ref.ki.dwFlags = flags;
    SendInput(1, p, sizeOf<INPUT>());
    calloc.free(p);
  }

  // ── Hotkeys (System-level via RegisterHotKey) ────────────

  @override
  Stream<String> get globalKeyEvents => _keyController.stream;

  @override
  void startListening() {
    if (_listening) return;
    _listening = true;
    // Hotkeys are registered via registerHotkey() method, not here.
    // This method is kept for interface compatibility.
  }

  @override
  void stopListening() {
    _listening = false;
    unregisterAllHotkeys();
  }

  /// Register a system-level hotkey using RegisterHotKey Win32 API.
  /// [field] is the hotkey field name (e.g., 'startStopClicker').
  /// [hotkeyStr] is the hotkey string (e.g., 'Alt+F6').
  /// Returns true if registration succeeded.
  Future<bool> registerHotkey(String field, String hotkeyStr) async {
    // Support both named fields and numeric IDs (for per-macro hotkeys)
    int id;
    final numericId = int.tryParse(field);
    if (numericId != null) {
      id = numericId;
    } else {
      id = HotkeyConfig.fieldToId(field);
      if (id == 0) return false;
    }

    // Unregister previous hotkey for this field if any
    if (_registeredHotkeys.containsKey(field)) {
      await unregisterHotkey(field);
    }

    final parsed = HotkeyConfig.parseHotkey(hotkeyStr);
    try {
      final result = await _channel.invokeMethod<bool>('registerHotkey', [
        id,
        parsed.modifiers,
        parsed.vk,
      ]);
      if (result == true) {
        _registeredHotkeys[field] = id;
      }
      return result ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// Unregister a system-level hotkey.
  Future<bool> unregisterHotkey(String field) async {
    final id = _registeredHotkeys[field];
    if (id == null) return true;
    try {
      final result = await _channel.invokeMethod<bool>('unregisterHotkey', [id]);
      if (result == true) {
        _registeredHotkeys.remove(field);
      }
      return result ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// Unregister all system-level hotkeys.
  Future<void> unregisterAllHotkeys() async {
    if (_registeredHotkeys.isEmpty) return;
    try {
      await _channel.invokeMethod<void>('unregisterAll');
      _registeredHotkeys.clear();
    } on PlatformException {
      // ignore
    }
  }

  /// Check if the hotkey is still physically held down.
  /// Uses GetAsyncKeyState to poll the physical key state.
  Future<bool> isHotkeyStillHeld(String hotkeyStr) async {
    final parsed = HotkeyConfig.parseHotkey(hotkeyStr);
    final vk = parsed.vk;
    if (vk == 0) return false;

    // Check the main key
    final keyState = GetAsyncKeyState(vk);
    final keyHeld = (keyState & 0x8000) != 0;

    // Check modifiers
    final mods = parsed.modifiers;
    bool modsHeld = true;
    if (mods & 0x0001 != 0) { // MOD_ALT
      final altState = GetAsyncKeyState(0x12); // VK_MENU
      if ((altState & 0x8000) == 0) modsHeld = false;
    }
    if (mods & 0x0002 != 0) { // MOD_CONTROL
      final ctrlState = GetAsyncKeyState(0x11); // VK_CONTROL
      if ((ctrlState & 0x8000) == 0) modsHeld = false;
    }
    if (mods & 0x0004 != 0) { // MOD_SHIFT
      final shiftState = GetAsyncKeyState(0x10); // VK_SHIFT
      if ((shiftState & 0x8000) == 0) modsHeld = false;
    }
    if (mods & 0x0008 != 0) { // MOD_WIN
      final winState = GetAsyncKeyState(0x5B); // VK_LWIN
      if ((winState & 0x8000) == 0) modsHeld = false;
    }

    return keyHeld && modsHeld;
  }

  @override
  Future<({int height, int width})> getScreenSize() {
    final w = GetSystemMetrics(SM_CXSCREEN);
    final h = GetSystemMetrics(SM_CYSCREEN);
    return Future.value((width: w, height: h));
  }

  @override
  void dispose() {
    stopListening();
    _keyController.close();
  }

  @override
  Future<dynamic> invokeMethod(String method, [dynamic arguments]) {
    return _platformChannel.invokeMethod(method, arguments);
  }
}
