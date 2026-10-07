import 'dart:io';
import 'dart:ui' show Color;

import '../../models/clicker_config.dart';
import '../../models/macro_model.dart';
import '../app_state.dart';
import '../script_engine.dart';
import '../vision_plugin.dart';
import '../vision_plugin_manager.dart';
import '../vision_service.dart';
import '../vision_template_store.dart';
import 'api_action.dart';
import 'api_schema.dart';

ApiActionRegistry buildApiRegistry(AppState state) {
  final registry = ApiActionRegistry();

  registry.registerAll([
    ApiAction(
      name: 'system_capabilities',
      group: 'system',
      summary: '列出全部可用能力及其参数',
      description: '返回本接口支持的所有能力、分组、说明与 JSON Schema。'
          '首次接入时先调用它，即可知道能做什么、参数怎么传。',
      readOnly: true,
      handler: (args) async => registry.describeAll(),
    ),
    ApiAction(
      name: 'system_status',
      group: 'system',
      summary: '获取软件整体运行状态',
      description: '返回连点器、宏、脚本的运行状态、点击计数、平台与屏幕尺寸。'
          '用于判断当前是否正在连点或录制，避免重复启动。',
      readOnly: true,
      handler: (args) async {
        final size = await state.platformInput.getScreenSize();
        return {
          'initialized': state.isInitialized,
          'platform': Platform.operatingSystem,
          'screenWidth': size.width,
          'screenHeight': size.height,
          'clicker': {
            'status': state.clickerStatus.name,
            'running': state.isClickerRunning,
            'clickCount': state.clickCount,
          },
          'macro': {
            'status': state.macroStatus.name,
            'recording': state.isRecording,
            'playing': state.isPlaying,
            'recordingEventCount': state.recordingEventCount,
          },
          'script': {'status': state.scriptStatus.name},
          'macroCount': state.macros.length,
          'scheduleCount': state.clickerConfig.schedules.length,
        };
      },
    ),
  ]);

  registry.registerAll(_clickerActions(state));
  registry.registerAll(_inputActions(state));
  registry.registerAll(_macroActions(state));
  registry.registerAll(_visionActions());
  registry.registerAll(_scheduleActions(state));
  registry.registerAll(_profileActions(state));
  registry.registerAll(_scriptActions(state));

  return registry;
}

List<ApiAction> _clickerActions(AppState state) => [
      ApiAction(
        name: 'clicker_start',
        group: 'clicker',
        summary: '开始自动连点',
        description: '按当前配置开始自动连点。需要 config.autoClickEnabled 为 true，'
            '否则返回错误；可先调用 clicker_set_config 打开。',
        handler: (args) async {
          if (state.isClickerRunning) {
            return {'running': true, 'alreadyRunning': true};
          }
          if (!state.clickerConfig.autoClickEnabled) {
            throw ApiError.conflict('自动连点未启用（config.autoClickEnabled = false）',
                hint: '先调用 clicker_set_config 传 {"autoClickEnabled": true}');
          }
          await state.clickService.start();
          return {'running': state.isClickerRunning};
        },
      ),
      ApiAction(
        name: 'clicker_stop',
        group: 'clicker',
        summary: '停止自动连点',
        description: '停止正在进行的自动连点。未运行时调用也返回成功。',
        handler: (args) async {
          state.stopClicker();
          return {'running': state.isClickerRunning};
        },
      ),
      ApiAction(
        name: 'clicker_toggle',
        group: 'clicker',
        summary: '切换连点开关',
        description: '正在连点则停止，否则开始。等价于手动点击主按钮。',
        handler: (args) async {
          state.toggleClicker();
          await Future<void>.delayed(const Duration(milliseconds: 60));
          return {'running': state.isClickerRunning};
        },
      ),
      ApiAction(
        name: 'clicker_get_config',
        group: 'clicker',
        summary: '读取连点配置',
        description: '返回完整配置对象，字段名与 clicker_set_config 接受的键一致。',
        readOnly: true,
        handler: (args) async => {'config': state.clickerConfig.toJson()},
      ),
      ApiAction(
        name: 'clicker_set_config',
        group: 'clicker',
        summary: '修改连点配置',
        description: '局部更新配置：只传要改的字段，未传的保持不变。'
            '可传任意 ClickerConfig 字段（如 intervalMs、clickMode、clickType、'
            'positionMode、fixedX、fixedY、repeatMode、repeatCount、'
            'humanLikeEnabled、randomOffsetEnabled、autoClickEnabled 等）。'
            '枚举字段用名称字符串（如 "mouse"、"single"、"fixed"）。',
        inputSchema: objSchema(
          {
            'patch': objField('要修改的字段集合，键为配置字段名', {},
                const [], true),
          },
          const ['patch'],
        ),
        handler: (args) async {
          final patch = requireMap(args, 'patch');
          if (patch.isEmpty) {
            throw ApiError.invalidArgument('patch 为空，没有要修改的字段');
          }
          final merged = <String, dynamic>{...state.clickerConfig.toJson()};
          final unknown = <String>[];
          final known = state.clickerConfig.toJson().keys.toSet();
          for (final e in patch.entries) {
            if (!known.contains(e.key)) {
              unknown.add(e.key);
              continue;
            }
            merged[e.key] = e.value;
          }
          if (unknown.isNotEmpty) {
            throw ApiError.invalidArgument('未知配置字段：${unknown.join('、')}',
                hint: '调用 clicker_get_config 可查看全部合法字段名');
          }
          final next = ClickerConfig.fromJson(merged);
          state.setClickerConfig(next);
          return {
            'config': next.toJson(),
            'changed': patch.keys.toList(),
          };
        },
      ),
      ApiAction(
        name: 'clicker_click_at',
        group: 'clicker',
        summary: '在指定坐标点击一次',
        description: '不启动连点循环，立即在 (x, y) 执行一次鼠标点击。'
            '适合"点一下某个按钮"这类一次性动作。',
        inputSchema: objSchema(
          {
            'x': intField('屏幕 X 坐标'),
            'y': intField('屏幕 Y 坐标'),
            'button': strField('鼠标按键',
                def: 'left',
                enumValues: const ['left', 'right', 'middle']),
            'doubleClick': boolField('是否双击', def: false),
          },
          const ['x', 'y'],
        ),
        handler: (args) async {
          final x = requireInt(args, 'x');
          final y = requireInt(args, 'y');
          final button = optionalString(args, 'button', 'left');
          final dbl = optionalBool(args, 'doubleClick', false);
          await state.platformInput.mouseClick(
              x: x, y: y, button: button, doubleClick: dbl);
          return {'clicked': true, 'x': x, 'y': y, 'button': button};
        },
      ),
    ];

