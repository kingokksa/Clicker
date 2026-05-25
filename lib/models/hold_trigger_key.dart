/// Hold trigger key model — each key can be individually configured.
/// When the trigger key is held down, the configured action auto-repeats.
library;

import 'dart:math';

enum HoldTriggerAction {
  mouseClick,   // mouse click (left/right/middle)
  keyRepeat,    // repeat a key press
  keyCombo,     // key combination
}

class HoldTriggerKey {
  final String id;
  String triggerKey;       // e.g. "F5", "Q", "1"
  bool enabled;

  // Action type
  HoldTriggerAction action;

  // Mouse click settings (when action == mouseClick)
  String mouseButton;     // "left", "right", "middle"

  // Key repeat settings (when action == keyRepeat)
  String keyToRepeat;     // e.g. "space", "A"

  // Key combo settings (when action == keyCombo)
  List<String> comboKeys; // e.g. ["ctrl", "A"]

  // Common settings
  double intervalMs;      // repeat interval in ms (min 10)
  bool backgroundMode;    // use background click if available

  // Background mode target
  int targetHwnd;         // target window handle
  int targetX;            // client area x
  int targetY;            // client area y

  HoldTriggerKey({
    String? id,
    this.triggerKey = 'F5',
    this.enabled = true,
    this.action = HoldTriggerAction.mouseClick,
    this.mouseButton = 'left',
    this.keyToRepeat = 'space',
    this.comboKeys = const [],
    this.intervalMs = 50,
    this.backgroundMode = false,
    this.targetHwnd = 0,
    this.targetX = 0,
    this.targetY = 0,
  }) : id = id ?? _generateId();

  static String _generateId() {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final rng = Random();
    return String.fromCharCodes(
      Iterable.generate(8, (_) => chars.codeUnitAt(rng.nextInt(chars.length))),
    );
  }

  factory HoldTriggerKey.fromJson(Map<String, dynamic> json) {
    return HoldTriggerKey(
      id: json['id'],
      triggerKey: json['triggerKey'] ?? 'F5',
      enabled: json['enabled'] ?? true,
      action: HoldTriggerAction.values.firstWhere(
        (e) => e.name == json['action'],
        orElse: () => HoldTriggerAction.mouseClick,
      ),
      mouseButton: json['mouseButton'] ?? 'left',
      keyToRepeat: json['keyToRepeat'] ?? 'space',
      comboKeys: (json['comboKeys'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      intervalMs: (json['intervalMs'] as num?)?.toDouble() ?? 50,
      backgroundMode: json['backgroundMode'] ?? false,
      targetHwnd: json['targetHwnd'] ?? 0,
      targetX: json['targetX'] ?? 0,
      targetY: json['targetY'] ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'triggerKey': triggerKey,
        'enabled': enabled,
        'action': action.name,
        'mouseButton': mouseButton,
        'keyToRepeat': keyToRepeat,
        'comboKeys': comboKeys,
        'intervalMs': intervalMs,
        'backgroundMode': backgroundMode,
        'targetHwnd': targetHwnd,
        'targetX': targetX,
        'targetY': targetY,
      };

  HoldTriggerKey copyWith({
    String? triggerKey,
    bool? enabled,
    HoldTriggerAction? action,
    String? mouseButton,
    String? keyToRepeat,
    List<String>? comboKeys,
    double? intervalMs,
    bool? backgroundMode,
    int? targetHwnd,
    int? targetX,
    int? targetY,
  }) {
    return HoldTriggerKey(
      id: id,
      triggerKey: triggerKey ?? this.triggerKey,
      enabled: enabled ?? this.enabled,
      action: action ?? this.action,
      mouseButton: mouseButton ?? this.mouseButton,
      keyToRepeat: keyToRepeat ?? this.keyToRepeat,
      comboKeys: comboKeys ?? this.comboKeys,
      intervalMs: (intervalMs ?? this.intervalMs).clamp(10.0, double.infinity),
      backgroundMode: backgroundMode ?? this.backgroundMode,
      targetHwnd: targetHwnd ?? this.targetHwnd,
      targetX: targetX ?? this.targetX,
      targetY: targetY ?? this.targetY,
    );
  }
}
