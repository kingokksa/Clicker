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
  bool humanLikeRandomPause;
  int humanLikePauseChance;
  int humanLikePauseMinMs;
  int humanLikePauseMaxMs;

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
    this.humanLikeRandomPause = true,
    this.humanLikePauseChance = 5,
    this.humanLikePauseMinMs = 200,
    this.humanLikePauseMaxMs = 800,
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
    bool? humanLikeRandomPause,
    int? humanLikePauseChance,
    int? humanLikePauseMinMs,
    int? humanLikePauseMaxMs,
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
    humanLikeRandomPause: humanLikeRandomPause ?? this.humanLikeRandomPause,
    humanLikePauseChance: humanLikePauseChance ?? this.humanLikePauseChance,
    humanLikePauseMinMs: humanLikePauseMinMs ?? this.humanLikePauseMinMs,
    humanLikePauseMaxMs: humanLikePauseMaxMs ?? this.humanLikePauseMaxMs,
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
    'humanLikeRandomPause': humanLikeRandomPause,
    'humanLikePauseChance': humanLikePauseChance,
    'humanLikePauseMinMs': humanLikePauseMinMs,
    'humanLikePauseMaxMs': humanLikePauseMaxMs,
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
    humanLikeRandomPause: json['humanLikeRandomPause'] as bool? ?? true,
    humanLikePauseChance: (json['humanLikePauseChance'] as num?)?.toInt() ?? 5,
    humanLikePauseMinMs: (json['humanLikePauseMinMs'] as num?)?.toInt() ?? 200,
    humanLikePauseMaxMs: (json['humanLikePauseMaxMs'] as num?)?.toInt() ?? 800,
  );

  factory ClickSettings.fromConfig(ClickerConfig config) => ClickSettings(
    intervalMs: config.intervalMs.toInt(),
    mouseButton: config.mouseButton,
    doubleClick: config.clickType == ClickType.double,
    holdMs: config.clickHoldMs,
    randomDelayEnabled: config.randomDelayMinMs > 0 || config.randomDelayMaxMs > 0,
    randomDelayMinMs: config.randomDelayMinMs > 0 ? config.randomDelayMinMs : 10,
    randomDelayMaxMs: config.randomDelayMaxMs > 0 ? config.randomDelayMaxMs : 50,
    randomOffsetEnabled: config.randomOffsetEnabled,
    randomOffsetMinPx: config.randomOffsetMinPx,
    randomOffsetMaxPx: config.randomOffsetMaxPx,
    humanLikeEnabled: config.humanLikeEnabled,
    humanLikeBezierCurve: config.humanLikeBezierCurve,
    humanLikeRandomPause: config.humanLikeRandomPause,
    humanLikePauseChance: config.humanLikePauseChance,
    humanLikePauseMinMs: config.humanLikePauseMinMs,
    humanLikePauseMaxMs: config.humanLikePauseMaxMs,
  );

  ClickerConfig applyTo(ClickerConfig config) => config.copyWith(
    intervalMs: intervalMs.toDouble(),
    mouseButton: mouseButton,
    clickType: (config.clickType == ClickType.single || config.clickType == ClickType.double)
        ? (doubleClick ? ClickType.double : ClickType.single)
        : config.clickType,
    clickHoldMs: holdMs,
    randomDelayMinMs: randomDelayEnabled ? randomDelayMinMs : 0,
    randomDelayMaxMs: randomDelayEnabled ? randomDelayMaxMs : 0,
    randomOffsetEnabled: randomOffsetEnabled,
    randomOffsetMinPx: randomOffsetMinPx,
    randomOffsetMaxPx: randomOffsetMaxPx,
    humanLikeEnabled: humanLikeEnabled,
    humanLikeBezierCurve: humanLikeBezierCurve,
    humanLikeRandomPause: humanLikeRandomPause,
    humanLikePauseChance: humanLikePauseChance,
    humanLikePauseMinMs: humanLikePauseMinMs,
    humanLikePauseMaxMs: humanLikePauseMaxMs,
  );
}
