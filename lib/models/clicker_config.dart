
import 'package:collection/collection.dart';

class WindowInfo {
  final int hwnd;
  final String title;
  final String className;

  const WindowInfo({required this.hwnd, required this.title, required this.className});
}

class SoundConfig {
  final bool startEnabled;
  final bool endEnabled;
  final String startPath;
  final String endPath;

  const SoundConfig({
    this.startEnabled = true,
    this.endEnabled = false,
    this.startPath = '',
    this.endPath = '',
  });

  bool get enabled => startEnabled || endEnabled;

  SoundConfig copyWith({
    bool? startEnabled,
    bool? endEnabled,
    String? startPath,
    String? endPath,
  }) => SoundConfig(
    startEnabled: startEnabled ?? this.startEnabled,
    endEnabled: endEnabled ?? this.endEnabled,
    startPath: startPath ?? this.startPath,
    endPath: endPath ?? this.endPath,
  );

  Map<String, dynamic> toJson() => {
    'startEnabled': startEnabled,
    'endEnabled': endEnabled,
    if (startPath.isNotEmpty) 'startPath': startPath,
    if (endPath.isNotEmpty) 'endPath': endPath,
  };

  factory SoundConfig.fromJson(Map<String, dynamic> json) => SoundConfig(
    startEnabled: json['startEnabled'] ?? true,
    endEnabled: json['endEnabled'] ?? false,
    startPath: json['startPath'] ?? '',
    endPath: json['endPath'] ?? '',
  );
}

enum ClickType { single, double, drag, swipe, sequence }

enum ClickMode { mouse, keyboard, touch }

enum TouchAction { tap, longPress, drag, swipe }

enum MouseButton { left, right, middle, scrollUp, scrollDown, x1, x2 }

enum PositionMode { current, fixed, pick }

enum ClickRepeatMode { infinite, count, duration }

enum KeyActionMode {
  repeat,
  hold,
  sequence,
  combo,
  text,
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

enum MouseActionType { click, press, release, doubleClick, delay }

class MouseActionItem {
  final MouseActionType action;
  final MouseButton button;
  final int delayMs;

  const MouseActionItem({
    required this.action,
    this.button = MouseButton.left,
    this.delayMs = 50,
  });

  Map<String, dynamic> toJson() => {
        'action': action.name,
        'button': button.name,
        'delayMs': delayMs,
      };

  factory MouseActionItem.fromJson(Map<String, dynamic> json) {
    return MouseActionItem(
      action: MouseActionType.values.firstWhereOrNull(
            (e) => e.name == json['action'],
          ) ??
          MouseActionType.click,
      button: MouseButton.values.firstWhereOrNull(
            (e) => e.name == json['button'],
          ) ??
          MouseButton.left,
      delayMs: json['delayMs'] ?? 50,
    );
  }
}

enum ScheduleTiming { clock, countdown }

enum ScheduleRepeat { once, daily }

enum ScheduleAction {
  startClick('启动连点'),
  stopClick('停止连点'),
  playMacro('播放宏'),
  stopMacro('停止宏');

  const ScheduleAction(this.label);
  final String label;
}

class ClickerSchedule {
  static int _idSeq = 0;
  static String newId() =>
      '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}_${_idSeq++}';

  final String id;
  final bool enabled;
  final ScheduleAction action;
  final String? macroId;
  final ScheduleTiming timing;
  final ScheduleRepeat repeat;
  final int hour;
  final int minute;
  final int afterMinutes;
  final int fireAtEpochMs;

  const ClickerSchedule({
    this.id = '',
    this.enabled = false,
    this.action = ScheduleAction.startClick,
    this.macroId,
    this.timing = ScheduleTiming.clock,
    this.repeat = ScheduleRepeat.once,
    this.hour = 0,
    this.minute = 0,
    this.afterMinutes = 10,
    this.fireAtEpochMs = 0,
  });