List<ApiAction> _inputActions(AppState state) => [
      ApiAction(
        name: 'input_move',
        group: 'input',
        summary: '移动鼠标到指定坐标',
        description: '立即把鼠标光标移动到 (x, y)，不产生点击。',
        inputSchema: objSchema(
          {'x': intField('屏幕 X 坐标'), 'y': intField('屏幕 Y 坐标')},
          const ['x', 'y'],
        ),
        handler: (args) async {
          final x = requireInt(args, 'x');
          final y = requireInt(args, 'y');
          await state.platformInput.mouseMove(x, y);
          return {'moved': true, 'x': x, 'y': y};
        },
      ),
      ApiAction(
        name: 'input_drag',
        group: 'input',
        summary: '拖拽鼠标',
        description: '从起点按住拖到终点后松开，用于拖动窗口、滑块、选中文本等。',
        inputSchema: objSchema(
          {
            'startX': intField('起点 X'),
            'startY': intField('起点 Y'),
            'endX': intField('终点 X'),
            'endY': intField('终点 Y'),
            'durationMs': intField('拖拽耗时（毫秒），越大越平滑',
                min: 0, max: 10000, def: 300),
            'button': strField('鼠标按键',
                def: 'left', enumValues: const ['left', 'right', 'middle']),
          },
          const ['startX', 'startY', 'endX', 'endY'],
        ),
        handler: (args) async {
          final sx = requireInt(args, 'startX');
          final sy = requireInt(args, 'startY');
          final ex = requireInt(args, 'endX');
          final ey = requireInt(args, 'endY');
          final duration = optionalInt(args, 'durationMs', 300);
          await state.platformInput.mouseDrag(
              startX: sx, startY: sy, endX: ex, endY: ey, durationMs: duration);
          return {'dragged': true, 'from': [sx, sy], 'to': [ex, ey]};
        },
      ),
      ApiAction(
        name: 'input_scroll',
        group: 'input',
        summary: '滚动鼠标滚轮',
        description: 'dx 为水平滚动量，dy 为垂直滚动量。正值 dy 通常表示向上滚动。',
        inputSchema: objSchema({
          'dx': numField('水平滚动量', def: 0),
          'dy': numField('垂直滚动量', def: 0),
        }),
        handler: (args) async {
          final dx = optionalDouble(args, 'dx', 0);
          final dy = optionalDouble(args, 'dy', 0);
          await state.platformInput.mouseScroll(dx: dx, dy: dy);
          return {'scrolled': true, 'dx': dx, 'dy': dy};
        },
      ),
      ApiAction(
        name: 'input_key',
        group: 'input',
        summary: '按下或松开一个按键',
        description: 'key 用按键名，如 "a"、"enter"、"f5"、"ctrl"、"shift"、"esc"、'
            '"tab"、"space"、"up"、"down"、"left"、"right"。'
            '默认按下并立即松开（一次完整按键）。',
        inputSchema: objSchema(
          {
            'key': strField('按键名'),
            'hold': boolField('是否按住不放（true 则不自动松开）', def: false),
          },
          const ['key'],
        ),
        handler: (args) async {
          final key = requireString(args, 'key');
          final hold = optionalBool(args, 'hold', false);
          await state.platformInput.keyPress(key);
          if (!hold) {
            await state.platformInput.keyRelease(key);
          }
          return {'key': key, 'held': hold};
        },
      ),
      ApiAction(
        name: 'input_type',
        group: 'input',
        summary: '输入一段文本',
        description: '逐字符输入文本，适合填写表单、搜索框。'
            '如需中文等非 ASCII 字符，请确认目标程序支持。',
        inputSchema: objSchema(
          {
            'text': strField('要输入的文本'),
            'delayMs': intField('每个字符间隔（毫秒）', min: 0, max: 2000, def: 30),
          },
          const ['text'],
        ),
        handler: (args) async {
          final text = requireString(args, 'text');
          final delay = optionalInt(args, 'delayMs', 30);
          await state.platformInput.keyType(text, delayMs: delay);
          return {'typed': true, 'length': text.length};
        },
      ),
    ];

List<ApiAction> _macroActions(AppState state) => [
      ApiAction(
        name: 'macro_list',
        group: 'macro',
        summary: '列出所有宏',
        description: '返回全部宏的 id、名称、事件数、总时长、重复次数、速度与启用状态。',
        readOnly: true,
        handler: (args) async => {
              'macros': [
                for (final m in state.macros)
                  {
                    'id': m.id,
                    'name': m.name,
                    'eventCount': m.events.length,
                    'totalDurationMs': m.totalDurationMs,
                    'repeatCount': m.repeatCount,
                    'speed': m.speed,
                    'enabled': m.enabled,
                    'hotkey': m.hotkey,
                  }
              ],
            },
      ),
      ApiAction(
        name: 'macro_get',
        group: 'macro',
        summary: '读取单个宏的完整定义',
        description: '按 id 返回宏的全部事件序列，可用于理解或复制已有宏。',
        inputSchema: objSchema({'id': strField('宏 id')}, const ['id']),
        readOnly: true,
        handler: (args) async {
          final id = requireString(args, 'id');
          final m = _findMacro(state, id);
          return {'macro': m.toJson()};
        },
      ),
      ApiAction(
        name: 'macro_create',
        group: 'macro',
        summary: '创建一个新宏',
        description: '用事件序列直接创建宏，无需手动录制。'
            'events 每项形如 {"type":"click","timestampMs":0,"x":100,"y":200}；'
            'type 可取 mouseDown/mouseUp/click/keyPress/keyRelease/scroll/wait/drag/swipe。',
        inputSchema: objSchema(
          {
            'name': strField('宏名称'),
            'events': arrField('事件数组', items: {'type': 'object'}),
            'repeatCount': intField('重复次数，0 表示无限', min: 0, def: 1),
            'speed': numField('播放倍速', min: 0.1, max: 10, def: 1.0),
          },
          const ['name', 'events'],
        ),
        handler: (args) async {
          final name = requireString(args, 'name');
          final rawEvents = requireList(args, 'events');
          if (rawEvents.isEmpty) {
            throw ApiError.invalidArgument('events 不能为空');
          }
          final events = <MacroEvent>[];
          for (var i = 0; i < rawEvents.length; i++) {
            final map = asMap(rawEvents[i]);
            if (map == null) {
              throw ApiError.invalidArgument('events[$i] 不是对象',
                  hint: '每项应是 {"type":"click","timestampMs":0,...}');
            }
            try {
              events.add(MacroEvent.fromJson(map));
            } on StateError {
              throw ApiError.invalidArgument(
                  'events[$i].type 取值 "${map['type']}" 不是合法事件类型',
                  hint: '可选值：${MacroEventType.values.map((e) => e.name).join(' | ')}');
            }
          }
          final macro = MacroModel(
            id: DateTime.now().microsecondsSinceEpoch.toString(),
            name: name,
            events: events,
            repeatCount: optionalInt(args, 'repeatCount', 1),
            speed: optionalDouble(args, 'speed', 1.0),
          );
          await state.saveMacroFromBuilder(macro);
          return {'id': macro.id, 'name': macro.name, 'eventCount': events.length};
        },
      ),
      ApiAction(
        name: 'macro_update',
        group: 'macro',
        summary: '修改宏的属性',
        description: '按 id 修改宏的名称、重复次数、速度、启用状态或事件序列。'
            '只传要改的字段。',
        inputSchema: objSchema(
          {
            'id': strField('宏 id'),
            'patch': objField(
                '要修改的字段，可含 name/repeatCount/speed/enabled/events', {}, const [], true),
          },
          const ['id', 'patch'],
        ),
        handler: (args) async {
          final id = requireString(args, 'id');
          final patch = requireMap(args, 'patch');
          final current = _findMacro(state, id);

          List<MacroEvent>? events;
          if (patch.containsKey('events')) {
            final raw = asList(patch['events']);
            if (raw == null) {
              throw ApiError.invalidArgument('events 必须是数组');
            }
            events = [];
            for (var i = 0; i < raw.length; i++) {
              final map = asMap(raw[i]);
              if (map == null) {
                throw ApiError.invalidArgument('events[$i] 不是对象');
              }
              events.add(MacroEvent.fromJson(map));
            }
          }

          final updated = current.copyWith(
            name: asString(patch['name']),
            repeatCount: asInt(patch['repeatCount']),
            speed: asDouble(patch['speed']),
            enabled: asBool(patch['enabled']),
            events: events,
          );
          await state.updateMacro(updated);
          return {'id': id, 'changed': patch.keys.toList()};
        },
      ),
      ApiAction(
        name: 'macro_rename',
        group: 'macro',
        summary: '重命名宏',
        description: '按 id 修改宏名称。',
        inputSchema: objSchema(
          {'id': strField('宏 id'), 'name': strField('新名称')},
          const ['id', 'name'],
        ),
        handler: (args) async {
          final id = requireString(args, 'id');
          final name = requireString(args, 'name');
          await state.renameMacro(_findMacro(state, id), name);
          return {'id': id, 'name': name};
        },
      ),
      ApiAction(
        name: 'macro_delete',
        group: 'macro',
        summary: '删除宏',
        description: '按 id 永久删除一个宏。',
        inputSchema: objSchema({'id': strField('宏 id')}, const ['id']),
        handler: (args) async {
          final id = requireString(args, 'id');
          await state.deleteMacro(_findMacro(state, id));
          return {'deleted': true, 'id': id};
        },
      ),
      ApiAction(
        name: 'macro_play',
        group: 'macro',
        summary: '播放宏',
        description: '按 id 播放宏。若已在播放中会先停止当前播放。'
            '播放是异步的，本调用立即返回。',
        inputSchema: objSchema(
          {
            'id': strField('宏 id'),
            'wait': boolField('是否等待播放结束再返回', def: false),
          },
          const ['id'],
        ),
        handler: (args) async {
          final id = requireString(args, 'id');
          final wait = optionalBool(args, 'wait', false);
          final macro = _findMacro(state, id);
          if (state.isPlaying) state.stopMacro();
          final future = state.playMacro(macro);
          if (wait) {
            await future;
            return {'id': id, 'played': true, 'finished': !state.isPlaying};
          }
          return {'id': id, 'playing': true};
        },
      ),
      ApiAction(
        name: 'macro_stop',
        group: 'macro',
        summary: '停止宏播放',
        description: '停止当前正在播放的宏。',
        handler: (args) async {
          state.stopMacro();
          return {'playing': state.isPlaying};
        },
      ),
      ApiAction(
        name: 'macro_record_start',
        group: 'macro',
        summary: '开始录制宏',
        description: '开始记录鼠标与键盘操作。录制期间请正常操作，'
            '结束后调用 macro_record_stop 保存。',
        handler: (args) async {
          if (state.isRecording) {
            return {'recording': true, 'alreadyRecording': true};
          }
          await state.startRecording();
          return {'recording': state.isRecording};
        },
      ),
      ApiAction(
        name: 'macro_record_stop',
        group: 'macro',
        summary: '停止录制并保存宏',
        description: '结束录制并把记录的操作保存为一个新宏，返回新宏的 id。',
        inputSchema: objSchema({'name': strField('宏名称', def: '录制的宏')}),
        handler: (args) async {
          if (!state.isRecording) {
            throw ApiError.conflict('当前没有在录制');
          }
          final name = optionalString(args, 'name', '录制的宏');
          final before = state.macros.length;
          await state.stopRecording(name: name);
          final created = state.macros.length > before ? state.macros.first : null;
          return {
            'saved': true,
            'name': name,
            if (created != null) 'id': created.id,
            if (created != null) 'eventCount': created.events.length,
          };
        },
      ),
      ApiAction(
        name: 'macro_record_cancel',
        group: 'macro',
        summary: '取消录制',
        description: '放弃当前录制内容，不保存。',
        handler: (args) async {
          state.cancelRecording();
          return {'recording': state.isRecording};
        },
      ),
      ApiAction(
        name: 'macro_record_pause',
        group: 'macro',
        summary: '暂停录制',
        description: '暂停录制，暂停期间的操作不会被记录。再次调用可继续。',
        handler: (args) async {
          if (!state.isRecording) {
            throw ApiError.conflict('当前没有在录制');
          }
          state.pauseRecording();
          return {'recording': state.isRecording, 'paused': state.isPaused};
        },
      ),
    ];

