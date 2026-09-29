
import 'dart:math';

enum HoldTriggerAction {
  mouseClick,
  keyRepeat,
  keyCombo,
  touchTap,
  touchLongPress,
}

enum HoldTriggerType {
  keyboard,
  mouse,
}

class HoldTriggerKey {
  final String id;
  String triggerKey;
  HoldTriggerType triggerType;
  String triggerMouseButton;
  bool enabled;

  HoldTriggerAction action;

  String mouseButton;

  String keyToRepeat;

  List<String> comboKeys;

  double intervalMs;
  bool backgroundMode;

  int targetHwnd;
  int targetX;
  int targetY;
  String targetWindowTitle;

  HoldTriggerKey({
    String? id,
    this.triggerKey = 'F5',
    this.triggerType = HoldTriggerType.keyboard,
    this.triggerMouseButton = 'left',
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
    this.targetWindowTitle = '',
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
      triggerType: HoldTriggerType.values.firstWhere(
        (e) => e.name == json['triggerType'],
        orElse: () => HoldTriggerType.keyboard,
      ),
      triggerMouseButton: json['triggerMouseButton'] ?? 'left',
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
      targetWindowTitle: json['targetWindowTitle'] ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'triggerKey': triggerKey,
        'triggerType': triggerType.name,
        'triggerMouseButton': triggerMouseButton,
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
        'targetWindowTitle': targetWindowTitle,
      };

  HoldTriggerKey copyWith({
    String? triggerKey,
    HoldTriggerType? triggerType,
    String? triggerMouseButton,
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
    String? targetWindowTitle,
  }) {
    return HoldTriggerKey(
      id: id,
      triggerKey: triggerKey ?? this.triggerKey,
      triggerType: triggerType ?? this.triggerType,
      triggerMouseButton: triggerMouseButton ?? this.triggerMouseButton,
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
      targetWindowTitle: targetWindowTitle ?? this.targetWindowTitle,
    );
  }
}