  ClickerSchedule copyWith({
    String? id,
    bool? enabled,
    ScheduleAction? action,
    String? macroId,
    ScheduleTiming? timing,
    ScheduleRepeat? repeat,
    int? hour,
    int? minute,
    int? afterMinutes,
    int? fireAtEpochMs,
    bool clearMacroId = false,
  }) => ClickerSchedule(
    id: id ?? this.id,
    enabled: enabled ?? this.enabled,
    action: action ?? this.action,
    macroId: clearMacroId ? null : (macroId ?? this.macroId),
    timing: timing ?? this.timing,
    repeat: repeat ?? this.repeat,
    hour: hour ?? this.hour,
    minute: minute ?? this.minute,
    afterMinutes: afterMinutes ?? this.afterMinutes,
    fireAtEpochMs: fireAtEpochMs ?? this.fireAtEpochMs,
  );

  Map<String, dynamic> toJson() => {
    if (id.isNotEmpty) 'id': id,
    'enabled': enabled,
    'action': action.name,
    if (macroId != null) 'macroId': macroId,
    'timing': timing.name,
    'repeat': repeat.name,
    'hour': hour,
    'minute': minute,
    'afterMinutes': afterMinutes,
    if (fireAtEpochMs != 0) 'fireAtEpochMs': fireAtEpochMs,
  };

