
import 'dart:async';

enum ScriptStatus { idle, running, paused }

class ScriptCommand {
  final String action;
  final Map<String, dynamic> params;

  const ScriptCommand(this.action, this.params);

  Map<String, dynamic> toJson() => {'action': action, ...params};

  factory ScriptCommand.fromJson(Map<String, dynamic> json) {
    final copy = Map<String, dynamic>.from(json)..remove('action');
    return ScriptCommand(json['action'] as String? ?? 'delay', copy);
  }
}

class ScriptModel {
  final String id;
  String name;
  List<ScriptCommand> commands;
  bool enabled;
  DateTime createdAt;

  ScriptModel({
    required this.id,
    required this.name,
    required this.commands,
    this.enabled = true,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'commands': commands.map((c) => c.toJson()).toList(),
    'enabled': enabled,
    'createdAt': createdAt.toIso8601String(),
  };

  factory ScriptModel.fromJson(Map<String, dynamic> json) => ScriptModel(
    id: json['id'] ?? '',
    name: json['name'] ?? '',
    commands: (json['commands'] as List<dynamic>?)
        ?.map((c) => ScriptCommand.fromJson(c as Map<String, dynamic>))
        .toList() ?? [],
    enabled: json['enabled'] ?? true,
    createdAt: json['createdAt'] != null ? DateTime.parse(json['createdAt']) : DateTime.now(),
  );
}

class ScriptEngine {
  ScriptStatus _status = ScriptStatus.idle;
  int _currentLine = 0;
  int _steps = 0;
  Completer<void>? _pauseCompleter;

  void Function(ScriptStatus status)? onStatusChanged;
  void Function(int line, int total)? onProgress;
  void Function(String message)? onLog;
  void Function(String message)? onError;

  ScriptStatus get status => _status;
  int get currentLine => _currentLine;

  Future<void> Function(int x, int y, String button)? doClick;
  Future<void> Function(int x, int y)? doMove;
  Future<void> Function(String key)? doKeyPress;
  Future<void> Function(String key)? doKeyRelease;
  Future<void> Function(double dx, double dy)? doScroll;
  Future<void> Function(String text, int delayMs)? doType;
  Future<void> Function()? doStartClicker;
  Future<void> Function()? doStopClicker;

  static String formatScript(List<ScriptCommand> commands) {
    final lines = <String>[];
    _formatCommands(commands, 0, lines);
    return lines.join('\n');
  }

  static void _formatCommands(
      List<ScriptCommand> commands, int indent, List<String> lines) {
    final pad = '  ' * indent;
    for (final cmd in commands) {
      final p = cmd.params;
      switch (cmd.action) {
        case 'click':
          lines.add('${pad}click ${p['x'] ?? 0} ${p['y'] ?? 0} ${p['button'] ?? 'left'}');
          break;
        case 'key':
          lines.add('${pad}key ${p['key'] ?? 'enter'}');
          break;
        case 'delay':
          lines.add('${pad}delay ${p['ms'] ?? 100}');
          break;
        case 'move':
          lines.add('${pad}move ${p['x'] ?? 0} ${p['y'] ?? 0}');
          break;
        case 'scroll':
          lines.add('${pad}scroll ${p['dx'] ?? 0} ${p['dy'] ?? 0}');
          break;
        case 'type':
          lines.add('${pad}type ${p['text'] ?? ''} ${p['delayMs'] ?? 30}');
          break;
        case 'repeat':
          lines.add('${pad}repeat ${p['count'] ?? 1}');
          break;
        case 'repeat_block':
          lines.add('${pad}repeat ${p['count'] ?? 1}');
          _formatCommands(_blockBody(p), indent + 1, lines);
          lines.add('${pad}end');
          break;
        case 'start_clicker':
          lines.add('${pad}start_clicker');
          break;
        case 'stop_clicker':
          lines.add('${pad}stop_clicker');
          break;
      }
    }
  }

  static List<ScriptCommand> _blockBody(Map<String, dynamic> p) {
    final body = p['body'];
    if (body is! List) return const [];
    return body
        .whereType<Map>()
        .map((e) => ScriptCommand.fromJson(e.cast<String, dynamic>()))
        .toList();
  }

  static const int _maxRepeatCount = 10000;

  static const int _maxRepeatDepth = 8;

  static const int _maxSteps = 200000;