Future<VisionTemplate> _resolveTemplate(Map<String, dynamic> args) async {
  final all = await VisionTemplateStore.instance.loadAll();
  if (all.isEmpty) {
    throw ApiError.notFound('模板库为空', hint: '先用 vision_capture_template 截取一个模板');
  }
  final id = asString(args['templateId']);
  final name = asString(args['templateName']);
  VisionTemplate? template;
  for (final t in all) {
    if (id != null && t.id == id) template = t;
    if (name != null && t.name == name) template = t;
  }
  if (template == null) {
    throw ApiError.notFound('找不到指定的模板', hint: '调用 vision_list_templates 查看可用模板');
  }
  return template;
}

TemplateData _templateData(VisionTemplate t) =>
    TemplateData(pixels: t.pixels, width: t.width, height: t.height);

Future<(int, int, int, int)> _resolveRegion(Map<String, dynamic> args) async {
  final size = await VisionService.instance.getScreenSize();
  return (
    optionalInt(args, 'regionX', 0),
    optionalInt(args, 'regionY', 0),
    optionalInt(args, 'regionWidth', size?.width ?? 1920),
    optionalInt(args, 'regionHeight', size?.height ?? 1080),
  );
}

List<double>? _parseScales(Map<String, dynamic> args) {
  final raw = args['scales'];
  if (raw is! List) return null;
  final out = <double>[];
  for (final v in raw) {
    if (v is! num) continue;
    final d = v.toDouble();
    if (d >= 0.2 && d <= 5.0) out.add(d);
  }
  return out.length > 1 ? out : null;
}

Color? _parseHexColor(String raw) {
  var s = raw.trim();
  if (s.startsWith('#')) s = s.substring(1);
  if (s.length == 3) {
    s = '${s[0]}${s[0]}${s[1]}${s[1]}${s[2]}${s[2]}';
  }
  if (s.length != 6) return null;
  final v = int.tryParse(s, radix: 16);
  if (v == null) return null;
  return Color(0xFF000000 | v);
}

String _hexOf(Color c) {
  final argb = c.toARGB32();
  final r = (argb >> 16) & 0xFF;
  final g = (argb >> 8) & 0xFF;
  final b = argb & 0xFF;
  return '#${r.toRadixString(16).padLeft(2, '0')}'
      '${g.toRadixString(16).padLeft(2, '0')}'
      '${b.toRadixString(16).padLeft(2, '0')}';
}

Map<String, dynamic> _matchJson(MatchResult m) => {
      'x': m.x,
      'y': m.y,
      'width': m.width,
      'height': m.height,
      'score': m.score,
      'centerX': m.centerX,
      'centerY': m.centerY,
    };

Map<String, dynamic> _scalesField() => arrField(
      '多尺度搜索的比例列表，如 [1.0, 0.9, 1.1]（0.2~5.0）；省略则只按原尺寸匹配',
      items: {'type': 'number'},
    );

String _activeOcrEngineId() {
  final p = VisionPluginManager.instance
      .getPluginForCapability(VisionCapability.ocr);
  return p?.info.id ?? 'none';
}

