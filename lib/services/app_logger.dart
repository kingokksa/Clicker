import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import 'app_paths.dart';

class AppLogger {
  AppLogger._();

  static final AppLogger instance = AppLogger._();

  factory AppLogger.forTesting() = AppLogger._;

  static const int _recentLimit = 400;
  static const String _filePrefix = 'clicker-';

  final List<String> _recent = <String>[];
  IOSink? _sink;
  String? _dir;
  String _fileDate = '';
  bool _ready = false;
  bool _handlersInstalled = false;

  List<String> get recent => List<String>.unmodifiable(_recent);

  String? get directory => _dir;

  bool get ready => _ready;

  Future<void> init({String? directory}) async {
    try {
      _dir = directory ?? await AppPaths.getLogsDir();
      await Directory(_dir!).create(recursive: true);
      await _openSink(DateTime.now());
      _ready = true;
    } catch (_) {
      _ready = false;
    }
    _installErrorHandlers();
  }

  void log(String tag, Object? message) {
    final now = DateTime.now();
    final line = '${_dateKey(now)} ${_time(now)} [$tag] $message';
    _recent.add(line);
    if (_recent.length > _recentLimit) _recent.removeAt(0);
    if (kDebugMode) debugPrint(line);
    if (!_ready || _dir == null) return;
    if (_dateKey(now) != _fileDate) {
      unawaited(_openSink(now).then((_) {
        try {
          _sink?.writeln(line);
        } catch (_) {}
      }));
      return;
    }
    try {
      _sink?.writeln(line);
    } catch (_) {}
  }

  String currentLogPath() =>
      _dir == null ? '' : '${_dir!}${Platform.pathSeparator}$_filePrefix$_fileDate.log';

  Future<void> flush() async {
    try {
      await _sink?.flush();
    } catch (_) {}
  }

  Future<List<String>> readTail({int maxLines = 300}) async {
    final path = currentLogPath();
    if (path.isEmpty) return <String>[];
    await flush();
    try {
      final file = File(path);
      if (!await file.exists()) return <String>[];
      final lines = await file.readAsLines();
      if (lines.length <= maxLines) return lines;
      return lines.sublist(lines.length - maxLines);
    } catch (_) {
      return <String>[];
    }
  }

  Future<void> clear() async {
    _recent.clear();
    if (_dir == null) return;
    try {
      await _sink?.flush();
      await _sink?.close();
    } catch (_) {}
    _sink = null;
    _fileDate = '';
    try {
      final dir = Directory(_dir!);
      if (await dir.exists()) {
        await for (final entity in dir.list()) {
          if (entity is File &&
              entity.uri.pathSegments.last.startsWith(_filePrefix)) {
            try {
              await entity.delete();
            } catch (_) {}
          }
        }
      }
    } catch (_) {}
    if (_ready) await _openSink(DateTime.now());
  }

  Future<void> _openSink(DateTime now) async {
    final key = _dateKey(now);
    if (_sink != null && _fileDate == key) return;
    try {
      await _sink?.flush();
      await _sink?.close();
    } catch (_) {}
    _sink = null;
    if (_dir == null) return;
    final file = File('${_dir!}${Platform.pathSeparator}$_filePrefix$key.log');
    _sink = file.openWrite(mode: FileMode.append);
    _fileDate = key;
  }

  void _installErrorHandlers() {
    if (_handlersInstalled) return;
    _handlersInstalled = true;
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      log('FlutterError', details.exceptionAsString());
      final context = details.context;
      if (context != null) log('FlutterError', context.toString());
      previous?.call(details);
    };
    ui.PlatformDispatcher.instance.onError = (error, stack) {
      log('UncaughtError', '$error');
      return false;
    };
  }

  static String _dateKey(DateTime t) =>
      '${t.year.toString().padLeft(4, '0')}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';

  static String _time(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}.${t.millisecond.toString().padLeft(3, '0')}';
  }
}
