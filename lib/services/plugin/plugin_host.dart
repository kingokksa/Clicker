/// 插件宿主 — 扩展点注册中心 + 事件总线 + 宿主服务。
///
/// UI（导航、命令面板、设置页）从这里读取扩展点贡献；
/// 插件停用时其贡献被整体移除。宿主是 ChangeNotifier，
/// 任何扩展点变化都会通知 UI 重建。
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'plugin_api.dart';
import 'plugin_event_bus.dart';

/// 插件宿主（单例）
class PluginHost extends ChangeNotifier {
  PluginHost._();
  static final PluginHost instance = PluginHost._();

  final PluginEventBus events = PluginEventBus();
  PluginHostServices? _services;

  // ─── 扩展点注册表 ─────────────────────────────────────

  final Map<String, PageRegistration> _pages = {};
  final Map<String, CommandRegistration> _commands = {};
  final Map<String, InputBackendRegistration> _inputBackends = {};
  final Map<String, VisionProviderRegistration> _visionProviders = {};

  /// 全部已注册页面（按 order 排序）
  List<PageRegistration> get pages {
    final list = _pages.values.toList()
      ..sort((a, b) => a.contribution.order.compareTo(b.contribution.order));
    return list;
  }

  /// 导航可见页面
  List<PageRegistration> get navPages =>
      pages.where((p) => p.contribution.showInNav).toList();

  /// 全部已注册命令
  List<CommandRegistration> get commands => _commands.values.toList();

  /// 全部输入后端
  List<InputBackendRegistration> get inputBackends => _inputBackends.values.toList();

  /// 全部视觉提供者
  List<VisionProviderRegistration> get visionProviders =>
      _visionProviders.values.toList();

  PageRegistration? page(String id) => _pages[id];
  CommandRegistration? command(String id) => _commands[id];
  InputBackendRegistration? inputBackend(String id) => _inputBackends[id];
  VisionProviderRegistration? visionProvider(String id) => _visionProviders[id];

  /// 注入宿主服务（由 AppState 在初始化时提供）
  void setServices(PluginHostServices services) => _services = services;

  PluginHostServices get services {
    assert(_services != null, 'PluginHost.setServices 必须在插件激活前调用');
    return _services!;
  }

  // ─── 注册（由 PluginContext 回调）────────────────────

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

  /// 移除某插件的全部贡献（停用时调用）
  void removeContributions(String pluginId) {
    _pages.removeWhere((_, reg) => reg.pluginId == pluginId);
    _commands.removeWhere((_, reg) => reg.pluginId == pluginId);
    _inputBackends.removeWhere((_, reg) => reg.pluginId == pluginId);
    _visionProviders.removeWhere((_, reg) => reg.pluginId == pluginId);
    notifyListeners();
  }

  // ─── 命令执行（自动按需激活插件）────────────────────

  /// 执行命令。若命令所属插件未激活，先激活再执行。
  Future<Object?> executeCommand(String commandId,
      [Map<String, dynamic> params = const {}]) async {
    final reg = _commands[commandId];
    if (reg != null) {
      return reg.handler(params);
    }
    // 未注册：可能插件未激活，交给管理器按需激活后重试
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

  /// 管理器引用（避免循环依赖，由 PluginManager 注入）
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

/// 命令按需激活桥（由 PluginManager 实现）
abstract class PluginManagerCommandActivator {
  /// 激活声明了 onCommand:<id> 的插件；返回是否成功
  Future<bool> activateForCommand(String commandId);
}

/// 同步屏幕捕获钩子（native 回调用）
typedef SyncScreenCapture = Uint8List? Function(int x, int y, int w, int h);
