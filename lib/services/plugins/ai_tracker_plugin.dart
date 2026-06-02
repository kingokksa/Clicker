library;

import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:fluent_ui/fluent_ui.dart';
import '../plugin_system.dart';
import '../app_paths.dart';
import '../../screens/sidebar/ai_tracker_page.dart';

typedef ExecuteActionNative = Int32 Function(
  Pointer<Utf8> actionId,
  Pointer<Utf8> params,
  Pointer<Utf8> outBuf,
  Int32 outSize,
);
typedef ExecuteActionDart = int Function(
  Pointer<Utf8> actionId,
  Pointer<Utf8> params,
  Pointer<Utf8> outBuf,
  int outSize,
);

typedef InitializeNative = Int32 Function();
typedef InitializeDart = int Function();

typedef DisposeNative = Void Function();
typedef DisposeDart = void Function();

class AiTrackerPlugin extends ClickerPlugin {
  DynamicLibrary? _library;
  ExecuteActionDart? _executeAction;
  InitializeDart? _initializeFn;
  DisposeDart? _disposeFn;
  bool _nativeLoaded = false;

  @override
  final manifest = const ClickerPluginManifest(
    id: 'ai_tracker',
    name: 'AI图像跟踪',
    version: '1.0.0',
    author: 'Clicker',
    description: '基于ONNX Runtime的YOLO目标检测与跟踪',
    icon: FluentIcons.machine_learning,
    category: PluginCategory.vision,
    source: PluginSource.builtin,
    platforms: ['windows', 'linux', 'android'],
  );

  bool get nativeLoaded => _nativeLoaded;

  bool loadNative() {
    if (_nativeLoaded) return true;

    final dllPath = _getNativeDllPath();
    if (dllPath == null) return false;

    try {
      _library = DynamicLibrary.open(dllPath);
      try {
        _executeAction = _library!.lookupFunction<ExecuteActionNative, ExecuteActionDart>(
          'plugin_execute_action',
        );
      } catch (_) {
        _executeAction = null;
      }
      try {
        _initializeFn = _library!.lookupFunction<InitializeNative, InitializeDart>(
          'plugin_initialize',
        );
      } catch (_) {
        _initializeFn = null;
      }
      try {
        _disposeFn = _library!.lookupFunction<DisposeNative, DisposeDart>(
          'plugin_dispose',
        );
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

  String? _getNativeDllPath() {
    final exePath = Platform.resolvedExecutable;
    final exeDir = File(exePath).parent.path;
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
        '$exeDir${sep}plugins${sep}ai_tracker${sep}linux${sep}libai_tracker.so',
      ];

      try {
        final dataDir = Directory('$exeDir${sep}data');
        if (dataDir.existsSync()) {
          for (final entity in dataDir.listSync(recursive: true)) {
            if (entity is File && entity.path.endsWith('libai_tracker.so')) {
              return entity.path;
            }
          }
        }
      } catch (_) {}

      try {
        final libDir = Directory('$exeDir${sep}lib');
        if (libDir.existsSync()) {
          for (final entity in libDir.listSync(recursive: true)) {
            if (entity is File && entity.path.endsWith('libai_tracker.so')) {
              return entity.path;
            }
          }
        }
      } catch (_) {}

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

  @override
  Future<void> onInitialize() async {}

  @override
  Future<void> onDispose() async {
    unloadNative();
  }

  @override
  Future<void> onUninstall() async {
    unloadNative();
    final path = await AppPaths.getPluginDir('ai_tracker');
    final dir = Directory(path);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }

  @override
  Widget onCreatePage(BuildContext context) => const AiTrackerPage();
}