List<ApiAction> _visionActions() => [
      ApiAction(
        name: 'vision_ocr_engines',
        group: 'vision',
        summary: '列出可用的文字识别引擎',
        description: '返回所有 OCR 引擎的 id、名称、是否可用与当前选中项。'
            '用 vision_set_ocr_engine 切换。',
        readOnly: true,
        inputSchema: objSchema({}),
        handler: (args) async {
          final mgr = VisionPluginManager.instance;
          final engines = <Map<String, dynamic>>[];
          for (final p in mgr.plugins) {
            if (!p.info.capabilities.contains(VisionCapability.ocr)) continue;
            engines.add({
              'id': p.info.id,
              'name': p.info.name,
              'description': p.info.description,
              'builtin': p.info.isBuiltin,
              'available': p.isAvailable,
              'enabled': p.enabled,
            });
          }
          return {
            'engines': engines,
            'selected': _activeOcrEngineId(),
            'preferred': mgr.preferredId,
          };
        },
      ),
      ApiAction(
        name: 'vision_set_ocr_engine',
        group: 'vision',
        summary: '切换文字识别引擎',
        description: '按 id 切换 OCR 引擎，传 auto 恢复默认（Windows OCR）。'
            '可用 vision_ocr_engines 查看可选 id。',
        inputSchema: objSchema({'id': strField('引擎 id，传 auto 恢复默认')}),
        handler: (args) async {
          final mgr = VisionPluginManager.instance;
          final raw = optionalString(args, 'id', 'auto');
          final id = (raw == 'auto' || raw.isEmpty) ? null : raw;
          if (id != null && mgr.getPlugin(id) == null) {
            throw ApiError.notFound('找不到 OCR 引擎 $id',
                hint: '调用 vision_ocr_engines 查看可用 id');
          }
          mgr.setPreferred(id);
          for (final p in mgr.plugins) {
            if (p.info.capabilities.contains(VisionCapability.ocr)) {
              p.enabled = id == null || p.info.id == id;
            }
          }
          final target = id ?? 'builtin_windows_ocr';
          mgr.resetInitialized(target);
          await mgr.ensureInitialized(target);
          final p = mgr.getPlugin(target);
          return {
            'selected': _activeOcrEngineId(),
            'available': p?.isAvailable ?? false,
          };
        },
      ),
      ApiAction(
        name: 'vision_list_templates',
        group: 'vision',
        summary: '列出所有图像模板',
        description: '返回模板库里保存的模板 id、名称与尺寸，'
            '供 vision_find_image 按 id 或名称引用。',
        readOnly: true,
        handler: (args) async {
          final all = await VisionTemplateStore.instance.loadAll();
          return {
            'templates': [
              for (final t in all)
                {
                  'id': t.id,
                  'name': t.name,
                  'width': t.width,
                  'height': t.height,
                  'threshold': t.threshold,
                  'createdAt': t.createdAt,
                }
            ],
          };
        },
      ),
      ApiAction(
        name: 'vision_capture_template',
        group: 'vision',
        summary: '截取屏幕区域保存为模板',
        description: '把屏幕上 (x, y) 起 width×height 的区域保存为可复用的图像模板，'
            '之后可用 vision_find_image 在屏幕中查找它。',
        inputSchema: objSchema(
          {
            'x': intField('区域左上角 X'),
            'y': intField('区域左上角 Y'),
            'width': intField('区域宽度', min: 1),
            'height': intField('区域高度', min: 1),
            'name': strField('模板名称'),
            'threshold': numField('匹配阈值 0~1，越高越严格',
                min: 0, max: 1, def: 0.85),
          },
          const ['x', 'y', 'width', 'height', 'name'],
          false,
          absoluteAliases,
        ),
        handler: (args) async {
          final x = requireInt(args, 'x');
          final y = requireInt(args, 'y');
          final w = requireInt(args, 'width');
          final h = requireInt(args, 'height');
          final name = requireString(args, 'name');
          final threshold = optionalDouble(args, 'threshold', 0.85);

          final data =
              await VisionService.instance.captureTemplate(x, y, w, h);
          if (data == null) {
            throw ApiError.unsupported('截屏失败，可能未授予屏幕录制权限',
                hint: '请先在图像识别页面开启屏幕捕获权限');
          }
          final template = VisionTemplate(
            id: DateTime.now().microsecondsSinceEpoch.toString(),
            name: name,
            width: data.width,
            height: data.height,
            pixels: data.pixels,
            threshold: threshold,
            createdAt: DateTime.now().millisecondsSinceEpoch,
          );
          await VisionTemplateStore.instance.save(template);
          return {'id': template.id, 'name': name, 'width': w, 'height': h};
        },
      ),
      ApiAction(
        name: 'vision_find_image',
        group: 'vision',
        summary: '在屏幕中查找图像模板',
        description: '在指定区域内查找已保存的模板，返回是否找到、'
            '匹配位置与中心点坐标（可直接喂给 input_click 或 clicker_click_at）。'
            '需要多个匹配用 vision_find_image_all，需要等它出现用 vision_wait_image。',
        inputSchema: objSchema({
          'templateId': strField('模板 id（与 templateName 二选一）'),
          'templateName': strField('模板名称（与 templateId 二选一）'),
          'regionX': intField('搜索区域左上角 X，默认整屏'),
          'regionY': intField('搜索区域左上角 Y，默认整屏'),
          'regionWidth': intField('搜索区域宽度，默认整屏'),
          'regionHeight': intField('搜索区域高度，默认整屏'),
          'threshold': numField('覆盖模板自带的匹配阈值 0~1', min: 0, max: 1),
          'scales': _scalesField(),
        }, const [], false, regionAliases),
        handler: (args) async {
          final template = await _resolveTemplate(args);
          final (rx, ry, rw, rh) = await _resolveRegion(args);
          final matches = await VisionService.instance.findImageAll(
            regionX: rx,
            regionY: ry,
            regionW: rw,
            regionH: rh,
            template: _templateData(template),
            threshold: asDouble(args['threshold']) ?? template.threshold,
            maxResults: 1,
            scales: _parseScales(args),
          );
          if (matches.isEmpty) {
            return {'found': false, 'templateId': template.id};
          }
          return {
            'found': true,
            'templateId': template.id,
            ..._matchJson(matches.first),
          };
        },
      ),
      ApiAction(
        name: 'vision_find_image_all',
        group: 'vision',
        summary: '找出屏幕中全部匹配的模板位置',
        description: '与 vision_find_image 相同，但返回多个匹配，'
            '按匹配分数从高到低排列。用于页面上有多个相同图标的情况。'
            'scales 可做多尺度搜索，适配被缩放的界面。',
        inputSchema: objSchema({
          'templateId': strField('模板 id（与 templateName 二选一）'),
          'templateName': strField('模板名称（与 templateId 二选一）'),
          'regionX': intField('搜索区域左上角 X，默认整屏'),
          'regionY': intField('搜索区域左上角 Y，默认整屏'),
          'regionWidth': intField('搜索区域宽度，默认整屏'),
          'regionHeight': intField('搜索区域高度，默认整屏'),
          'threshold': numField('覆盖模板自带的匹配阈值 0~1', min: 0, max: 1),
          'maxResults': intField('最多返回多少个匹配', def: 10, min: 1, max: 200),
          'scales': _scalesField(),
        }, const [], false, regionAliases),
        handler: (args) async {
          final template = await _resolveTemplate(args);
          final (rx, ry, rw, rh) = await _resolveRegion(args);
          final matches = await VisionService.instance.findImageAll(
            regionX: rx,
            regionY: ry,
            regionW: rw,
            regionH: rh,
            template: _templateData(template),
            threshold: asDouble(args['threshold']) ?? template.threshold,
            maxResults: optionalInt(args, 'maxResults', 10),
            scales: _parseScales(args),
          );
          return {
            'templateId': template.id,
            'found': matches.isNotEmpty,
            'count': matches.length,
            'matches': [for (final m in matches) _matchJson(m)],
          };
        },
      ),
      ApiAction(
        name: 'vision_wait_image',
        group: 'vision',
        summary: '等待模板出现在屏幕上',
        description: '反复查找模板直到出现或超时，适合等待加载完成、等待按钮可点。'
            '超时不报错，返回 found=false 与已等待时长。',
        inputSchema: objSchema({
          'templateId': strField('模板 id（与 templateName 二选一）'),
          'templateName': strField('模板名称（与 templateId 二选一）'),
          'regionX': intField('搜索区域左上角 X，默认整屏'),
          'regionY': intField('搜索区域左上角 Y，默认整屏'),
          'regionWidth': intField('搜索区域宽度，默认整屏'),
          'regionHeight': intField('搜索区域高度，默认整屏'),
          'threshold': numField('覆盖模板自带的匹配阈值 0~1', min: 0, max: 1),
          'timeoutMs': intField('最长等待毫秒数', def: 10000, min: 100, max: 600000),
          'intervalMs': intField('两次查找之间的间隔毫秒数', def: 200, min: 20, max: 60000),
          'scales': _scalesField(),
        }, const [], false, regionAliases),
        handler: (args) async {
          final template = await _resolveTemplate(args);
          final (rx, ry, rw, rh) = await _resolveRegion(args);
          final started = DateTime.now();
          final match = await VisionService.instance.waitForImage(
            regionX: rx,
            regionY: ry,
            regionW: rw,
            regionH: rh,
            template: _templateData(template),
            threshold: asDouble(args['threshold']) ?? template.threshold,
            scales: _parseScales(args),
            timeout: Duration(milliseconds: optionalInt(args, 'timeoutMs', 10000)),
            interval: Duration(milliseconds: optionalInt(args, 'intervalMs', 200)),
          );
          return {
            'found': match != null,
            'templateId': template.id,
            'elapsedMs': DateTime.now().difference(started).inMilliseconds,
            if (match != null) ..._matchJson(match),
          };
        },
      ),
      ApiAction(
        name: 'vision_find_color',
        group: 'vision',
        summary: '在屏幕区域中查找指定颜色',
        description: '在区域内扫描颜色，返回第一个符合容差的像素坐标。'
            '适合判断按钮高亮、血条颜色、状态灯。',
        inputSchema: objSchema(
          {
            'hex': strField('目标颜色，如 #FF0000 或 FF0000'),
            'regionX': intField('搜索区域左上角 X，默认整屏'),
            'regionY': intField('搜索区域左上角 Y，默认整屏'),
            'regionWidth': intField('搜索区域宽度，默认整屏'),
            'regionHeight': intField('搜索区域高度，默认整屏'),
            'tolerance': intField('每个通道允许的偏差', def: 10, min: 0, max: 255),
          },
          const ['hex'],
          false,
          const {
            'color': 'hex',
            'colour': 'hex',
            ...regionAliases,
          },
        ),
        handler: (args) async {
          final color = _parseHexColor(requireString(args, 'hex'));
          if (color == null) {
            throw ApiError.invalidArgument('hex 不是合法的颜色，示例：#FF0000',
                hint: '也可用别名 color / colour 传入同一个值');
          }
          final (rx, ry, rw, rh) = await _resolveRegion(args);
          final hit = await VisionService.instance.findColor(
            regionX: rx,
            regionY: ry,
            regionW: rw,
            regionH: rh,
            targetColor: color,
            tolerance: optionalInt(args, 'tolerance', 10),
          );
          if (hit == null) {
            return {'found': false, 'hex': _hexOf(color)};
          }
          return {
            'found': true,
            'hex': _hexOf(color),
            'x': hit.x,
            'y': hit.y,
            'centerX': hit.centerX,
            'centerY': hit.centerY,
          };
        },
      ),
      ApiAction(
        name: 'vision_ocr',
        group: 'vision',
        summary: '识别屏幕区域的文字',
        description: '对指定区域做 OCR，返回识别出的文本与逐行坐标。'
            '不传区域则识别整个屏幕。lines 里每行都有中心点，可直接拿去点击。',
        inputSchema: objSchema({
          'x': intField('区域左上角 X', def: 0),
          'y': intField('区域左上角 Y', def: 0),
          'width': intField('区域宽度，默认整屏'),
          'height': intField('区域高度，默认整屏'),
          'language': strField('识别语言', def: 'zh-Hans-CN'),
        }, const [], false, absoluteAliases),
        handler: (args) async {
          final size = await VisionService.instance.getScreenSize();
          final x = optionalInt(args, 'x', 0);
          final y = optionalInt(args, 'y', 0);
          final w = optionalInt(args, 'width', size?.width ?? 1920);
          final h = optionalInt(args, 'height', size?.height ?? 1080);
          final lang = optionalString(args, 'language', 'zh-Hans-CN');

          final lines = await VisionService.instance
              .ocrLines(x: x, y: y, w: w, h: h, language: lang);
          if (lines.isNotEmpty) {
            return {
              'text': lines.map((l) => l.text).join('\n'),
              'hasText': true,
              'engine': _activeOcrEngineId(),
              'lines': [
                for (final l in lines)
                  {
                    'text': l.text,
                    'x': l.x,
                    'y': l.y,
                    'width': l.width,
                    'height': l.height,
                    'centerX': l.x + l.width ~/ 2,
                    'centerY': l.y + l.height ~/ 2,
                  },
              ],
              'region': {'x': x, 'y': y, 'width': w, 'height': h},
            };
          }

          final result = await VisionService.instance
              .ocrRegion(x: x, y: y, w: w, h: h, language: lang);
          if (result == null) {
            throw ApiError.unsupported('OCR 失败，可能未授予屏幕录制权限或未启用识别插件');
          }
          return {
            'text': result.text,
            'hasText': result.hasText,
            'engine': _activeOcrEngineId(),
            'lines': const <Map<String, dynamic>>[],
            if (result.error != null) 'error': result.error,
            'region': {'x': x, 'y': y, 'width': w, 'height': h},
          };
        },
      ),
      ApiAction(
        name: 'vision_get_pixel',
        group: 'vision',
        summary: '读取屏幕上某点的颜色',
        description: '返回 (x, y) 处的像素颜色，含 hex 与 RGB 分量。'
            '可用于判断按钮状态、血条颜色等。',
        inputSchema: objSchema(
          {'x': intField('屏幕 X 坐标'), 'y': intField('屏幕 Y 坐标')},
          const ['x', 'y'],
          false,
          absoluteAliases,
        ),
        handler: (args) async {
          final x = requireInt(args, 'x');
          final y = requireInt(args, 'y');
          final color = await VisionService.instance.getPixelColor(x, y);
          if (color == null) {
            throw ApiError.unsupported('读取像素失败，可能未授予屏幕录制权限');
          }
          final argb = color.toARGB32();
          final r = (argb >> 16) & 0xFF;
          final g = (argb >> 8) & 0xFF;
          final b = argb & 0xFF;
          return {
            'x': x,
            'y': y,
            'hex': '#${r.toRadixString(16).padLeft(2, '0')}'
                '${g.toRadixString(16).padLeft(2, '0')}'
                '${b.toRadixString(16).padLeft(2, '0')}',
            'r': r,
            'g': g,
            'b': b,
          };
        },
      ),
      ApiAction(
        name: 'vision_screenshot',
        group: 'vision',
        summary: '截屏并保存为文件',
        description: '截取指定区域并保存到磁盘，返回文件路径。'
            '不传区域则截取整个屏幕。',
        inputSchema: objSchema({
          'x': intField('区域左上角 X', def: 0),
          'y': intField('区域左上角 Y', def: 0),
          'width': intField('区域宽度，默认整屏'),
          'height': intField('区域高度，默认整屏'),
        }, const [], false, absoluteAliases),
        handler: (args) async {
          final size = await VisionService.instance.getScreenSize();
          final x = optionalInt(args, 'x', 0);
          final y = optionalInt(args, 'y', 0);
          final w = optionalInt(args, 'width', size?.width ?? 1920);
          final h = optionalInt(args, 'height', size?.height ?? 1080);
          final path =
              await VisionService.instance.saveScreenshot(x, y, w, h);
          if (path == null) {
            throw ApiError.unsupported('截屏失败，可能未授予屏幕录制权限');
          }
          return {'path': path, 'width': w, 'height': h};
        },
      ),
      ApiAction(
        name: 'vision_delete_template',
        group: 'vision',
        summary: '删除图像模板',
        description: '按 id 删除一个已保存的图像模板。',
        inputSchema: objSchema({'id': strField('模板 id')}, const ['id']),
        handler: (args) async {
          final id = requireString(args, 'id');
          await VisionTemplateStore.instance.delete(id);
          return {'deleted': true, 'id': id};
        },
      ),
      ApiAction(
        name: 'vision_dump_elements',
        group: 'vision',
        summary: '枚举窗口控件树',
        description: '用 Windows UI Automation 读出控件树，返回每个控件的名称、类型、'
            '包围盒与中心点。比截图匹配稳得多，适合找按钮、输入框、菜单项。'
            '坐标与 vision_click / vision_screenshot 处于同一坐标系。',
        readOnly: true,
        inputSchema: objSchema({
          'maxDepth': intField('控件树最大深度', def: 6, min: 1, max: 20),
          'maxElements': intField('最多返回多少个控件', def: 400, min: 1, max: 4000),
          'hwnd': intField('只枚举这个窗口句柄的子树，0 表示整个桌面', def: 0),
        }),
        handler: (args) async {
          final dump = await VisionService.instance.dumpElements(
            maxDepth: optionalInt(args, 'maxDepth', 6),
            maxElements: optionalInt(args, 'maxElements', 400),
            rootHwnd: optionalInt(args, 'hwnd', 0),
          );
          if (dump.hasError) {
            throw ApiError.unsupported('枚举控件失败：${dump.error}');
          }
          return {
            'count': dump.elements.length,
            'truncated': dump.truncated,
            'elements': [for (final e in dump.elements) e.toJson()],
          };
        },
      ),
      ApiAction(
        name: 'vision_find_element',
        group: 'vision',
        summary: '按条件查找控件',
        description: '在控件树里找第一个匹配的控件，返回包围盒与中心点，可直接拿去点击。'
            '名称按包含匹配（不区分大小写），其余字段按完全匹配（不区分大小写）。'
            '四个条件至少要给一个。',
        readOnly: true,
        inputSchema: objSchema({
          'name': strField('控件名称，包含匹配'),
          'automationId': strField('AutomationId，完全匹配'),
          'className': strField('窗口类名，完全匹配'),
          'controlType': strField('控件类型，如 Button / Edit / MenuItem，完全匹配'),
          'maxDepth': intField('控件树最大深度', def: 6, min: 1, max: 20),
          'maxElements': intField('最多扫描多少个控件', def: 400, min: 1, max: 4000),
          'hwnd': intField('只搜索这个窗口句柄的子树，0 表示整个桌面', def: 0),
        }),
        handler: (args) async {
          final el = await VisionService.instance.findElement(
            name: asString(args['name']),
            automationId: asString(args['automationId']),
            className: asString(args['className']),
            controlType: asString(args['controlType']),
            maxDepth: optionalInt(args, 'maxDepth', 6),
            maxElements: optionalInt(args, 'maxElements', 400),
            rootHwnd: optionalInt(args, 'hwnd', 0),
          );
          if (el == null) return {'found': false};
          return {'found': true, ...el.toJson()};
        },
      ),
      ApiAction(
        name: 'vision_wait_element',
        group: 'vision',
        summary: '等待控件出现',
        description: '轮询控件树直到找到匹配的控件，超时返回 found=false（不报错）。'
            '条件与 vision_find_element 相同。',
        readOnly: true,
        inputSchema: objSchema({
          'name': strField('控件名称，包含匹配'),
          'automationId': strField('AutomationId，完全匹配'),
          'className': strField('窗口类名，完全匹配'),
          'controlType': strField('控件类型，如 Button / Edit / MenuItem，完全匹配'),
          'timeoutMs': intField('最长等待毫秒数', def: 10000, min: 100, max: 600000),
          'intervalMs': intField('两次查找之间的间隔毫秒数', def: 200, min: 20, max: 60000),
          'maxDepth': intField('控件树最大深度', def: 6, min: 1, max: 20),
          'maxElements': intField('最多扫描多少个控件', def: 400, min: 1, max: 4000),
          'hwnd': intField('只搜索这个窗口句柄的子树，0 表示整个桌面', def: 0),
        }),
        handler: (args) async {
          final el = await VisionService.instance.waitForElement(
            name: asString(args['name']),
            automationId: asString(args['automationId']),
            className: asString(args['className']),
            controlType: asString(args['controlType']),
            maxDepth: optionalInt(args, 'maxDepth', 6),
            maxElements: optionalInt(args, 'maxElements', 400),
            rootHwnd: optionalInt(args, 'hwnd', 0),
            timeout: Duration(milliseconds: optionalInt(args, 'timeoutMs', 10000)),
            interval: Duration(milliseconds: optionalInt(args, 'intervalMs', 200)),
          );
          if (el == null) return {'found': false};
          return {'found': true, ...el.toJson()};
        },
      ),
      ApiAction(
        name: 'vision_screenshot_png',
        group: 'vision',
        summary: '截屏返回 PNG（base64）',
        description: '截取区域并返回 PNG 的 base64，可直接作为多模态模型的图像输入。'
            '用 maxWidth 等比缩小能显著降低 token 消耗。不传区域则截取整个屏幕。',
        readOnly: true,
        inputSchema: objSchema({
          'x': intField('区域左上角 X', def: 0),
          'y': intField('区域左上角 Y', def: 0),
          'width': intField('区域宽度，默认整屏'),
          'height': intField('区域高度，默认整屏'),
          'maxWidth': intField('等比缩小到不超过这个宽度，0 表示不缩放', def: 0, min: 0, max: 8192),
        }, const [], false, absoluteAliases),
        handler: (args) async {
          final size = await VisionService.instance.getScreenSize();
          final png = await VisionService.instance.capturePng(
            x: optionalInt(args, 'x', 0),
            y: optionalInt(args, 'y', 0),
            w: optionalInt(args, 'width', size?.width ?? 1920),
            h: optionalInt(args, 'height', size?.height ?? 1080),
            maxWidth: optionalInt(args, 'maxWidth', 0),
          );
          if (png == null) {
            throw ApiError.unsupported('截屏失败，可能未授予屏幕录制权限');
          }
          return {
            'image': png.toBase64(),
            'mimeType': 'image/png',
            'width': png.width,
            'height': png.height,
            'scale': png.scale,
            'byteLength': png.byteLength,
          };
        },
      ),
      ApiAction(
        name: 'vision_set_of_mark',
        group: 'vision',
        summary: '截图 + 控件编号（Set-of-Mark）',
        description: '截取区域，把 UI Automation 找到的控件画上编号框，返回带编号的 PNG '
            '（base64）与编号对应的控件表。多模态模型看图后可直接说"点 3 号"，'
            '再用 elements 里第 3 项的 centerX/centerY 点击。',
        readOnly: true,
        inputSchema: objSchema({
          'x': intField('区域左上角 X', def: 0),
          'y': intField('区域左上角 Y', def: 0),
          'width': intField('区域宽度，默认整屏'),
          'height': intField('区域高度，默认整屏'),
          'maxDepth': intField('控件树最大深度', def: 6, min: 1, max: 20),
          'maxElements': intField('最多编号多少个控件', def: 60, min: 1, max: 200),
          'maxWidth': intField('等比缩小到不超过这个宽度，0 表示不缩放', def: 0, min: 0, max: 8192),
          'hwnd': intField('只枚举这个窗口句柄的子树，0 表示整个桌面', def: 0),
        }, const [], false, absoluteAliases),
        handler: (args) async {
          final result = await VisionService.instance.setOfMark(
            x: optionalInt(args, 'x', 0),
            y: optionalInt(args, 'y', 0),
            w: optionalInt(args, 'width', 0),
            h: optionalInt(args, 'height', 0),
            maxDepth: optionalInt(args, 'maxDepth', 6),
            maxElements: optionalInt(args, 'maxElements', 60),
            maxWidth: optionalInt(args, 'maxWidth', 0),
            rootHwnd: optionalInt(args, 'hwnd', 0),
          );
          if (result == null) {
            throw ApiError.unsupported('截屏失败，可能未授予屏幕录制权限');
          }
          return {
            'image': result.png.toBase64(),
            'mimeType': 'image/png',
            'width': result.png.width,
            'height': result.png.height,
            'scale': result.png.scale,
            'truncated': result.truncated,
            'elements': [
              for (var i = 0; i < result.elements.length; i++)
                {'mark': i + 1, ...result.elements[i].toJson()},
            ],
          };
        },
      ),
    ];

