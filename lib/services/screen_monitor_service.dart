/// Screen monitoring service — pixel color checking, screen capture, change detection.
/// Uses platform channel to access Windows GDI APIs.
library;

import 'dart:async';
import 'package:flutter/services.dart';

class ScreenMonitorService {
  static const _channel = MethodChannel('com.clicker.pro/platform');

  bool _isMonitoring = false;
  Timer? _monitorTimer;
  final List<MonitorRegion> _regions = [];
  final List<MonitorLogEntry> _logs = [];
  int _checkIntervalMs = 500;
  double _sensitivity = 0.5;

  void Function(MonitorLogEntry entry)? onLogEntry;
  void Function(bool isMonitoring)? onMonitoringChanged;

  bool get isMonitoring => _isMonitoring;
  List<MonitorRegion> get regions => List.unmodifiable(_regions);
  List<MonitorLogEntry> get logs => List.unmodifiable(_logs);
  int get checkIntervalMs => _checkIntervalMs;
  double get sensitivity => _sensitivity;

  /// Get pixel color at screen coordinates
  Future<Color?> getPixelColor(int x, int y) async {
    try {
      final result = await _channel.invokeMethod<Map>('getPixelColor', [x, y]);
      if (result != null) {
        final r = result['r'] as int;
        final g = result['g'] as int;
        final b = result['b'] as int;
        return Color.fromARGB(255, r, g, b);
      }
    } on PlatformException {
      return null;
    }
    return null;
  }

  /// Capture a screen rectangle as raw BGRA pixel data
  Future<Uint8List?> captureScreenRect(int x, int y, int w, int h) async {
    try {
      final result = await _channel.invokeMethod<Uint8List>('captureScreenRect', [x, y, w, h]);
      return result;
    } on PlatformException {
      return null;
    }
  }

  /// Get screen size
  Future<({int width, int height})?> getScreenSize() async {
    try {
      final result = await _channel.invokeMethod<Map>('getScreenSize');
      if (result != null) {
        return (width: result['width'] as int, height: result['height'] as int);
      }
    } on PlatformException {
      return null;
    }
    return null;
  }

  /// Add a monitoring region
  void addRegion(MonitorRegion region) {
    _regions.add(region);
  }

  /// Remove a monitoring region
  void removeRegion(String id) {
    _regions.removeWhere((r) => r.id == id);
  }

  /// Update check interval
  void setCheckInterval(int ms) {
    _checkIntervalMs = ms.clamp(100, 5000);
    if (_isMonitoring) {
      _stopMonitor();
      _startMonitor();
    }
  }

  /// Update sensitivity
  void setSensitivity(double value) {
    _sensitivity = value.clamp(0.1, 1.0);
  }

  /// Start monitoring
  void startMonitoring() {
    if (_isMonitoring) return;
    _isMonitoring = true;
    _startMonitor();
    onMonitoringChanged?.call(true);
    _addLog('监控已启动', MonitorLogLevel.info);
  }

  /// Stop monitoring
  void stopMonitoring() {
    if (!_isMonitoring) return;
    _isMonitoring = false;
    _stopMonitor();
    onMonitoringChanged?.call(false);
    _addLog('监控已停止', MonitorLogLevel.info);
  }

  /// Clear logs
  void clearLogs() {
    _logs.clear();
  }

  void _startMonitor() {
    _monitorTimer = Timer.periodic(Duration(milliseconds: _checkIntervalMs), (_) async {
      if (!_isMonitoring) return;
      await _checkRegions();
    });
  }

  void _stopMonitor() {
    _monitorTimer?.cancel();
    _monitorTimer = null;
  }

  Future<void> _checkRegions() async {
    for (final region in _regions) {
      if (!region.enabled) continue;

      try {
        // Sample key pixels in the region
        final color = await getPixelColor(region.x + region.w ~/ 2, region.y + region.h ~/ 2);
        if (color == null) continue;

        // Check if color matches the target
        if (region.targetColor != null) {
          final diff = _colorDifference(color, region.targetColor!);
          if (diff < (1.0 - _sensitivity)) {
            // Color matches — trigger action
            _addLog('区域 "${region.name}" 检测到目标颜色 RGB(${color.red},${color.green},${color.blue})', MonitorLogLevel.detected);
            region.onDetected?.call();
          }
        }

        // Check for change from last capture
        if (region.lastCenterColor != null) {
          final diff = _colorDifference(color, region.lastCenterColor!);
          if (diff > _sensitivity * 0.3) {
            _addLog('区域 "${region.name}" 检测到变化 (差异: ${(diff * 100).toStringAsFixed(1)}%)', MonitorLogLevel.changed);
            region.onChanged?.call();
          }
        }

        region.lastCenterColor = color;
      } on PlatformException {
        // Ignore errors during monitoring
      }
    }
  }

  double _colorDifference(Color a, Color b) {
    final dr = (a.red - b.red).abs();
    final dg = (a.green - b.green).abs();
    final db = (a.blue - b.blue).abs();
    return (dr + dg + db) / (255 * 3);
  }

  void _addLog(String message, MonitorLogLevel level) {
    final entry = MonitorLogEntry(
      time: DateTime.now(),
      message: message,
      level: level,
    );
    _logs.add(entry);
    if (_logs.length > 500) _logs.removeAt(0);
    onLogEntry?.call(entry);
  }

  void dispose() {
    stopMonitoring();
  }
}

class MonitorRegion {
  final String id;
  final String name;
  final int x;
  final int y;
  final int w;
  final int h;
  final Color? targetColor;
  final bool enabled;
  final VoidCallback? onDetected;
  final VoidCallback? onChanged;

  Color? lastCenterColor;

  MonitorRegion({
    required this.id,
    required this.name,
    required this.x,
    required this.y,
    required this.w,
    required this.h,
    this.targetColor,
    this.enabled = true,
    this.onDetected,
    this.onChanged,
  });

  MonitorRegion copyWith({
    String? name,
    int? x,
    int? y,
    int? w,
    int? h,
    Color? targetColor,
    bool? enabled,
    VoidCallback? onDetected,
    VoidCallback? onChanged,
  }) {
    return MonitorRegion(
      id: id,
      name: name ?? this.name,
      x: x ?? this.x,
      y: y ?? this.y,
      w: w ?? this.w,
      h: h ?? this.h,
      targetColor: targetColor ?? this.targetColor,
      enabled: enabled ?? this.enabled,
      onDetected: onDetected ?? this.onDetected,
      onChanged: onChanged ?? this.onChanged,
    );
  }
}

enum MonitorLogLevel { info, detected, changed, error }

class MonitorLogEntry {
  final DateTime time;
  final String message;
  final MonitorLogLevel level;

  MonitorLogEntry({required this.time, required this.message, required this.level});
}