  factory ClickerSchedule.fromJson(Map<String, dynamic> json,
      {ScheduleAction defaultAction = ScheduleAction.startClick}) => ClickerSchedule(
    id: json['id'] as String? ?? newId(),
    enabled: json['enabled'] ?? false,
    action: json['action'] != null
        ? (ScheduleAction.values.asNameMap()[json['action']] ?? defaultAction)
        : defaultAction,
    macroId: json['macroId'] as String?,
    timing: ScheduleTiming.values.firstWhereOrNull(
          (e) => e.name == json['timing'],
        ) ??
        ScheduleTiming.clock,
    repeat: ScheduleRepeat.values.firstWhereOrNull(
          (e) => e.name == json['repeat'],
        ) ??
        ScheduleRepeat.once,
    hour: json['hour'] ?? 0,
    minute: json['minute'] ?? 0,
    afterMinutes: json['afterMinutes'] ?? 10,
    fireAtEpochMs: json['fireAtEpochMs'] ?? 0,
  );
}

List<ClickerSchedule> _parseSchedules(Map<String, dynamic> json) {
  final list = json['schedules'];
  if (list is List) {
    return list
        .whereType<Map>()
        .map((e) => ClickerSchedule.fromJson(e.cast<String, dynamic>()))
        .toList();
  }
  final result = <ClickerSchedule>[];
  final start = json['startSchedule'];
  if (start is Map) {
    result.add(ClickerSchedule.fromJson(
      start.cast<String, dynamic>(),
      defaultAction: ScheduleAction.startClick,
    ));
  }
  final stop = json['stopSchedule'];
  if (stop is Map) {
    result.add(ClickerSchedule.fromJson(
      stop.cast<String, dynamic>(),
      defaultAction: ScheduleAction.stopClick,
    ));
  }
  return result;
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

  String keyToRepeat;
  bool holdKey;
  KeyActionMode keyActionMode;

  TouchAction touchAction;
  int longPressDurationMs;
  int dragStartX;
  int dragStartY;
  int dragEndX;
  int dragEndY;
  int swipeStartX;
  int swipeStartY;
  int swipeEndX;
  int swipeEndY;
  int swipeDurationMs;

  List<KeySequenceItem> keySequence;

  List<MouseActionItem> mouseSequence;

  List<ClickerSchedule> schedules;

  List<String> comboKeys;

  String textToType;
  int textTypeDelayMs;

  int randomDelayMinMs;
  int randomDelayMaxMs;

  bool jitterEnabled;
  int jitterMinMs;
  int jitterMaxMs;

  bool randomOffsetEnabled;
  int randomOffsetMinPx;
  int randomOffsetMaxPx;

  int clickHoldMs;

  bool holdTriggerEnabled;
  String holdTriggerKey;

  bool autoClickEnabled;
  bool humanLikeEnabled;
  bool soundFeedbackEnabled;
  bool statsEnabled;
  bool imageRecognitionEnabled;
  bool windowAutoDetectEnabled;
  bool scriptEngineEnabled;
  bool remoteControlEnabled;

  bool humanLikeBezierCurve;
  bool humanLikeRandomPause;
  int humanLikePauseChance;
  int humanLikePauseMinMs;
  int humanLikePauseMaxMs;

  SoundConfig soundFeedbackClick;
  SoundConfig soundFeedbackKey;
  SoundConfig soundFeedbackMacro;

  bool backgroundExecutionEnabled;
  bool silentStartEnabled;
  bool antiInterferenceEnabled;
  bool autoStartEnabled;
  bool autoStartSilent;
  bool taskQueueEnabled;
  bool taskNotificationEnabled;
  bool autoRetryEnabled;

  int targetHwnd;
  String targetWindowTitle;
  int targetClientX;
  int targetClientY;

  bool userInterventionEnabled;
  bool userInterventionStop;
  int userInterventionResumeMs;

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
    this.touchAction = TouchAction.tap,
    this.longPressDurationMs = 500,
    this.dragStartX = 0,
    this.dragStartY = 0,
    this.dragEndX = 0,
    this.dragEndY = 0,
    this.swipeStartX = 0,
    this.swipeStartY = 0,
    this.swipeEndX = 0,
    this.swipeEndY = 0,
    this.swipeDurationMs = 300,
    this.keySequence = const [],
    this.mouseSequence = const [],
    this.schedules = const [],
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
    this.clickHoldMs = 0,
    this.holdTriggerEnabled = false,
    this.holdTriggerKey = 'F5',
    this.autoClickEnabled = true,
    this.humanLikeEnabled = false,
    this.humanLikeBezierCurve = false,
    this.humanLikeRandomPause = true,
    this.humanLikePauseChance = 5,
    this.humanLikePauseMinMs = 200,
    this.humanLikePauseMaxMs = 800,
    this.soundFeedbackEnabled = false,
    this.soundFeedbackClick = const SoundConfig(),
    this.soundFeedbackKey = const SoundConfig(),
    this.soundFeedbackMacro = const SoundConfig(),
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
    this.userInterventionEnabled = false,
    this.userInterventionStop = false,
    this.userInterventionResumeMs = 1500,
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
      touchAction: TouchAction.values.firstWhereOrNull(
            (e) => e.name == json['touchAction'],
          ) ??
          TouchAction.tap,
      longPressDurationMs: json['longPressDurationMs'] ?? 500,
      dragStartX: json['dragStartX'] ?? 0,
      dragStartY: json['dragStartY'] ?? 0,
      dragEndX: json['dragEndX'] ?? 0,
      dragEndY: json['dragEndY'] ?? 0,
      swipeStartX: json['swipeStartX'] ?? 0,
      swipeStartY: json['swipeStartY'] ?? 0,
      swipeEndX: json['swipeEndX'] ?? 0,
      swipeEndY: json['swipeEndY'] ?? 0,
      swipeDurationMs: json['swipeDurationMs'] ?? 300,
      keySequence: (json['keySequence'] as List<dynamic>?)
              ?.map((e) => KeySequenceItem.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      mouseSequence: (json['mouseSequence'] as List<dynamic>?)
              ?.map((e) => MouseActionItem.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      schedules: _parseSchedules(json),
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
      clickHoldMs: json['clickHoldMs'] ?? 0,
      holdTriggerEnabled: json['holdTriggerEnabled'] ?? false,
      holdTriggerKey: json['holdTriggerKey'] ?? 'F5',
      autoClickEnabled: json['autoClickEnabled'] ?? true,
      humanLikeEnabled: json['humanLikeEnabled'] ?? false,
      humanLikeBezierCurve: json['humanLikeBezierCurve'] ?? false,
      humanLikeRandomPause: json['humanLikeRandomPause'] ?? true,
      humanLikePauseChance: json['humanLikePauseChance'] ?? 5,
      humanLikePauseMinMs: json['humanLikePauseMinMs'] ?? 200,
      humanLikePauseMaxMs: json['humanLikePauseMaxMs'] ?? 800,
      soundFeedbackEnabled: json['soundFeedbackEnabled'] ?? false,
      soundFeedbackClick: json['soundFeedbackClick'] != null
        ? SoundConfig.fromJson(json['soundFeedbackClick'])
        : (json['soundFeedbackClickEnabled'] != null
          ? SoundConfig(startEnabled: json['soundFeedbackClickEnabled'] ?? true)
          : const SoundConfig()),
      soundFeedbackKey: json['soundFeedbackKey'] != null
        ? SoundConfig.fromJson(json['soundFeedbackKey'])
        : (json['soundFeedbackKeyEnabled'] != null
          ? SoundConfig(startEnabled: json['soundFeedbackKeyEnabled'] ?? true)
          : const SoundConfig()),
      soundFeedbackMacro: json['soundFeedbackMacro'] != null
        ? SoundConfig.fromJson(json['soundFeedbackMacro'])
        : (json['soundFeedbackMacroEnabled'] != null
          ? SoundConfig(startEnabled: json['soundFeedbackMacroEnabled'] ?? true)
          : const SoundConfig()),
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
      userInterventionEnabled: json['userInterventionEnabled'] ?? false,
      userInterventionStop: json['userInterventionStop'] ?? false,
      userInterventionResumeMs: json['userInterventionResumeMs'] ?? 1500,
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
        'touchAction': touchAction.name,
        'longPressDurationMs': longPressDurationMs,
        'dragStartX': dragStartX,
        'dragStartY': dragStartY,
        'dragEndX': dragEndX,
        'dragEndY': dragEndY,
        'swipeStartX': swipeStartX,
        'swipeStartY': swipeStartY,
        'swipeEndX': swipeEndX,
        'swipeEndY': swipeEndY,
        'swipeDurationMs': swipeDurationMs,
        'keySequence': keySequence.map((e) => e.toJson()).toList(),
        'mouseSequence': mouseSequence.map((e) => e.toJson()).toList(),
        'schedules': schedules.map((e) => e.toJson()).toList(),
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
        'clickHoldMs': clickHoldMs,
        'holdTriggerEnabled': holdTriggerEnabled,
        'holdTriggerKey': holdTriggerKey,
        'autoClickEnabled': autoClickEnabled,
        'humanLikeEnabled': humanLikeEnabled,
        'humanLikeBezierCurve': humanLikeBezierCurve,
        'humanLikeRandomPause': humanLikeRandomPause,
        'humanLikePauseChance': humanLikePauseChance,
        'humanLikePauseMinMs': humanLikePauseMinMs,
        'humanLikePauseMaxMs': humanLikePauseMaxMs,
        'soundFeedbackEnabled': soundFeedbackEnabled,
        'soundFeedbackClick': soundFeedbackClick.toJson(),
        'soundFeedbackKey': soundFeedbackKey.toJson(),
        'soundFeedbackMacro': soundFeedbackMacro.toJson(),
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
        'userInterventionEnabled': userInterventionEnabled,
        'userInterventionStop': userInterventionStop,
        'userInterventionResumeMs': userInterventionResumeMs,
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
    TouchAction? touchAction,
    int? longPressDurationMs,
    int? dragStartX,
    int? dragStartY,
    int? dragEndX,
    int? dragEndY,
    int? swipeStartX,
    int? swipeStartY,
    int? swipeEndX,
    int? swipeEndY,
    int? swipeDurationMs,
    List<KeySequenceItem>? keySequence,
    List<MouseActionItem>? mouseSequence,
    List<ClickerSchedule>? schedules,
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
    int? clickHoldMs,
    bool? holdTriggerEnabled,
    String? holdTriggerKey,
    bool? autoClickEnabled,
    bool? humanLikeEnabled,
    bool? humanLikeBezierCurve,
    bool? humanLikeRandomPause,
    int? humanLikePauseChance,
    int? humanLikePauseMinMs,
    int? humanLikePauseMaxMs,
    bool? soundFeedbackEnabled,
    SoundConfig? soundFeedbackClick,
    SoundConfig? soundFeedbackKey,
    SoundConfig? soundFeedbackMacro,
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
    bool? userInterventionEnabled,
    bool? userInterventionStop,
    int? userInterventionResumeMs,
  }) {
    return ClickerConfig(
      clickMode: clickMode ?? this.clickMode,
      clickType: clickType ?? this.clickType,
      mouseButton: mouseButton ?? this.mouseButton,
      positionMode: positionMode ?? this.positionMode,
      fixedX: fixedX ?? this.fixedX,
      fixedY: fixedY ?? this.fixedY,
      intervalMs: (intervalMs ?? this.intervalMs).clamp(1.0, double.infinity),
      repeatMode: repeatMode ?? this.repeatMode,
      repeatCount: repeatCount ?? this.repeatCount,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      keyToRepeat: keyToRepeat ?? this.keyToRepeat,
      holdKey: holdKey ?? this.holdKey,
      keyActionMode: keyActionMode ?? this.keyActionMode,
      touchAction: touchAction ?? this.touchAction,
      longPressDurationMs: longPressDurationMs ?? this.longPressDurationMs,
      dragStartX: dragStartX ?? this.dragStartX,
      dragStartY: dragStartY ?? this.dragStartY,
      dragEndX: dragEndX ?? this.dragEndX,
      dragEndY: dragEndY ?? this.dragEndY,
      swipeStartX: swipeStartX ?? this.swipeStartX,
      swipeStartY: swipeStartY ?? this.swipeStartY,
      swipeEndX: swipeEndX ?? this.swipeEndX,
      swipeEndY: swipeEndY ?? this.swipeEndY,
      swipeDurationMs: swipeDurationMs ?? this.swipeDurationMs,
      keySequence: keySequence ?? this.keySequence,
      mouseSequence: mouseSequence ?? this.mouseSequence,
      schedules: schedules ?? this.schedules,
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
      clickHoldMs: clickHoldMs ?? this.clickHoldMs,
      holdTriggerEnabled: holdTriggerEnabled ?? this.holdTriggerEnabled,
      holdTriggerKey: holdTriggerKey ?? this.holdTriggerKey,
      autoClickEnabled: autoClickEnabled ?? this.autoClickEnabled,
      humanLikeEnabled: humanLikeEnabled ?? this.humanLikeEnabled,
      humanLikeBezierCurve: humanLikeBezierCurve ?? this.humanLikeBezierCurve,
      humanLikeRandomPause: humanLikeRandomPause ?? this.humanLikeRandomPause,
      humanLikePauseChance: humanLikePauseChance ?? this.humanLikePauseChance,
      humanLikePauseMinMs: humanLikePauseMinMs ?? this.humanLikePauseMinMs,
      humanLikePauseMaxMs: humanLikePauseMaxMs ?? this.humanLikePauseMaxMs,
      soundFeedbackEnabled: soundFeedbackEnabled ?? this.soundFeedbackEnabled,
      soundFeedbackClick: soundFeedbackClick ?? this.soundFeedbackClick,
      soundFeedbackKey: soundFeedbackKey ?? this.soundFeedbackKey,
      soundFeedbackMacro: soundFeedbackMacro ?? this.soundFeedbackMacro,
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
      userInterventionEnabled: userInterventionEnabled ?? this.userInterventionEnabled,
      userInterventionStop: userInterventionStop ?? this.userInterventionStop,
      userInterventionResumeMs: userInterventionResumeMs ?? this.userInterventionResumeMs,
    );
  }
}