List<ApiAction> _scheduleActions(AppState state) => [
      ApiAction(
        name: 'schedule_list',
        group: 'schedule',
        summary: '列出所有定时任务',
        description: '返回定时任务的下标、动作、触发方式与下次触发时间。'
            '下标用于 schedule_update 与 schedule_remove。',
        readOnly: true,
        handler: (args) async {
          final list = state.clickerConfig.schedules;
          return {
            'schedules': [
              for (var i = 0; i < list.length; i++)
                {
                  'index': i,
                  'id': list[i].id,
                  'enabled': list[i].enabled,
                  'action': list[i].action.name,
                  'actionLabel': list[i].action.label,
                  'timing': list[i].timing.name,
                  'repeat': list[i].repeat.name,
                  'hour': list[i].hour,
                  'minute': list[i].minute,
                  'afterMinutes': list[i].afterMinutes,
                  'macroId': list[i].macroId,
                  'fireAtEpochMs': list[i].fireAtEpochMs,
                  'nextFireAt': list[i].fireAtEpochMs > 0
                      ? DateTime.fromMillisecondsSinceEpoch(
                              list[i].fireAtEpochMs)
                          .toIso8601String()
                      : null,
                }
            ],
          };
        },
      ),
      ApiAction(
        name: 'schedule_add',
        group: 'schedule',
        summary: '新增一个定时任务',
        description: 'timing 为 clock 时按每天的 hour:minute 触发；'
            '为 countdown 时在 afterMinutes 分钟后触发。'
            'action 可取 startClick/stopClick/playMacro/stopMacro。'
            '返回新任务的下标。',
        inputSchema: objSchema(
          {
            'action': strField('到点执行的动作',
                def: 'startClick',
                enumValues: const [
                  'startClick',
                  'stopClick',
                  'playMacro',
                  'stopMacro'
                ]),
            'timing': strField('触发方式',
                def: 'clock', enumValues: const ['clock', 'countdown']),
            'repeat': strField('重复方式',
                def: 'once',
                enumValues: const [
                  'once',
                  'daily',
                  'weekly',
                  'weekdays',
                  'interval'
                ]),
            'weekday': intField('星期 1~7（repeat=weekly 时使用，1 为周一）',
                min: 1, max: 7, def: 1),
            'intervalMinutes': intField('间隔分钟数（repeat=interval 时使用）',
                min: 1, max: 1440, def: 30),
            'hour': intField('小时 0~23（timing=clock 时使用）',
                min: 0, max: 23, def: 8),
            'minute': intField('分钟 0~59（timing=clock 时使用）',
                min: 0, max: 59, def: 0),
            'afterMinutes': intField('多少分钟后触发（timing=countdown 时使用）',
                min: 1, max: 10080, def: 10),
            'macroId': strField('要播放的宏 id（action=playMacro 时必填）'),
            'enabled': boolField('是否立即启用并布防', def: true),
          },
          const ['action'],
        ),
        handler: (args) async {
          final action = optionalEnum(args, 'action', ScheduleAction.values,
              ScheduleAction.startClick);
          final timing = optionalEnum(
              args, 'timing', ScheduleTiming.values, ScheduleTiming.clock);
          final repeat = optionalEnum(
              args, 'repeat', ScheduleRepeat.values, ScheduleRepeat.once);
          final hour = optionalInt(args, 'hour', 8);
          final minute = optionalInt(args, 'minute', 0);
          final after = optionalInt(args, 'afterMinutes', 10);
          final weekday = optionalInt(args, 'weekday', 1);
          final intervalMinutes = optionalInt(args, 'intervalMinutes', 30);
          final enabled = optionalBool(args, 'enabled', true);
          final macroId = asString(args['macroId']);

          if (action == ScheduleAction.playMacro && macroId == null) {
            throw ApiError.invalidArgument('action=playMacro 时必须提供 macroId',
                hint: '调用 macro_list 获取可用宏 id');
          }
          if (macroId != null) {
            _findMacro(state, macroId);
          }

          state.addSchedule();
          final index = state.clickerConfig.schedules.length - 1;
          final base = state.clickerConfig.schedules[index];
          final next = base.copyWith(
            action: action,
            timing: timing,
            repeat: repeat,
            hour: hour,
            minute: minute,
            afterMinutes: after,
            weekday: weekday,
            intervalMinutes: intervalMinutes,
            enabled: enabled,
            macroId: macroId,
          );
          state.updateScheduleAt(index, next, rearm: true);
          final saved = state.clickerConfig.schedules[index];
          return {
            'index': index,
            'id': saved.id,
            'fireAtEpochMs': saved.fireAtEpochMs,
          };
        },
      ),
      ApiAction(
        name: 'schedule_update',
        group: 'schedule',
        summary: '修改定时任务',
        description: '按下标修改定时任务。只传要改的字段。'
            '改动时间或启用状态后会自动重新布防。',
        inputSchema: objSchema(
          {
            'index': intField('任务下标，从 0 开始', min: 0),
            'patch': objField(
                '要修改的字段，可含 action/timing/repeat/weekday/intervalMinutes/hour/minute/afterMinutes/macroId/enabled',
                {},
                const [],
                true),
          },
          const ['index', 'patch'],
        ),
        handler: (args) async {
          final index = requireInt(args, 'index');
          final list = state.clickerConfig.schedules;
          if (index < 0 || index >= list.length) {
            throw ApiError.invalidArgument('index 越界：当前共 ${list.length} 个任务',
                hint: '调用 schedule_list 查看有效下标');
          }
          final patch = requireMap(args, 'patch');
          if (patch.isEmpty) {
            throw ApiError.invalidArgument('patch 为空，没有要修改的字段');
          }
          final current = list[index];

          ScheduleAction? action;
          if (patch.containsKey('action')) {
            action = _enumByName(patch['action'], ScheduleAction.values);
            if (action == null) {
              throw ApiError.invalidArgument('action 取值不合法',
                  hint:
                      '可选值：${ScheduleAction.values.map((e) => e.name).join(' | ')}');
            }
          }
          ScheduleTiming? timing;
          if (patch.containsKey('timing')) {
            timing = _enumByName(patch['timing'], ScheduleTiming.values);
            if (timing == null) {
              throw ApiError.invalidArgument('timing 取值不合法',
                  hint: '可选值：clock | countdown');
            }
          }
          ScheduleRepeat? repeat;
          if (patch.containsKey('repeat')) {
            repeat = _enumByName(patch['repeat'], ScheduleRepeat.values);
            if (repeat == null) {
              throw ApiError.invalidArgument('repeat 取值不合法',
                  hint:
                      '可选值：${ScheduleRepeat.values.map((e) => e.name).join(' | ')}');
            }
          }
          final macroId = asString(patch['macroId']);
          if (macroId != null) _findMacro(state, macroId);

          final next = current.copyWith(
            action: action,
            timing: timing,
            repeat: repeat,
            hour: asInt(patch['hour']),
            minute: asInt(patch['minute']),
            afterMinutes: asInt(patch['afterMinutes']),
            weekday: asInt(patch['weekday']),
            intervalMinutes: asInt(patch['intervalMinutes']),
            enabled: asBool(patch['enabled']),
            macroId: macroId,
          );
          state.updateScheduleAt(index, next, rearm: true);
          return {'index': index, 'changed': patch.keys.toList()};
        },
      ),
      ApiAction(
        name: 'schedule_remove',
        group: 'schedule',
        summary: '删除定时任务',
        description: '按下标删除一个定时任务。',
        inputSchema:
            objSchema({'index': intField('任务下标', min: 0)}, const ['index']),
        handler: (args) async {
          final index = requireInt(args, 'index');
          final list = state.clickerConfig.schedules;
          if (index < 0 || index >= list.length) {
            throw ApiError.invalidArgument('index 越界：当前共 ${list.length} 个任务');
          }
          state.removeScheduleAt(index);
          return {'removed': true, 'index': index};
        },
      ),
    ];

