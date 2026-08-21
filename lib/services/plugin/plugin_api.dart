/// 插件 API — 新插件系统的核心接口。
///
/// 一个 Dart 插件实现 [Plugin]，在 [onActivate] 中通过 [PluginContext]
/// 注册贡献（页面/命令/输入后端/视觉提供者）并分配资源；
/// 在 [onDeactivate] 中释放全部资源。宿主保证：
/// - 激活前不会创建插件实例（工厂惰性实例化）
/// - 停用后插件实例被丢弃，重新激活时重建
/// - 停用时自动取消事件订阅、移除全部贡献
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import 'plugin_manifest.dart';
import 'plugin_event_bus.dart';
import '../vision_plugin.dart';

// ─── 插件接口 ──────────────────────────────────────────────

/// Dart 插件基类
abstract class Plugin {
  PluginManifest get manifest;

  /// 激活：注册贡献、分配资源。失败应抛异常，宿主会回滚。
  Future<void> onActivate(PluginContext context);

  /// 停用：释放全部资源。此后实例不再被使用。
  Future<void> onDeactivate();
}

/// Dart 插件工厂 — 注册时只保存工厂，激活才实例化
typedef PluginFactory = Plugin Function();

// ─── 输入后端 ──────────────────────────────────────────────

/// 输入后端 — 一种输入注入方式的抽象。
/// 插件可实现此接口注册新的输入后端（如硬件驱动、合成 HID），
/// 宿主输入系统可在后端间切换。
abstract class InputBackend {
  String get id;
  String get name;

  /// 后端是否可用（如驱动已安装）
  bool get isAvailable;

  /// 激活后端（获取设备句柄等）
  Future<bool> initialize();

  /// 释放后端资源
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

// ─── 扩展点注册模型 ────────────────────────────────────────

/// 已注册的页面贡献
class PageRegistration {
  final PageContribution contribution;
  final WidgetBuilder builder;
  final String pluginId;
  const PageRegistration(this.contribution, this.builder, this.pluginId);
}

/// 已注册的命令贡献
class CommandRegistration {
  final CommandContribution contribution;
  final FutureOr<Object?> Function(Map<String, dynamic> params) handler;
  final String pluginId;
  const CommandRegistration(this.contribution, this.handler, this.pluginId);
}

/// 已注册的输入后端
class InputBackendRegistration {
  final InputBackendContribution contribution;
  final InputBackend Function() factory;
  final String pluginId;
  const InputBackendRegistration(this.contribution, this.factory, this.pluginId);
}

/// 已注册的视觉提供者
class VisionProviderRegistration {
  final VisionProviderContribution contribution;
  final VisionPlugin Function() factory;
  final String pluginId;
  const VisionProviderRegistration(this.contribution, this.factory, this.pluginId);
}

// ─── 宿主服务 ──────────────────────────────────────────────

/// 宿主服务 — 插件可调用的主程序能力。
/// 由 PluginHost 注入实现；权限不足时调用会抛 [PluginPermissionError]。
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

/// 权限错误
class PluginPermissionError implements Exception {
  final String permission;
  final String pluginId;
  PluginPermissionError(this.pluginId, this.permission);
  @override
  String toString() => '插件 $pluginId 缺少权限: $permission（请在 manifest.json 声明）';
}

// ─── 插件上下文 ────────────────────────────────────────────

/// 插件上下文 — 激活时注入，是插件访问宿主的唯一入口
class PluginContext {
  final String pluginId;
  final PluginManifest manifest;
  final PluginHostServices services;
  final PluginEventBus events;

  /// 激活期间注册的全部贡献（宿主持有，用于停用时移除）
  final List<void Function()> _undoRegistrations = [];
  final List<void Function()> _eventUnsubscribers = [];

  /// 页面注册回调（由 PluginHost 注入）
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

  /// 注册导航页面
  void registerPage(PageContribution contribution, WidgetBuilder builder) {
    final reg = PageRegistration(contribution, builder, pluginId);
    onPageRegistered(pluginId, reg);
    _undoRegistrations.add(() {});
    // 移除由 host 统一按 pluginId 处理，这里无需单独 undo
  }

  /// 注册命令（热键/脚本/宏均可触发）
  void registerCommand(
    CommandContribution contribution,
    FutureOr<Object?> Function(Map<String, dynamic> params) handler,
  ) {
    final reg = CommandRegistration(contribution, handler, pluginId);
    onCommandRegistered(pluginId, reg);
  }

  /// 注册输入后端
  void registerInputBackend(
    InputBackendContribution contribution,
    InputBackend Function() factory,
  ) {
    final reg = InputBackendRegistration(contribution, factory, pluginId);
    onInputBackendRegistered(pluginId, reg);
  }

  /// 注册视觉提供者（模板匹配/OCR/目标检测）
  void registerVisionProvider(
    VisionProviderContribution contribution,
    VisionPlugin Function() factory,
  ) {
    final reg = VisionProviderRegistration(contribution, factory, pluginId);
    onVisionProviderRegistered(pluginId, reg);
  }

  /// 订阅事件（停用时自动取消）
  void Function() on(String event, PluginEventHandler handler) {
    final unsubscribe = events.on(event, handler, subscriber: pluginId);
    _eventUnsubscribers.add(unsubscribe);
    return unsubscribe;
  }

  /// 发布事件
  Future<void> emit(String event, [Map<String, dynamic>? data]) =>
      events.emit(event, data);

  /// 停用清理：取消全部事件订阅
  void dispose() {
    for (final unsub in _eventUnsubscribers) {
      unsub();
    }
    _eventUnsubscribers.clear();
    _undoRegistrations.clear();
  }
}
