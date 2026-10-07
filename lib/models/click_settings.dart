import 'clicker_config.dart';

class ClickSettings {
  int intervalMs;
  MouseButton mouseButton;
  bool doubleClick;
  int holdMs;
  bool randomDelayEnabled;
  int randomDelayMinMs;
  int randomDelayMaxMs;
  bool randomOffsetEnabled;
  int randomOffsetMinPx;
  int randomOffsetMaxPx;
  bool humanLikeEnabled;
  bool humanLikeBezierCurve;

  ClickSettings({
    this.intervalMs = 200,
    this.mouseButton = MouseButton.left,
    this.doubleClick = false,
    this.holdMs = 0,
    this.randomDelayEnabled = false,
    this.randomDelayMinMs = 10,
    this.randomDelayMaxMs = 50,
    this.randomOffsetEnabled = false,
    this.randomOffsetMinPx = 1,
    this.randomOffsetMaxPx = 5,
    this.humanLikeEnabled = false,
    this.humanLikeBezierCurve = false,
  });

  ClickSettings copyWith({
    int? intervalMs,
    MouseButton? mouseButton,
    bool? doubleClick,
    int? holdMs,
    bool? randomDelayEnabled,
    int? randomDelayMinMs,
    int? randomDelayMaxMs,
    bool? randomOffsetEnabled,
    int? randomOffsetMinPx,
    int? randomOffsetMaxPx,
    bool? humanLikeEnabled,
    bool? humanLikeBezierCurve,
  }) => ClickSettings(
    intervalMs: intervalMs ?? this.intervalMs,
    mouseButton: mouseButton ?? this.mouseButton,
    doubleClick: doubleClick ?? this.doubleClick,
    holdMs: holdMs ?? this.holdMs,
    randomDelayEnabled: randomDelayEnabled ?? this.randomDelayEnabled,
    randomDelayMinMs: randomDelayMinMs ?? this.randomDelayMinMs,
    randomDelayMaxMs: randomDelayMaxMs ?? this.randomDelayMaxMs,
    randomOffsetEnabled: randomOffsetEnabled ?? this.randomOffsetEnabled,
    randomOffsetMinPx: randomOffsetMinPx ?? this.randomOffsetMinPx,
    randomOffsetMaxPx: randomOffsetMaxPx ?? this.randomOffsetMaxPx,
    humanLikeEnabled: humanLikeEnabled ?? this.humanLikeEnabled,
    humanLikeBezierCurve: humanLikeBezierCurve ?? this.humanLikeBezierCurve,
  );

  Map<String, dynamic> toJson() => {
    'intervalMs': intervalMs,
    'mouseButton': mouseButton.name,
    'doubleClick': doubleClick,
    'holdMs': holdMs,
    'randomDelayEnabled': randomDelayEnabled,
    'randomDelayMinMs': randomDelayMinMs,
    'randomDelayMaxMs': randomDelayMaxMs,
    'randomOffsetEnabled': randomOffsetEnabled,
    'randomOffsetMinPx': randomOffsetMinPx,
    'randomOffsetMaxPx': randomOffsetMaxPx,
    'humanLikeEnabled': humanLikeEnabled,
    'humanLikeBezierCurve': humanLikeBezierCurve,
  };

  factory ClickSettings.fromJson(Map<String, dynamic> json) => ClickSettings(
    intervalMs: (json['intervalMs'] as num?)?.toInt() ?? 200,
    mouseButton: MouseButton.values.firstWhere(
      (b) => b.name == json['mouseButton'],
      orElse: () => MouseButton.left,
    ),
    doubleClick: json['doubleClick'] as bool? ?? false,
    holdMs: (json['holdMs'] as num?)?.toInt() ?? 0,
    randomDelayEnabled: json['randomDelayEnabled'] as bool? ?? false,
    randomDelayMinMs: (json['randomDelayMinMs'] as num?)?.toInt() ?? 10,
    randomDelayMaxMs: (json['randomDelayMaxMs'] as num?)?.toInt() ?? 50,
    randomOffsetEnabled: json['randomOffsetEnabled'] as bool? ?? false,
    randomOffsetMinPx: (json['randomOffsetMinPx'] as num?)?.toInt() ?? 1,
    randomOffsetMaxPx: (json['randomOffsetMaxPx'] as num?)?.toInt() ?? 5,
    humanLikeEnabled: json['humanLikeEnabled'] as bool? ?? false,
    humanLikeBezierCurve: json['humanLikeBezierCurve'] as bool? ?? false,
  );
}