List<ApiAction> _profileActions(AppState state) => [
      ApiAction(
        name: 'profile_list',
        group: 'profile',
        summary: '列出所有配置档案',
        description: '返回已保存的配置档案名称。',
        readOnly: true,
        handler: (args) async => {'profiles': state.profiles},
      ),
      ApiAction(
        name: 'profile_save',
        group: 'profile',
        summary: '把当前配置保存为档案',
        description: '用给定名称保存当前全部连点配置，之后可随时载入。'
            '同名会覆盖。',
        inputSchema:
            objSchema({'name': strField('档案名称')}, const ['name']),
        handler: (args) async {
          final name = requireString(args, 'name');
          await state.saveProfile(name);
          return {'saved': true, 'name': name};
        },
      ),
      ApiAction(
        name: 'profile_load',
        group: 'profile',
        summary: '载入配置档案',
        description: '按名称载入之前保存的配置，会覆盖当前连点配置。',
        inputSchema:
            objSchema({'name': strField('档案名称')}, const ['name']),
        handler: (args) async {
          final name = requireString(args, 'name');
          if (!state.profiles.contains(name)) {
            throw ApiError.notFound('找不到档案 "$name"',
                hint: '调用 profile_list 查看可用档案');
          }
          state.loadProfile(name);
          return {'loaded': true, 'name': name};
        },
      ),
      ApiAction(
        name: 'profile_delete',
        group: 'profile',
        summary: '删除配置档案',
        description: '按名称删除一个配置档案。',
        inputSchema:
            objSchema({'name': strField('档案名称')}, const ['name']),
        handler: (args) async {
          final name = requireString(args, 'name');
          if (!state.profiles.contains(name)) {
            throw ApiError.notFound('找不到档案 "$name"');
          }
          await state.deleteProfile(name);
          return {'deleted': true, 'name': name};
        },
      ),
    ];

