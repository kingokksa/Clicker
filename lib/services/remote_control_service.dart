/// Remote control service — lightweight HTTP server for remote start/stop.
/// Listens on a configurable port and exposes REST endpoints:
///   GET  /status       → current clicker/macro status
///   POST /start        → start clicker
///   POST /stop         → stop clicker
///   POST /toggle       → toggle clicker
///   POST /macro/play   → play first macro
///   POST /macro/stop   → stop macro playback
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

class RemoteControlService {
  HttpServer? _server;
  bool _isRunning = false;
  int _port = 9876;

  // Callbacks (set by AppState)
  void Function()? onStartClicker;
  void Function()? onStopClicker;
  void Function()? onToggleClicker;
  void Function()? onPlayMacro;
  void Function()? onStopMacro;
  Map<String, dynamic> Function()? onGetStatus;

  void Function(String message)? onLog;
  void Function(String message)? onError;

  bool get isRunning => _isRunning;
  int get port => _port;

  /// Start the HTTP server
  Future<bool> start({int? port}) async {
    if (_isRunning) return true;
    _port = port ?? _port;

    try {
      _server = await HttpServer.bind(InternetAddress.anyIPv4, _port);
      _isRunning = true;
      onLog?.call('远程控制已启动，监听端口 $_port');
      _serve();
      return true;
    } catch (e) {
      onError?.call('启动远程控制失败: $e');
      return false;
    }
  }

  /// Stop the HTTP server
  Future<void> stop() async {
    if (!_isRunning) return;
    await _server?.close(force: true);
    _server = null;
    _isRunning = false;
    onLog?.call('远程控制已停止');
  }

  void _serve() {
    _server?.listen((request) {
      _handleRequest(request);
    });
  }

  Future<void> _handleRequest(HttpRequest request) async {
    final path = request.uri.path;
    final method = request.method;

    try {
      if (method == 'GET' && path == '/status') {
        final status = onGetStatus?.call() ?? {};
        _jsonResponse(request, 200, status);
      } else if (method == 'POST' && path == '/start') {
        onStartClicker?.call();
        _jsonResponse(request, 200, {'ok': true, 'action': 'start'});
      } else if (method == 'POST' && path == '/stop') {
        onStopClicker?.call();
        _jsonResponse(request, 200, {'ok': true, 'action': 'stop'});
      } else if (method == 'POST' && path == '/toggle') {
        onToggleClicker?.call();
        _jsonResponse(request, 200, {'ok': true, 'action': 'toggle'});
      } else if (method == 'POST' && path == '/macro/play') {
        onPlayMacro?.call();
        _jsonResponse(request, 200, {'ok': true, 'action': 'macro_play'});
      } else if (method == 'POST' && path == '/macro/stop') {
        onStopMacro?.call();
        _jsonResponse(request, 200, {'ok': true, 'action': 'macro_stop'});
      } else {
        _jsonResponse(request, 404, {'error': 'Not found', 'endpoints': [
          'GET /status', 'POST /start', 'POST /stop',
          'POST /toggle', 'POST /macro/play', 'POST /macro/stop',
        ]});
      }
    } catch (e) {
      _jsonResponse(request, 500, {'error': e.toString()});
    }
  }

  void _jsonResponse(HttpRequest request, int statusCode, Map<String, dynamic> body) {
    request.response
      ..statusCode = statusCode
      ..headers.set('Content-Type', 'application/json')
      ..headers.set('Access-Control-Allow-Origin', '*')
      ..write(jsonEncode(body))
      ..close();
  }

  void dispose() {
    stop();
  }
}
