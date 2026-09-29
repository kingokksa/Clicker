
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import 'plugin_manifest.dart';
import 'plugin_event_bus.dart';
import '../vision_plugin.dart';


abstract class Plugin {
  PluginManifest get manifest;

  Future<void> onActivate(PluginContext context);

  Future<void> onDeactivate();
}

typedef PluginFactory = Plugin Function();


abstract class InputBackend {
  String get id;
  String get name;

  bool get isAvailable;

  Future<bool> initialize();

  Future<void> shutdown();

  Future<void> mouseDown(int x, int y, String button);
  Future<void> mouseUp(int x, int y, String button);
  Future<void> mousePress(int x, int y, String button);
  Future<void> keyDown(String key);
  Future<void> keyUp(String key);
  Future<void> keyPress(String key);
  Future<void> moveCursor(int x, int y);
  Future<void> scroll(double dx, double dy);
}


class PageRegistration {
  final PageContribution contribution;
  final WidgetBuilder builder;
  final String pluginId;
  const PageRegistration(this.contribution, this.builder, this.pluginId);
}

class CommandRegistration {
  final CommandContribution contribution;
  final FutureOr<Object?> Function(Map<String, dynamic> params) handler;
  final String pluginId;
  const CommandRegistration(this.contribution, this.handler, this.pluginId);
}

class InputBackendRegistration {
  final InputBackendContribution contribution;
  final InputBackend Function() factory;
  final String pluginId;
  const InputBackendRegistration(this.contribution, this.factory, this.pluginId);
}

class VisionProviderRegistration {
  final VisionProviderContribution contribution;
  final VisionPlugin Function() factory;
  final String pluginId;
  const VisionProviderRegistration(this.contribution, this.factory, this.pluginId);
}


class PluginHostServices {
  final Future<void> Function(int x, int y, String button) mouseDown;
  final Future<void> Function(int x, int y, String button) mouseUp;
  final Future<void> Function(String key) keyDown;
  final Future<void> Function(String key) keyUp;
  final Future<void> Function(int x, int y) moveCursor;
  final Future<void> Function(double dx, double dy) scroll;
  final Future<Uint8List?> Function(int x, int y, int w, int h) captureScreen;
  final void Function(String title, String message) showNotification;
  final Future<String?> Function() readClipboard;
  final Future<void> Function(String text) writeClipboard;

  const PluginHostServices({
    required this.mouseDown,
    required this.mouseUp,
    required this.keyDown,
    required this.keyUp,
    required this.moveCursor,
    required this.scroll,
    required this.captureScreen,
    required this.showNotification,
    required this.readClipboard,
    required this.writeClipboard,
  });
}

class PluginPermissionError implements Exception {
  final String permission;
  final String pluginId;
  PluginPermissionError(this.pluginId, this.permission);
  @override
  String toString() => '插件 $pluginId 缺少权限: $permission（请在 manifest.json 声明）';
}


class PluginContext {
  final String pluginId;
  final PluginManifest manifest;
  final PluginHostServices services;
  final PluginEventBus events;

  final List<void Function()> _undoRegistrations = [];
  final List<void Function()> _eventUnsubscribers = [];

  final void Function(String pluginId, PageRegistration reg) onPageRegistered;
  final void Function(String pluginId, CommandRegistration reg) onCommandRegistered;
  final void Function(String pluginId, InputBackendRegistration reg) onInputBackendRegistered;
  final void Function(String pluginId, VisionProviderRegistration reg) onVisionProviderRegistered;

  PluginContext({
    required this.pluginId,
    required this.manifest,
    required this.services,
    required this.events,
    required this.onPageRegistered,
    required this.onCommandRegistered,
    required this.onInputBackendRegistered,
    required this.onVisionProviderRegistered,
  });

  void registerPage(PageContribution contribution, WidgetBuilder builder) {
    final reg = PageRegistration(contribution, builder, pluginId);
    onPageRegistered(pluginId, reg);
    _undoRegistrations.add(() {});
  }

  void registerCommand(
    CommandContribution contribution,
    FutureOr<Object?> Function(Map<String, dynamic> params) handler,
  ) {
    final reg = CommandRegistration(contribution, handler, pluginId);
    onCommandRegistered(pluginId, reg);
  }

  void registerInputBackend(
    InputBackendContribution contribution,
    InputBackend Function() factory,
  ) {
    final reg = InputBackendRegistration(contribution, factory, pluginId);
    onInputBackendRegistered(pluginId, reg);
  }

  void registerVisionProvider(
    VisionProviderContribution contribution,
    VisionPlugin Function() factory,
  ) {
    final reg = VisionProviderRegistration(contribution, factory, pluginId);
    onVisionProviderRegistered(pluginId, reg);
  }

  void Function() on(String event, PluginEventHandler handler) {
    final unsubscribe = events.on(event, handler, subscriber: pluginId);
    _eventUnsubscribers.add(unsubscribe);
    return unsubscribe;
  }

  Future<void> emit(String event, [Map<String, dynamic>? data]) =>
      events.emit(event, data);

  void dispose() {
    for (final unsub in _eventUnsubscribers) {
      unsub();
    }
    _eventUnsubscribers.clear();
    _undoRegistrations.clear();
  }
}