List<ApiAction> _scriptActions(AppState state) => [
      ApiAction(
        name: 'script_list',
        group: 'script',
        summary: '列出已加载的脚本',
        description: '返回当前会话中已添加的脚本。注意：脚本不持久化，重启后清空。',
        readOnly: true,
        handler: (args) async => {
              'scripts': [
                for (final s in state.scripts)
                  {
                    'id': s.id,
                    'name': s.name,
                    'commandCount': s.commands.length,
                    'enabled': s.enabled,
                  }
              ],
              'status': state.scriptStatus.name,
            },
      ),
      ApiAction(
        name: 'script_run',
        group: 'script',
        summary: '执行一段脚本',
        description: '直接执行脚本文本，无需先创建脚本对象。'
            '支持的指令：click x y / key <键名> / delay <毫秒> / move x y / '
            'scroll dx dy / type <文本> / repeat <次数> / start_clicker / stop_clicker。'
            'wait=true 时等待执行结束再返回。',
        inputSchema: objSchema(
          {
            'script': strField('脚本文本，每行一条指令'),
            'name': strField('脚本名称（仅用于日志）', def: 'API 脚本'),
            'wait': boolField('是否等待执行结束', def: true),
          },
          const ['script'],
        ),
        handler: (args) async {
          final text = requireString(args, 'script');
          final name = optionalString(args, 'name', 'API 脚本');
          final wait = optionalBool(args, 'wait', true);

          List<ScriptCommand> commands;
          try {
            commands = ScriptEngine.parseScript(text);
          } catch (e) {
            throw ApiError.invalidArgument('脚本解析失败：$e',
                hint: '每行一条指令，例如：click 100 200');
          }
          if (commands.isEmpty) {
            throw ApiError.invalidArgument('脚本没有任何有效指令');
          }

          final model = ScriptModel(
            id: DateTime.now().microsecondsSinceEpoch.toString(),
            name: name,
            commands: commands,
            createdAt: DateTime.now(),
          );
          state.addScript(model);
          final future = state.runScript(model);
          if (wait) {
            await future;
            return {
              'id': model.id,
              'commandCount': commands.length,
              'status': state.scriptStatus.name,
            };
          }
          return {'id': model.id, 'commandCount': commands.length};
        },
      ),
      ApiAction(
        name: 'script_stop',
        group: 'script',
        summary: '停止脚本执行',
        description: '停止当前正在运行的脚本。',
        handler: (args) async {
          state.stopScript();
          return {'status': state.scriptStatus.name};
        },
      ),
    ];

MacroModel _findMacro(AppState state, String id) {
  for (final m in state.macros) {
    if (m.id == id) return m;
  }
  throw ApiError.notFound('找不到 id 为 "$id" 的宏',
      hint: '调用 macro_list 获取全部宏 id');
}

T? _enumByName<T extends Enum>(dynamic raw, List<T> values) {
  final name = asString(raw);
  if (name == null) return null;
  for (final v in values) {
    if (v.name == name) return v;
  }
  return null;
}
