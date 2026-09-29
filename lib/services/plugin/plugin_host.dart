
import 'dart:async';

import 'package:flutter/foundation.dart';

import 'plugin_api.dart';
import 'plugin_event_bus.dart';

class PluginHost extends ChangeNotifier {
  PluginHost._();
  static final PluginHost instance = PluginHost._();

  final PluginEventBus events = PluginEventBus();
  PluginHostServices? _services;


  final Map<String, PageRegistration> _pages = {};
  final Map<String, CommandRegistration> _commands = {};
  final Map<String, InputBackendRegistration> _inputBackends = {};
  final Map<String, VisionProviderRegistration> _visionProviders = {};

  List<PageRegistration> get pages {
    final list = _pages.values.toList()
      ..sort((a, b) => a.contribution.order.compareTo(b.contribution.order));
    return list;
  }

  List<PageRegistration> get navPages =>
      pages.where((p) => p.contribution.showInNav).toList();

  List<CommandRegistration> get commands => _commands.values.toList();

  List<InputBackendRegistration> get inputBackends => _inputBackends.values.toList();

  List<VisionProviderRegistration> get visionProviders =>
      _visionProviders.values.toList();

  PageRegistration? page(String id) => _pages[id];
  CommandRegistration? command(String id) => _commands[id];
  InputBackendRegistration? inputBackend(String id) => _inputBackends[id];
  VisionProviderRegistration? visionProvider(String id) => _visionProviders[id];

  void setServices(PluginHostServices services) => _services = services;

  PluginHostServices get services {
    assert(_services != null, 'PluginHost.setServices 必须在插件激活前调用');
    return _services!;
  }


  void registerPage(String pluginId, PageRegistration reg) {
    _pages[reg.contribution.id] = reg;
    notifyListeners();
  }

  void registerCommand(String pluginId, CommandRegistration reg) {
    _commands[reg.contribution.id] = reg;
    notifyListeners();
  }

  void registerInputBackend(String pluginId, InputBackendRegistration reg) {
    _inputBackends[reg.contribution.id] = reg;
    notifyListeners();
  }

  void registerVisionProvider(String pluginId, VisionProviderRegistration reg) {
    _visionProviders[reg.contribution.id] = reg;
    notifyListeners();
  }

  void removeContributions(String pluginId) {
    _pages.removeWhere((_, reg) => reg.pluginId == pluginId);
    _commands.removeWhere((_, reg) => reg.pluginId == pluginId);
    _inputBackends.removeWhere((_, reg) => reg.pluginId == pluginId);
    _visionProviders.removeWhere((_, reg) => reg.pluginId == pluginId);
    notifyListeners();
  }


  Future<Object?> executeCommand(String commandId,
      [Map<String, dynamic> params = const {}]) async {
    final reg = _commands[commandId];
    if (reg != null) {
      return reg.handler(params);
    }
    final manager = pluginManagerActivator;
    if (manager != null) {
      final activated = await manager.activateForCommand(commandId);
      if (activated) {
        final reg2 = _commands[commandId];
        if (reg2 != null) return reg2.handler(params);
      }
    }
    return null;
  }

  PluginManagerCommandActivator? pluginManagerActivator;

  @override
  void dispose() {
    _pages.clear();
    _commands.clear();
    _inputBackends.clear();
    _visionProviders.clear();
    super.dispose();
  }
}

abstract class PluginManagerCommandActivator {
  Future<bool> activateForCommand(String commandId);
}

typedef SyncScreenCapture = Uint8List? Function(int x, int y, int w, int h);