  static List<ScriptCommand> parseScript(String text) {
    final root = <ScriptCommand>[];
    final stack = <_RepeatFrame>[];

    void emit(ScriptCommand cmd) {
      if (stack.isEmpty) {
        root.add(cmd);
      } else {
        stack.last.body.add(cmd);
      }
    }

    for (final line in text.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('//') || trimmed.startsWith('#')) continue;

      final parts = trimmed.split(RegExp(r'\s+'));
      final action = parts[0].toLowerCase();

      if (action == 'end') {
        if (stack.isNotEmpty) {
          final frame = stack.removeLast();
          emit(ScriptCommand('repeat_block', {
            'count': frame.count,
            'body': frame.body.map((c) => c.toJson()).toList(),
          }));
        }
        continue;
      }

      switch (action) {
        case 'click':
          if (parts.length >= 3) {
            emit(ScriptCommand('click', {
              'x': int.tryParse(parts[1]) ?? 0,
              'y': int.tryParse(parts[2]) ?? 0,
              'button': parts.length > 3 ? parts[3] : 'left',
            }));
          }
          break;
        case 'key':
          if (parts.length >= 2) {
            emit(ScriptCommand('key', {'key': parts[1]}));
          }
          break;
        case 'delay':
          if (parts.length >= 2) {
            emit(ScriptCommand('delay', {'ms': int.tryParse(parts[1]) ?? 100}));
          }
          break;
        case 'move':
          if (parts.length >= 3) {
            emit(ScriptCommand('move', {
              'x': int.tryParse(parts[1]) ?? 0,
              'y': int.tryParse(parts[2]) ?? 0,
            }));
          }
          break;
        case 'scroll':
          if (parts.length >= 3) {
            emit(ScriptCommand('scroll', {
              'dx': double.tryParse(parts[1]) ?? 0,
              'dy': double.tryParse(parts[2]) ?? 0,
            }));
          }
          break;
        case 'type':
          final text = parts.length > 2 ? parts.sublist(1, parts.length - 1).join(' ') : '';
          final delay = parts.length > 2 ? int.tryParse(parts.last) ?? 30 : 30;
          emit(ScriptCommand('type', {'text': text, 'delayMs': delay}));
          break;
        case 'repeat':
          if (parts.length >= 2) {
            final count = (int.tryParse(parts[1]) ?? 1).clamp(1, _maxRepeatCount);
            if (stack.length >= _maxRepeatDepth) {
              emit(ScriptCommand('repeat', {'count': count}));
            } else {
              stack.add(_RepeatFrame(count));
            }
          }
          break;
        case 'start_clicker':
          emit(const ScriptCommand('start_clicker', {}));
          break;
        case 'stop_clicker':
          emit(const ScriptCommand('stop_clicker', {}));
          break;
      }
    }

    while (stack.isNotEmpty) {
      final frame = stack.removeLast();
      emit(ScriptCommand('repeat', {'count': frame.count}));
      for (final cmd in frame.body) {
        emit(cmd);
      }
    }

    return root;
  }

  Future<void> run(ScriptModel script) async {
    if (_status == ScriptStatus.running) return;
    _status = ScriptStatus.running;
    _currentLine = 0;
    _steps = 0;
    onStatusChanged?.call(_status);
    onLog?.call('脚本 "${script.name}" 开始执行 (${script.commands.length} 条命令)');

    try {
      await _executeCommands(script.commands);
    } catch (e) {
      onError?.call('脚本执行出错: $e');
    }

    _status = ScriptStatus.idle;
    _currentLine = 0;
    onStatusChanged?.call(_status);
    onLog?.call('脚本执行完成');
  }

  Future<void> _executeCommands(List<ScriptCommand> commands) async {
    int i = 0;
    while (i < commands.length && _status != ScriptStatus.idle) {
      if (_status == ScriptStatus.paused) {
        _pauseCompleter = Completer<void>();
        await _pauseCompleter!.future;
        _pauseCompleter = null;
        if (_status == ScriptStatus.idle) return;
      }

      final cmd = commands[i];
      _currentLine = i;
      onProgress?.call(i, commands.length);

      await _executeCommand(cmd);
      i++;
    }
  }

  Future<void> _executeCommand(ScriptCommand cmd) async {
    _steps++;
    if (_steps > _maxSteps) {
      throw StateError('脚本执行步数超过上限');
    }
    switch (cmd.action) {
      case 'click':
        await doClick?.call(
          cmd.params['x'] as int? ?? 0,
          cmd.params['y'] as int? ?? 0,
          cmd.params['button'] as String? ?? 'left',
        );
        break;
      case 'key':
        final key = cmd.params['key'] as String? ?? 'enter';
        await doKeyPress?.call(key);
        await Future.delayed(const Duration(milliseconds: 30));
        await doKeyRelease?.call(key);
        break;
      case 'delay':
        final ms = cmd.params['ms'] as int? ?? 100;
        await Future.delayed(Duration(milliseconds: ms));
        break;
      case 'move':
        await doMove?.call(
          cmd.params['x'] as int? ?? 0,
          cmd.params['y'] as int? ?? 0,
        );
        break;
      case 'scroll':
        await doScroll?.call(
          (cmd.params['dx'] as num?)?.toDouble() ?? 0,
          (cmd.params['dy'] as num?)?.toDouble() ?? 0,
        );
        break;
      case 'type':
        await doType?.call(
          cmd.params['text'] as String? ?? '',
          cmd.params['delayMs'] as int? ?? 30,
        );
        break;
      case 'repeat':
        final count = cmd.params['count'] as int? ?? 1;
        for (int r = 0; r < count && _status == ScriptStatus.running; r++) {
          await Future.delayed(const Duration(milliseconds: 50));
        }
        break;
      case 'repeat_block':
        final count =
            (cmd.params['count'] as int? ?? 1).clamp(1, _maxRepeatCount);
        final body = _blockBody(cmd.params);
        for (int r = 0; r < count && _status == ScriptStatus.running; r++) {
          await _executeCommands(body);
        }
        break;
      case 'start_clicker':
        await doStartClicker?.call();
        break;
      case 'stop_clicker':
        await doStopClicker?.call();
        break;
    }
  }

  void pause() {
    if (_status == ScriptStatus.running) {
      _status = ScriptStatus.paused;
      onStatusChanged?.call(_status);
    }
  }

  void resume() {
    if (_status == ScriptStatus.paused) {
      _status = ScriptStatus.running;
      onStatusChanged?.call(_status);
      _pauseCompleter?.complete();
    }
  }

  void stop() {
    _status = ScriptStatus.idle;
    _pauseCompleter?.complete();
    onStatusChanged?.call(_status);
  }

  void dispose() {
    stop();
  }
}

class _RepeatFrame {
  final int count;
  final List<ScriptCommand> body = [];

  _RepeatFrame(this.count);
}
