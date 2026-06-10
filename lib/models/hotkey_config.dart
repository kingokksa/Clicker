/// Hotkey configuration model.
/// Supports modifier key combinations: "Alt+F6", "Ctrl+Shift+F12", etc.
library;

class HotkeyConfig {
  /// Hotkey string format: "Key" or "Mod1+Mod2+Key"
  /// Examples: "F6", "Alt+F6", "Ctrl+Shift+F12"
  String startStopClicker;
  String startStopRecording;
  String emergencyStop;
  String playMacro;
  String holdTrigger;
  String backgroundClick;

  HotkeyConfig({
    this.startStopClicker = 'Alt+F6',
    this.startStopRecording = 'Alt+F8',
    this.emergencyStop = 'Alt+F12',
    this.playMacro = 'Alt+F9',
    this.holdTrigger = 'F5',
    this.backgroundClick = 'Alt+F7',
  });

  factory HotkeyConfig.fromJson(Map<String, dynamic> json) {
    return HotkeyConfig(
      startStopClicker: json['startStopClicker'] ?? 'Alt+F6',
      startStopRecording: json['startStopRecording'] ?? 'Alt+F8',
      emergencyStop: json['emergencyStop'] ?? 'Alt+F12',
      playMacro: json['playMacro'] ?? 'Alt+F9',
      holdTrigger: json['holdTrigger'] ?? 'F5',
      backgroundClick: json['backgroundClick'] ?? 'Alt+F7',
    );
  }

  Map<String, dynamic> toJson() => {
        'startStopClicker': startStopClicker,
        'startStopRecording': startStopRecording,
        'emergencyStop': emergencyStop,
        'playMacro': playMacro,
        'holdTrigger': holdTrigger,
        'backgroundClick': backgroundClick,
      };

  HotkeyConfig copyWith({
    String? startStopClicker,
    String? startStopRecording,
    String? emergencyStop,
    String? playMacro,
    String? holdTrigger,
    String? backgroundClick,
  }) {
    return HotkeyConfig(
      startStopClicker: startStopClicker ?? this.startStopClicker,
      startStopRecording: startStopRecording ?? this.startStopRecording,
      emergencyStop: emergencyStop ?? this.emergencyStop,
      playMacro: playMacro ?? this.playMacro,
      holdTrigger: holdTrigger ?? this.holdTrigger,
      backgroundClick: backgroundClick ?? this.backgroundClick,
    );
  }

  /// Parse a hotkey string into Win32 modifier flags and virtual key code.
  /// Returns (modifiers, vkCode).
  static ({int modifiers, int vk}) parseHotkey(String hotkey) {
    final parts = hotkey.split('+').map((p) => p.trim()).toList();
    int modifiers = 0;
    String keyPart = parts.last;

    for (int i = 0; i < parts.length - 1; i++) {
      final mod = parts[i].toLowerCase();
      switch (mod) {
        case 'alt':
          modifiers |= 0x0001; // MOD_ALT
          break;
        case 'ctrl':
        case 'control':
          modifiers |= 0x0002; // MOD_CONTROL
          break;
        case 'shift':
          modifiers |= 0x0004; // MOD_SHIFT
          break;
        case 'win':
        case 'super':
          modifiers |= 0x0008; // MOD_WIN
          break;
      }
    }

    final vk = _keyToVk(keyPart);
    return (modifiers: modifiers, vk: vk);
  }

  /// Map key name to Windows virtual key code.
  static int _keyToVk(String key) {
    const fKeys = {
      'F1': 0x70, 'F2': 0x71, 'F3': 0x72, 'F4': 0x73,
      'F5': 0x74, 'F6': 0x75, 'F7': 0x76, 'F8': 0x77,
      'F9': 0x78, 'F10': 0x79, 'F11': 0x7A, 'F12': 0x7B,
    };
    const specialKeys = {
      'Space': 0x20, 'Enter': 0x0D, 'Tab': 0x09, 'Escape': 0x1B,
      'Backspace': 0x08, 'Delete': 0x2E, 'Insert': 0x2D,
      'Home': 0x24, 'End': 0x23, 'PageUp': 0x21, 'PageDown': 0x22,
      'Up': 0x26, 'Down': 0x28, 'Left': 0x25, 'Right': 0x27,
    };
    const numKeys = {
      '0': 0x30, '1': 0x31, '2': 0x32, '3': 0x33, '4': 0x34,
      '5': 0x35, '6': 0x36, '7': 0x37, '8': 0x38, '9': 0x39,
    };
    final upper = key.toUpperCase();
    if (fKeys.containsKey(upper)) return fKeys[upper]!;
    if (specialKeys.containsKey(key)) return specialKeys[key]!;
    if (numKeys.containsKey(key)) return numKeys[key]!;
    // Single letter key A-Z: 0x41 + offset
    if (upper.length == 1 && upper.codeUnitAt(0) >= 65 && upper.codeUnitAt(0) <= 90) {
      return upper.codeUnitAt(0);
    }
    return 0;
  }

  /// Available modifier options for hotkey configuration.
  static const List<String> modifiers = ['Alt', 'Ctrl', 'Shift', 'Win'];

  /// Available key options for hotkey configuration.
  static const List<String> keys = [
    'F1', 'F2', 'F3', 'F4', 'F5', 'F6',
    'F7', 'F8', 'F9', 'F10', 'F11', 'F12',
    'Space', 'Enter', 'Tab', 'Escape', 'Backspace',
    'Delete', 'Insert', 'Home', 'End',
    'PageUp', 'PageDown',
    'Up', 'Down', 'Left', 'Right',
    '0', '1', '2', '3', '4', '5', '6', '7', '8', '9',
    'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J',
    'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T',
    'U', 'V', 'W', 'X', 'Y', 'Z',
  ];

  /// Build a hotkey string from modifier list and key.
  static String buildHotkey(List<String> mods, String key) {
    if (mods.isEmpty) return key;
    return '${mods.join('+')}+$key';
  }

  /// Parse a hotkey string into modifier list and key.
  static ({List<String> mods, String key}) splitHotkey(String hotkey) {
    final parts = hotkey.split('+').map((p) => p.trim()).toList();
    if (parts.isEmpty) return (mods: [], key: 'F6');
    return (mods: parts.sublist(0, parts.length - 1), key: parts.last);
  }

  /// Map hotkey field name to numeric ID for RegisterHotKey.
  static int fieldToId(String field) {
    switch (field) {
      case 'startStopClicker':
        return 1;
      case 'startStopRecording':
        return 2;
      case 'emergencyStop':
        return 3;
      case 'playMacro':
        return 4;
      case 'holdTrigger':
        return 5;
      case 'backgroundClick':
        return 6;
      default:
        return 0;
    }
  }

  /// Map numeric ID back to field name.
  static String idToField(int id) {
    switch (id) {
      case 1:
        return 'startStopClicker';
      case 2:
        return 'startStopRecording';
      case 3:
        return 'emergencyStop';
      case 4:
        return 'playMacro';
      case 5:
        return 'holdTrigger';
      case 6:
        return 'backgroundClick';
      default:
        return '';
    }
  }
}
