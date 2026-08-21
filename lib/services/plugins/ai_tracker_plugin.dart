/// AI tracker plugin — 基于 ONNX Runtime 的 YOLO 目标检测与跟踪。
/// 加载外部 ai_tracker 动态库（data/plugins/ai_tracker/…）。
library;

import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

import '../plugin/plugin_api.dart';
import '../plugin/plugin_manifest.dart';
import '../plugin/plugin_manager.dart';
import '../app_paths.dart';

typedef ExecuteActionNative = Int32 Function(
  Pointer<Utf8> actionId, Pointer<Utf8> params, Pointer<Utf8> outBuf, Int32 outSize);
typedef ExecuteActionDart = int Function(
  Pointer<Utf8> actionId, Pointer<Utf8> params, Pointer<Utf8> outBuf, int outSize);

typedef InitializeNative = Int32 Function();
typedef InitializeDart = int Function();

typedef DisposeNative = Void Function();
typedef DisposeDart = void Function();

class AiTrackerPlugin extends Plugin {
  DynamicLibrary? _library;
  ExecuteActionDart? _executeAction;
  InitializeDart? _initializeFn;
  DisposeDart? _disposeFn;
  bool _nativeLoaded = false;

  @override
  final PluginManifest manifest = const PluginManifest(
    id: 'ai_tracker',
    name: 'AI图像跟踪',
    version: '1.0.0',
    author: 'Clicker',
    description: '基于ONNX Runtime的YOLO目标检测与跟踪',
    category: 'vision',
    platforms: ['windows', 'linux', 'android'],
    runtime: PluginRuntime.dart,
    permissions: [PluginPermission.screen],
    activationEvents: ['manual'],
    icon: 'machine_learning',
  );

  bool get nativeLoaded => _nativeLoaded;

  /// 激活：真实加载动态库并初始化
  @override
  Future<void> onActivate(PluginContext context) async {
    await loadNativeAsync();
  }

  /// 停用：释放动态库资源
  @override
  Future<void> onDeactivate() async {
    unloadNative();
  }

  bool loadNative() {
    if (_nativeLoaded) return true;
    final dllPath = _getNativeDllPathSync();
    if (dllPath == null) return false;
    return _openAndBind(dllPath);
  }

  Future<bool> loadNativeAsync() async {
    if (_nativeLoaded) return true;
    final dllPath = await _getNativeDllPath();
    if (dllPath == null) return false;
    return _openAndBind(dllPath);
  }

  bool _openAndBind(String dllPath) {
    try {
      _library = DynamicLibrary.open(dllPath);
      try {
        _executeAction = _library!.lookupFunction<ExecuteActionNative, ExecuteActionDart>(
            'plugin_execute_action');
      } catch (_) {
        _executeAction = null;
      }
      try {
        _initializeFn = _library!.lookupFunction<InitializeNative, InitializeDart>(
            'plugin_initialize');
      } catch (_) {
        _initializeFn = null;
      }
      try {
        _disposeFn = _library!.lookupFunction<DisposeNative, DisposeDart>(
            'plugin_dispose');
      } catch (_) {
        _disposeFn = null;
      }

      if (_initializeFn != null) {
        final initResult = _initializeFn!();
        if (initResult != 0) {
          debugPrint('[AiTrackerPlugin] plugin_initialize failed: $initResult');
        }
      }

      _nativeLoaded = true;
      return true;
    } catch (e) {
      _library = null;
      _executeAction = null;
      _initializeFn = null;
      _disposeFn = null;
      _nativeLoaded = false;
      return false;
    }
  }

