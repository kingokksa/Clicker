/// Auto-clicker configuration model.
/// Supports both mouse and keyboard click modes with advanced features.
library;

import 'package:collection/collection.dart';

enum ClickType { single, double }

enum ClickMode { mouse, keyboard }

enum MouseButton { left, right, middle }

enum PositionMode { current, fixed }

enum ClickRepeatMode { infinite, count, duration }

enum KeyActionMode {
  repeat,    // repeat single key press
  hold,      // hold key down
  sequence,  // press key sequence
  combo,     // key combination (press together)
  text,      // auto-type text
}

class KeySequenceItem {
  final String key;
  final int delayMs;

  const KeySequenceItem({required this.key, this.delayMs = 50});

  Map<String, dynamic> toJson() => {'key': key, 'delayMs': delayMs};

  factory KeySequenceItem.fromJson(Map<String, dynamic> json) {
    return KeySequenceItem(
      key: json['key'] ?? 'space',
      delayMs: json['delayMs'] ?? 50,
    );
  }
}

class ClickerConfig {
  ClickMode clickMode;
  ClickType clickType;
  MouseButton mouseButton;
  PositionMode positionMode;
  int fixedX;
  int fixedY;
  double intervalMs;
  ClickRepeatMode repeatMode;
  int repeatCount;
  int durationSeconds;

  // Keyboard-specific
  String keyToRepeat;
  bool holdKey;
  KeyActionMode keyActionMode;

  // Key sequence
  List<KeySequenceItem> keySequence;

  // Key combo (keys pressed together)
  List<String> comboKeys;

  // Text to auto-type
  String textToType;
  int textTypeDelayMs;

  // Random delay range (0 = no random)
  int randomDelayMinMs;
  int randomDelayMaxMs;

  // Anti-detection: jitter on key press timing
  bool jitterEnabled;
  int jitterMinMs;
  int jitterMaxMs;

  // Random offset for mouse click position (pixels)
  bool randomOffsetEnabled;
  int randomOffsetMinPx;
  int randomOffsetMaxPx;

  // Hold-trigger: when enabled, holding the trigger key runs the clicker
  bool holdTriggerEnabled;
  String holdTriggerKey; // e.g. "F5", "Alt+F5"

  // Feature toggles
  bool autoClickEnabled;
  bool smartDelayEnabled;
  bool humanLikeEnabled;
  bool soundFeedbackEnabled;
  bool statsEnabled;
  bool imageRecognitionEnabled;
  bool windowAutoDetectEnabled;
  bool scriptEngineEnabled;
  bool remoteControlEnabled;

  // Background execution
  bool backgroundExecutionEnabled;
  bool silentStartEnabled;
  bool antiInterferenceEnabled;
  bool autoStartEnabled;
  bool autoStartSilent;
  bool taskQueueEnabled;
  bool taskNotificationEnabled;
  bool autoRetryEnabled;

  // Background click target
  int targetHwnd;         // target window handle (0 = none)
  String targetWindowTitle; // display name of target window
  int targetClientX;      // click X relative to target client area
  int targetClientY;      // click Y relative to target client area

  ClickerConfig({
    this.clickMode = ClickMode.mouse,
    this.clickType = ClickType.single,
    this.mouseButton = MouseButton.left,
    this.positionMode = PositionMode.current,
    this.fixedX = 0,
    this.fixedY = 0,
    this.intervalMs = 100,
    this.repeatMode = ClickRepeatMode.infinite,
    this.repeatCount = 100,
    this.durationSeconds = 60,
    this.keyToRepeat = 'space',
    this.holdKey = false,
    this.keyActionMode = KeyActionMode.repeat,
    this.keySequence = const [],
    this.comboKeys = const [],
    this.textToType = '',
    this.textTypeDelayMs = 50,
    this.randomDelayMinMs = 0,
    this.randomDelayMaxMs = 0,
    this.jitterEnabled = false,
    this.jitterMinMs = 5,
    this.jitterMaxMs = 30,
    this.randomOffsetEnabled = false,
    this.randomOffsetMinPx = 1,
    this.randomOffsetMaxPx = 5,
    this.holdTriggerEnabled = false,
    this.holdTriggerKey = 'F5',
    this.autoClickEnabled = true,
    this.smartDelayEnabled = false,
    this.humanLikeEnabled = false,
    this.soundFeedbackEnabled = false,
    this.statsEnabled = true,
    this.imageRecognitionEnabled = false,
    this.windowAutoDetectEnabled = false,
    this.scriptEngineEnabled = false,
    this.remoteControlEnabled = false,
    this.backgroundExecutionEnabled = false,
    this.silentStartEnabled = false,
    this.antiInterferenceEnabled = false,
    this.autoStartEnabled = false,
    this.autoStartSilent = false,
    this.taskQueueEnabled = false,
    this.taskNotificationEnabled = true,
    this.autoRetryEnabled = false,
    this.targetHwnd = 0,
    this.targetWindowTitle = '',
    this.targetClientX = 0,
    this.targetClientY = 0,
  });

