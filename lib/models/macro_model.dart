/// Macro model — records mouse/keyboard events for playback.
library;

import 'dart:convert';

enum MacroEventType {
  mouseDown,
  mouseUp,
  click,
  keyPress,
  keyRelease,
  scroll,
  wait,
}

class MacroEvent {
  final MacroEventType type;
  final int timestampMs; // ms since recording started
  final String? button; // left | right | middle (for click)
  final int? x;
  final int? y;
  final String? key; // key name (for keyPress/keyRelease)
  final double? scrollDx;
  final double? scrollDy;

  const MacroEvent({
    required this.type,
    required this.timestampMs,
    this.button,
    this.x,
    this.y,
    this.key,
    this.scrollDx,
    this.scrollDy,
  });

  factory MacroEvent.fromJson(Map<String, dynamic> json) {
    return MacroEvent(
      type: MacroEventType.values.firstWhere((e) => e.name == json['type']),
      timestampMs: json['timestampMs'] ?? 0,
      button: json['button'],
      x: json['x'],
      y: json['y'],
      key: json['key'],
      scrollDx: (json['scrollDx'] as num?)?.toDouble(),
      scrollDy: (json['scrollDy'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'timestampMs': timestampMs,
        if (button != null) 'button': button,
        if (x != null) 'x': x,
        if (y != null) 'y': y,
        if (key != null) 'key': key,
        if (scrollDx != null) 'scrollDx': scrollDx,
        if (scrollDy != null) 'scrollDy': scrollDy,
      };
}

class MacroModel {
  String id;
  String name;
  List<MacroEvent> events;
  int repeatCount; // 0 = infinite
  double speed; // 0.1 ~ 10.0
  DateTime createdAt;
  String? hotkey; // Per-macro hotkey, e.g. "Alt+F3"
  bool backgroundMode; // Use background click (requires background_execution plugin)
  int backgroundTargetHwnd; // Target window handle for background mode
  int backgroundTargetX; // Client area X for background mode
  int backgroundTargetY; // Client area Y for background mode
  String backgroundTargetWindowTitle; // Target window title (for display)

  MacroModel({
    required this.id,
    this.name = '未命名宏',
    List<MacroEvent>? events,
    this.repeatCount = 1,
    this.speed = 1.0,
    DateTime? createdAt,
    this.hotkey,
    this.backgroundMode = false,
    this.backgroundTargetHwnd = 0,
    this.backgroundTargetX = 0,
    this.backgroundTargetY = 0,
    this.backgroundTargetWindowTitle = '',
  })  : events = events ?? [],
        createdAt = createdAt ?? DateTime.now();

  int get totalDurationMs {
    if (events.isEmpty) return 0;
    return events.last.timestampMs;
  }

  factory MacroModel.fromJson(Map<String, dynamic> json) {
    return MacroModel(
      id: json['id'] ?? '',
      name: json['name'] ?? '未命名宏',
      events: (json['events'] as List<dynamic>?)
              ?.map((e) => MacroEvent.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      repeatCount: json['repeatCount'] ?? 1,
      speed: (json['speed'] as num?)?.toDouble() ?? 1.0,
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : DateTime.now(),
      hotkey: json['hotkey'] as String?,
      backgroundMode: json['backgroundMode'] ?? false,
      backgroundTargetHwnd: json['backgroundTargetHwnd'] ?? 0,
      backgroundTargetX: json['backgroundTargetX'] ?? 0,
      backgroundTargetY: json['backgroundTargetY'] ?? 0,
      backgroundTargetWindowTitle: json['backgroundTargetWindowTitle'] ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'events': events.map((e) => e.toJson()).toList(),
        'repeatCount': repeatCount,
        'speed': speed,
        'createdAt': createdAt.toIso8601String(),
        if (hotkey != null) 'hotkey': hotkey,
        'backgroundMode': backgroundMode,
        'backgroundTargetHwnd': backgroundTargetHwnd,
        'backgroundTargetX': backgroundTargetX,
        'backgroundTargetY': backgroundTargetY,
        'backgroundTargetWindowTitle': backgroundTargetWindowTitle,
      };

  String toJsonString() => jsonEncode(toJson());

  factory MacroModel.fromJsonString(String jsonStr) {
    return MacroModel.fromJson(jsonDecode(jsonStr) as Map<String, dynamic>);
  }

  MacroModel copyWith({
    String? name,
    List<MacroEvent>? events,
    int? repeatCount,
    double? speed,
    Object? hotkey = _notProvided,
    bool? backgroundMode,
    int? backgroundTargetHwnd,
    int? backgroundTargetX,
    int? backgroundTargetY,
    String? backgroundTargetWindowTitle,
  }) {
    return MacroModel(
      id: id,
      name: name ?? this.name,
      events: events ?? List.from(this.events),
      repeatCount: repeatCount ?? this.repeatCount,
      speed: speed ?? this.speed,
      createdAt: createdAt,
      hotkey: hotkey == _notProvided ? this.hotkey : hotkey as String?,
      backgroundMode: backgroundMode ?? this.backgroundMode,
      backgroundTargetHwnd: backgroundTargetHwnd ?? this.backgroundTargetHwnd,
      backgroundTargetX: backgroundTargetX ?? this.backgroundTargetX,
      backgroundTargetY: backgroundTargetY ?? this.backgroundTargetY,
      backgroundTargetWindowTitle: backgroundTargetWindowTitle ?? this.backgroundTargetWindowTitle,
    );
  }

  static const _notProvided = Object();
}