  String? _getNativeDllPathSync() {
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    final sep = Platform.pathSeparator;

    if (Platform.isWindows) {
      final candidates = [
        '$exeDir${sep}data${sep}plugins${sep}ai_tracker${sep}windows${sep}ai_tracker.dll',
        '$exeDir${sep}plugins${sep}ai_tracker${sep}windows${sep}ai_tracker.dll',
      ];
      try {
        final dataDir = Directory('$exeDir${sep}data');
        if (dataDir.existsSync()) {
          for (final entity in dataDir.listSync(recursive: true)) {
            if (entity is File && entity.path.endsWith('ai_tracker.dll')) {
              return entity.path;
            }
          }
        }
      } catch (_) {}
      for (final path in candidates) {
        if (File(path).existsSync()) return path;
      }
    } else if (Platform.isLinux) {
      final candidates = [
        '$exeDir${sep}data${sep}plugins${sep}ai_tracker${sep}linux${sep}libai_tracker.so',
        '$exeDir${sep}lib${sep}libai_tracker.so',
      ];
      for (final path in candidates) {
        if (File(path).existsSync()) return path;
      }
    } else if (Platform.isAndroid) {
      return 'libai_tracker.so';
    }
    return null;
  }

  Future<String?> _getNativeDllPath() async {
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    final sep = Platform.pathSeparator;

    if (Platform.isWindows) {
      final pluginDir = await AppPaths.getPluginDir('ai_tracker');
      final candidates = [
        '$exeDir${sep}data${sep}plugins${sep}ai_tracker${sep}windows${sep}ai_tracker.dll',
        '$exeDir${sep}plugins${sep}ai_tracker${sep}windows${sep}ai_tracker.dll',
        '$pluginDir${sep}windows${sep}ai_tracker.dll',
      ];
      try {
        final dataDir = Directory('$exeDir${sep}data');
        if (dataDir.existsSync()) {
          for (final entity in dataDir.listSync(recursive: true)) {
            if (entity is File && entity.path.endsWith('ai_tracker.dll')) {
              return entity.path;
            }
          }
        }
      } catch (_) {}
      for (final path in candidates) {
        if (File(path).existsSync()) return path;
      }
    } else if (Platform.isLinux) {
      final pluginDir = await AppPaths.getPluginDir('ai_tracker');
      final candidates = [
        '$exeDir${sep}data${sep}plugins${sep}ai_tracker${sep}linux${sep}libai_tracker.so',
        '$exeDir${sep}lib${sep}libai_tracker.so',
        '$pluginDir${sep}linux${sep}libai_tracker.so',
      ];
      for (final path in candidates) {
        if (File(path).existsSync()) return path;
      }
    } else if (Platform.isAndroid) {
      return 'libai_tracker.so';
    }
    return null;
  }

  String? executeAction(String actionId, String params, {bool returnOnError = false}) {
    if (!_nativeLoaded || _executeAction == null) return null;
    final actionIdPtr = actionId.toNativeUtf8();
    final paramsPtr = params.toNativeUtf8();
    final outBuf = calloc<Uint8>(65536);
    try {
      outBuf.cast<Uint8>().asTypedList(65536).fillRange(0, 65536, 0);
      final rc = _executeAction!(actionIdPtr, paramsPtr, outBuf.cast<Utf8>(), 65536);
      if (rc != 0) {
        if (returnOnError) {
          try {
            final errStr = outBuf.cast<Utf8>().toDartString();
            if (errStr.isNotEmpty) return errStr;
          } catch (_) {}
        }
        return null;
      }
      return outBuf.cast<Utf8>().toDartString();
    } catch (_) {
      return null;
    } finally {
      calloc.free(actionIdPtr);
      calloc.free(paramsPtr);
      calloc.free(outBuf);
    }
  }

  void unloadNative() {
    if (!_nativeLoaded) return;
    try {
      _disposeFn?.call();
    } catch (_) {}
    _library = null;
    _executeAction = null;
    _initializeFn = null;
    _disposeFn = null;
    _nativeLoaded = false;
  }

  /// 取当前激活的 AiTrackerPlugin 实例（供视觉子系统使用）
  static AiTrackerPlugin? activeInstance() {
    final desc = PluginManager.instance.byId('ai_tracker');
    return desc?.dartInstance is AiTrackerPlugin
        ? desc!.dartInstance as AiTrackerPlugin
        : null;
  }
}
