/// Window auto-detect service — monitors foreground window title changes
/// and auto-switches clicker config based on window rules.
library;

import 'dart:async';
import 'package:flutter/services.dart';

class WindowRule {
  final String id;
  String name;
  String windowTitlePattern; // substring match
  String profileName;
  bool enabled;
  int matchCount;

  WindowRule({
    required this.id,
    required this.name,
    required this.windowTitlePattern,
    required this.profileName,
    this.enabled = true,
    this.matchCount = 0,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'windowTitlePattern': windowTitlePattern,
    'profileName': profileName,
    'enabled': enabled,
  };

  factory WindowRule.fromJson(Map<String, dynamic> json) => WindowRule(
    id: json['id'] ?? '',
    name: json['name'] ?? '',
    windowTitlePattern: json['windowTitlePattern'] ?? '',
    profileName: json['profileName'] ?? '',
    enabled: json['enabled'] ?? true,
  );
}

class WindowDetectService {
  static const _channel = MethodChannel('com.clicker.pro/platform');

  bool _isRunning = false;
  Timer? _timer;
  String _lastWindowTitle = '';
  final List<WindowRule> _rules = [];

  void Function(String windowTitle)? onWindowChanged;
  void Function(WindowRule rule)? onRuleMatched;
  void Function(String windowTitle)? onCurrentWindow;

  bool get isRunning => _isRunning;
  List<WindowRule> get rules => List.unmodifiable(_rules);
  String get lastWindowTitle => _lastWindowTitle;

  /// Get current foreground window title
  Future<String> getForegroundWindowTitle() async {
    try {
      final result = await _channel.invokeMethod<String>('getForegroundWindowTitle');
      return result ?? '';
    } on PlatformException {
      return '';
    }
  }

  /// Add a window rule
  void addRule(WindowRule rule) {
    _rules.add(rule);
  }

  /// Remove a window rule
  void removeRule(String id) {
    _rules.removeWhere((r) => r.id == id);
  }

  /// Update a window rule
  void updateRule(String id, {String? name, String? pattern, String? profile, bool? enabled}) {
    final idx = _rules.indexWhere((r) => r.id == id);
    if (idx < 0) return;
    final r = _rules[idx];
    _rules[idx] = WindowRule(
      id: r.id,
      name: name ?? r.name,
      windowTitlePattern: pattern ?? r.windowTitlePattern,
      profileName: profile ?? r.profileName,
      enabled: enabled ?? r.enabled,
    );
  }

  /// Start monitoring
  void start() {
    if (_isRunning) return;
    _isRunning = true;
    _pollWindow();
  }

  /// Stop monitoring
  void stop() {
    _isRunning = false;
    _timer?.cancel();
    _timer = null;
  }

  void _pollWindow() {
    _timer = Timer.periodic(const Duration(milliseconds: 500), (_) async {
      if (!_isRunning) return;
      final title = await getForegroundWindowTitle();
      onCurrentWindow?.call(title);

      if (title != _lastWindowTitle) {
        _lastWindowTitle = title;
        onWindowChanged?.call(title);
        _checkRules(title);
      }
    });
  }

  void _checkRules(String title) {
    if (title.isEmpty) return;
    for (final rule in _rules) {
      if (!rule.enabled) continue;
      if (title.toLowerCase().contains(rule.windowTitlePattern.toLowerCase())) {
        rule.matchCount++;
        onRuleMatched?.call(rule);
      }
    }
  }

  void dispose() {
    stop();
  }
}