  factory ClickerConfig.fromJson(Map<String, dynamic> json) {
    return ClickerConfig(
      clickMode: ClickMode.values.firstWhereOrNull(
            (e) => e.name == json['clickMode'],
          ) ??
          ClickMode.mouse,
      clickType: ClickType.values.firstWhereOrNull(
            (e) => e.name == json['clickType'],
          ) ??
          ClickType.single,
      mouseButton: MouseButton.values.firstWhereOrNull(
            (e) => e.name == json['mouseButton'],
          ) ??
          MouseButton.left,
      positionMode: PositionMode.values.firstWhereOrNull(
            (e) => e.name == json['positionMode'],
          ) ??
          PositionMode.current,
      fixedX: json['fixedX'] ?? 0,
      fixedY: json['fixedY'] ?? 0,
      intervalMs: (json['intervalMs'] as num?)?.toDouble() ?? 100,
      repeatMode: ClickRepeatMode.values.firstWhereOrNull(
            (e) => e.name == json['repeatMode'],
          ) ??
          ClickRepeatMode.infinite,
      repeatCount: json['repeatCount'] ?? 100,
      durationSeconds: json['durationSeconds'] ?? 60,
      keyToRepeat: json['keyToRepeat'] ?? 'space',
      holdKey: json['holdKey'] ?? false,
      keyActionMode: KeyActionMode.values.firstWhereOrNull(
            (e) => e.name == json['keyActionMode'],
          ) ??
          KeyActionMode.repeat,
      keySequence: (json['keySequence'] as List<dynamic>?)
              ?.map((e) => KeySequenceItem.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      comboKeys: (json['comboKeys'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      textToType: json['textToType'] ?? '',
      textTypeDelayMs: json['textTypeDelayMs'] ?? 50,
      randomDelayMinMs: json['randomDelayMinMs'] ?? 0,
      randomDelayMaxMs: json['randomDelayMaxMs'] ?? 0,
      jitterEnabled: json['jitterEnabled'] ?? false,
      jitterMinMs: json['jitterMinMs'] ?? 5,
      jitterMaxMs: json['jitterMaxMs'] ?? 30,
      randomOffsetEnabled: json['randomOffsetEnabled'] ?? false,
      randomOffsetMinPx: json['randomOffsetMinPx'] ?? 1,
      randomOffsetMaxPx: json['randomOffsetMaxPx'] ?? 5,
      holdTriggerEnabled: json['holdTriggerEnabled'] ?? false,
      holdTriggerKey: json['holdTriggerKey'] ?? 'F5',
      autoClickEnabled: json['autoClickEnabled'] ?? true,
      smartDelayEnabled: json['smartDelayEnabled'] ?? false,
      humanLikeEnabled: json['humanLikeEnabled'] ?? false,
      soundFeedbackEnabled: json['soundFeedbackEnabled'] ?? false,
      statsEnabled: json['statsEnabled'] ?? true,
      imageRecognitionEnabled: json['imageRecognitionEnabled'] ?? false,
      windowAutoDetectEnabled: json['windowAutoDetectEnabled'] ?? false,
      scriptEngineEnabled: json['scriptEngineEnabled'] ?? false,
      remoteControlEnabled: json['remoteControlEnabled'] ?? false,
      backgroundExecutionEnabled: json['backgroundExecutionEnabled'] ?? false,
      silentStartEnabled: json['silentStartEnabled'] ?? false,
      antiInterferenceEnabled: json['antiInterferenceEnabled'] ?? false,
      autoStartEnabled: json['autoStartEnabled'] ?? false,
      autoStartSilent: json['autoStartSilent'] ?? false,
      taskQueueEnabled: json['taskQueueEnabled'] ?? false,
      taskNotificationEnabled: json['taskNotificationEnabled'] ?? true,
      autoRetryEnabled: json['autoRetryEnabled'] ?? false,
      targetHwnd: json['targetHwnd'] ?? 0,
      targetWindowTitle: json['targetWindowTitle'] ?? '',
      targetClientX: json['targetClientX'] ?? 0,
      targetClientY: json['targetClientY'] ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'clickMode': clickMode.name,
        'clickType': clickType.name,
        'mouseButton': mouseButton.name,
        'positionMode': positionMode.name,
        'fixedX': fixedX,
        'fixedY': fixedY,
        'intervalMs': intervalMs,
        'repeatMode': repeatMode.name,
        'repeatCount': repeatCount,
        'durationSeconds': durationSeconds,
        'keyToRepeat': keyToRepeat,
        'holdKey': holdKey,
        'keyActionMode': keyActionMode.name,
        'keySequence': keySequence.map((e) => e.toJson()).toList(),
        'comboKeys': comboKeys,
        'textToType': textToType,
        'textTypeDelayMs': textTypeDelayMs,
        'randomDelayMinMs': randomDelayMinMs,
        'randomDelayMaxMs': randomDelayMaxMs,
        'jitterEnabled': jitterEnabled,
        'jitterMinMs': jitterMinMs,
        'jitterMaxMs': jitterMaxMs,
        'randomOffsetEnabled': randomOffsetEnabled,
        'randomOffsetMinPx': randomOffsetMinPx,
        'randomOffsetMaxPx': randomOffsetMaxPx,
        'holdTriggerEnabled': holdTriggerEnabled,
        'holdTriggerKey': holdTriggerKey,
        'autoClickEnabled': autoClickEnabled,
        'smartDelayEnabled': smartDelayEnabled,
        'humanLikeEnabled': humanLikeEnabled,
        'soundFeedbackEnabled': soundFeedbackEnabled,
        'statsEnabled': statsEnabled,
        'imageRecognitionEnabled': imageRecognitionEnabled,
        'windowAutoDetectEnabled': windowAutoDetectEnabled,
        'scriptEngineEnabled': scriptEngineEnabled,
        'remoteControlEnabled': remoteControlEnabled,
        'backgroundExecutionEnabled': backgroundExecutionEnabled,
        'silentStartEnabled': silentStartEnabled,
        'antiInterferenceEnabled': antiInterferenceEnabled,
        'autoStartEnabled': autoStartEnabled,
        'autoStartSilent': autoStartSilent,
        'taskQueueEnabled': taskQueueEnabled,
        'taskNotificationEnabled': taskNotificationEnabled,
        'autoRetryEnabled': autoRetryEnabled,
        'targetHwnd': targetHwnd,
        'targetWindowTitle': targetWindowTitle,
        'targetClientX': targetClientX,
        'targetClientY': targetClientY,
      };

  ClickerConfig copyWith({
    ClickMode? clickMode,
    ClickType? clickType,
    MouseButton? mouseButton,
    PositionMode? positionMode,
    int? fixedX,
    int? fixedY,
    double? intervalMs,
    ClickRepeatMode? repeatMode,
    int? repeatCount,
    int? durationSeconds,
    String? keyToRepeat,
    bool? holdKey,
    KeyActionMode? keyActionMode,
    List<KeySequenceItem>? keySequence,
    List<String>? comboKeys,
    String? textToType,
    int? textTypeDelayMs,
    int? randomDelayMinMs,
    int? randomDelayMaxMs,
    bool? jitterEnabled,
    int? jitterMinMs,
    int? jitterMaxMs,
    bool? randomOffsetEnabled,
    int? randomOffsetMinPx,
    int? randomOffsetMaxPx,
    bool? holdTriggerEnabled,
    String? holdTriggerKey,
    bool? autoClickEnabled,
    bool? smartDelayEnabled,
    bool? humanLikeEnabled,
    bool? soundFeedbackEnabled,
    bool? statsEnabled,
    bool? imageRecognitionEnabled,
    bool? windowAutoDetectEnabled,
    bool? scriptEngineEnabled,
    bool? remoteControlEnabled,
    bool? backgroundExecutionEnabled,
    bool? silentStartEnabled,
    bool? antiInterferenceEnabled,
    bool? autoStartEnabled,
    bool? autoStartSilent,
    bool? taskQueueEnabled,
    bool? taskNotificationEnabled,
    bool? autoRetryEnabled,
    int? targetHwnd,
    String? targetWindowTitle,
    int? targetClientX,
    int? targetClientY,
  }) {
    return ClickerConfig(
      clickMode: clickMode ?? this.clickMode,
      clickType: clickType ?? this.clickType,
      mouseButton: mouseButton ?? this.mouseButton,
      positionMode: positionMode ?? this.positionMode,
      fixedX: fixedX ?? this.fixedX,
      fixedY: fixedY ?? this.fixedY,
      intervalMs: intervalMs ?? this.intervalMs,
      repeatMode: repeatMode ?? this.repeatMode,
      repeatCount: repeatCount ?? this.repeatCount,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      keyToRepeat: keyToRepeat ?? this.keyToRepeat,
      holdKey: holdKey ?? this.holdKey,
      keyActionMode: keyActionMode ?? this.keyActionMode,
      keySequence: keySequence ?? this.keySequence,
      comboKeys: comboKeys ?? this.comboKeys,
      textToType: textToType ?? this.textToType,
      textTypeDelayMs: textTypeDelayMs ?? this.textTypeDelayMs,
      randomDelayMinMs: randomDelayMinMs ?? this.randomDelayMinMs,
      randomDelayMaxMs: randomDelayMaxMs ?? this.randomDelayMaxMs,
      jitterEnabled: jitterEnabled ?? this.jitterEnabled,
      jitterMinMs: jitterMinMs ?? this.jitterMinMs,
      jitterMaxMs: jitterMaxMs ?? this.jitterMaxMs,
      randomOffsetEnabled: randomOffsetEnabled ?? this.randomOffsetEnabled,
      randomOffsetMinPx: randomOffsetMinPx ?? this.randomOffsetMinPx,
      randomOffsetMaxPx: randomOffsetMaxPx ?? this.randomOffsetMaxPx,
      holdTriggerEnabled: holdTriggerEnabled ?? this.holdTriggerEnabled,
      holdTriggerKey: holdTriggerKey ?? this.holdTriggerKey,
      autoClickEnabled: autoClickEnabled ?? this.autoClickEnabled,
      smartDelayEnabled: smartDelayEnabled ?? this.smartDelayEnabled,
      humanLikeEnabled: humanLikeEnabled ?? this.humanLikeEnabled,
      soundFeedbackEnabled: soundFeedbackEnabled ?? this.soundFeedbackEnabled,
      statsEnabled: statsEnabled ?? this.statsEnabled,
      imageRecognitionEnabled: imageRecognitionEnabled ?? this.imageRecognitionEnabled,
      windowAutoDetectEnabled: windowAutoDetectEnabled ?? this.windowAutoDetectEnabled,
      scriptEngineEnabled: scriptEngineEnabled ?? this.scriptEngineEnabled,
      remoteControlEnabled: remoteControlEnabled ?? this.remoteControlEnabled,
      backgroundExecutionEnabled: backgroundExecutionEnabled ?? this.backgroundExecutionEnabled,
      silentStartEnabled: silentStartEnabled ?? this.silentStartEnabled,
      antiInterferenceEnabled: antiInterferenceEnabled ?? this.antiInterferenceEnabled,
      autoStartEnabled: autoStartEnabled ?? this.autoStartEnabled,
      autoStartSilent: autoStartSilent ?? this.autoStartSilent,
      taskQueueEnabled: taskQueueEnabled ?? this.taskQueueEnabled,
      taskNotificationEnabled: taskNotificationEnabled ?? this.taskNotificationEnabled,
      autoRetryEnabled: autoRetryEnabled ?? this.autoRetryEnabled,
      targetHwnd: targetHwnd ?? this.targetHwnd,
      targetWindowTitle: targetWindowTitle ?? this.targetWindowTitle,
      targetClientX: targetClientX ?? this.targetClientX,
      targetClientY: targetClientY ?? this.targetClientY,
    );
  }
}
