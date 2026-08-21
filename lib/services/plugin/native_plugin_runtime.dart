/// 原生插件运行时 v2 — 动态加载 .dll/.so/.dylib 并提供宿主 C 回调函数表。
///
/// 真实即需即用：
/// - 安装后只解析 manifest.json（零加载开销）
/// - 激活时才 DynamicLibrary.open 并调用 plugin_initialize(host_api)
/// - 停用时调用 plugin_deactivate + plugin_dispose 释放原生资源
///
/// v2 C API（推荐，见 sdk/clicker_plugin.h）：
///   plugin_initialize_v2(const ClickerHostApi* host, const char* plugin_dir)
///   plugin_activate_v2(const char* event)
///   plugin_deactivate_v2()
///   plugin_dispose_v2()
///   plugin_execute_command_v2(id, params_json, out, out_size)
///
/// v1 兼容（旧插件如 ai_tracker）：plugin_initialize() / plugin_dispose() /
/// plugin_execute_action() / plugin_template_match() / plugin_ocr()
///
/// 宿主回调只能在宿主发起的调用栈内同步使用（isolateLocal），
/// 即插件在 plugin_execute_command 等函数执行期间调用是安全的。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'plugin_api.dart';
import 'plugin_manifest.dart';
import 'plugin_storage.dart';

// ─── C 结构体定义（与 sdk/clicker_plugin.h 严格一致）────────

/// 宿主 API 函数表（C 侧）
final class ClickerHostApiC extends Struct {
  @Uint32()
  external int structSize;

  // 日志
  external Pointer<NativeFunction<Void Function(Int32, Pointer<Utf8>, Pointer<Utf8>)>> log;

  // 输入（需 input 权限）
  external Pointer<NativeFunction<Void Function(Int32, Int32, Int32)>> sendMouseDown;
  external Pointer<NativeFunction<Void Function(Int32, Int32, Int32)>> sendMouseUp;
  external Pointer<NativeFunction<Void Function(Uint16)>> sendKeyDown;
  external Pointer<NativeFunction<Void Function(Uint16)>> sendKeyUp;
  external Pointer<NativeFunction<Void Function(Int32, Int32)>> moveCursor;
  external Pointer<NativeFunction<Void Function(Double, Double)>> scroll;

  // 屏幕（需 screen 权限）
  external Pointer<NativeFunction<Int32 Function(Int32, Int32, Int32, Int32, Pointer<Uint8>, Int32)>> captureScreen;

  // 存储（需 storage 权限）
  external Pointer<NativeFunction<Int32 Function(Pointer<Utf8>, Pointer<Utf8>, Int32)>> storageGet;
  external Pointer<NativeFunction<Int32 Function(Pointer<Utf8>, Pointer<Utf8>)>> storageSet;

  // 事件 / 通知
  external Pointer<NativeFunction<Void Function(Pointer<Utf8>, Pointer<Utf8>)>> emitEvent;
  external Pointer<NativeFunction<Void Function(Pointer<Utf8>, Pointer<Utf8>)>> showNotification;

  // 剪贴板（需 clipboard 权限）
  external Pointer<NativeFunction<Int32 Function(Pointer<Utf8>, Int32)>> readClipboard;
  external Pointer<NativeFunction<Void Function(Pointer<Utf8>)>> writeClipboard;

  // 内存
  external Pointer<NativeFunction<Void Function(Pointer<Void>)>> freeBuffer;
}

/// PluginInfo v2（C 侧）
final class PluginInfoV2C extends Struct {
  @Uint32()
  external int apiVersion;
  external Pointer<Utf8> id;
  external Pointer<Utf8> name;
  external Pointer<Utf8> version;
  external Pointer<Utf8> author;
  external Pointer<Utf8> description;
  @Int32()
  external int category;
  @Uint32()
  external int capabilities;
}

// ─── 符号签名 ──────────────────────────────────────────────

// v2
typedef GetInfoV2Native = Pointer<PluginInfoV2C> Function();
typedef GetInfoV2Dart = Pointer<PluginInfoV2C> Function();

typedef InitializeV2Native = Int32 Function(Pointer<ClickerHostApiC>, Pointer<Utf8>);
typedef InitializeV2Dart = int Function(Pointer<ClickerHostApiC>, Pointer<Utf8>);

typedef ActivateV2Native = Int32 Function(Pointer<Utf8>);
typedef ActivateV2Dart = int Function(Pointer<Utf8>);

typedef DisposeV2Native = Void Function();
typedef DisposeV2Dart = void Function();

typedef ExecuteCommandV2Native = Int32 Function(
    Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>, Int32);
typedef ExecuteCommandV2Dart = int Function(
    Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>, int);

// v1 兼容
typedef InitializeV1Native = Int32 Function();
typedef InitializeV1Dart = int Function();
typedef DisposeV1Native = Void Function();
typedef DisposeV1Dart = void Function();
typedef ExecuteActionNative = Int32 Function(
    Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>, Int32);
typedef ExecuteActionDart = int Function(
    Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>, int);

// 视觉（v1/v2 通用）
typedef TemplateMatchNative = Int32 Function(
    Pointer<Uint8>, Int32, Int32, Pointer<Uint8>, Int32, Int32,
    Double, Pointer<NativeTemplateMatchResult>, Int32);
typedef TemplateMatchDart = int Function(
    Pointer<Uint8>, int, int, Pointer<Uint8>, int, int,
    double, Pointer<NativeTemplateMatchResult>, int);

typedef OcrNative = Int32 Function(
    Pointer<Uint8>, Int32, Int32, Pointer<Utf8>, Pointer<NativeOcrResult>);
typedef OcrDart = int Function(
    Pointer<Uint8>, int, int, Pointer<Utf8>, Pointer<NativeOcrResult>);

final class NativeTemplateMatchResult extends Struct {
  @Int32() external int x;
  @Int32() external int y;
  @Int32() external int width;
  @Int32() external int height;
  @Double() external double score;
}

final class NativeOcrLine extends Struct {
  @Array(256) external Array<Uint8> text;
  @Int32() external int x;
  @Int32() external int y;
  @Int32() external int width;
  @Int32() external int height;
}

final class NativeOcrResult extends Struct {
  @Array(64) external Array<NativeOcrLine> lines;
  @Int32() external int lineCount;
  @Int32() external int totalX;
  @Int32() external int totalY;
  @Int32() external int totalWidth;
  @Int32() external int totalHeight;
}

// ─── 宿主 API 实现 ─────────────────────────────────────────

/// 为单个原生插件构建宿主函数表
class NativeHostApiTable {
  final String pluginId;
  final PluginManifest manifest;
  final PluginHostServices services;
  final PluginStorageLike storage;
  final void Function(String event, String? data) onEvent;
  final void Function(int level, String tag, String msg) onLog;

  Pointer<ClickerHostApiC>? _table;
  final List<void Function()> _closers = [];

  NativeHostApiTable({
    required this.pluginId,
    required this.manifest,
    required this.services,
    required this.storage,
    required this.onEvent,
    required this.onLog,
  });

  bool get isCreated => _table != null;

  /// 分配并填充函数表
  Pointer<ClickerHostApiC> create() {
    if (_table != null) return _table!;
    _table = calloc<ClickerHostApiC>();
    final t = _table!.ref;
    t.structSize = sizeOf<ClickerHostApiC>();

    void require(String perm) {
      if (!manifest.permissions.contains(perm)) {
        throw PluginPermissionError(pluginId, perm);
      }
    }

    final log = NativeCallable<Void Function(Int32, Pointer<Utf8>, Pointer<Utf8>)>.isolateLocal(
      (int level, Pointer<Utf8> tag, Pointer<Utf8> msg) {
        onLog(level, tag.toDartString(), msg.toDartString());
      },
    );
    _closers.add(log.close);
    t.log = log.nativeFunction;

    final sendMouseDown = NativeCallable<Void Function(Int32, Int32, Int32)>.isolateLocal(
      (int x, int y, int button) {
        require(PluginPermission.input);
        services.mouseDown(x, y, _buttonName(button));
      },
    );
    _closers.add(sendMouseDown.close);
    t.sendMouseDown = sendMouseDown.nativeFunction;

    final sendMouseUp = NativeCallable<Void Function(Int32, Int32, Int32)>.isolateLocal(
      (int x, int y, int button) {
        require(PluginPermission.input);
        services.mouseUp(x, y, _buttonName(button));
      },
    );
    _closers.add(sendMouseUp.close);
    t.sendMouseUp = sendMouseUp.nativeFunction;

    final sendKeyDown = NativeCallable<Void Function(Uint16)>.isolateLocal((int vk) {
      require(PluginPermission.input);
      services.keyDown(_vkToName(vk));
    });
    _closers.add(sendKeyDown.close);
    t.sendKeyDown = sendKeyDown.nativeFunction;

    final sendKeyUp = NativeCallable<Void Function(Uint16)>.isolateLocal((int vk) {
      require(PluginPermission.input);
      services.keyUp(_vkToName(vk));
    });
    _closers.add(sendKeyUp.close);
    t.sendKeyUp = sendKeyUp.nativeFunction;

    final moveCursor = NativeCallable<Void Function(Int32, Int32)>.isolateLocal((int x, int y) {
      require(PluginPermission.input);
      services.moveCursor(x, y);
    });
    _closers.add(moveCursor.close);
    t.moveCursor = moveCursor.nativeFunction;

    final scroll = NativeCallable<Void Function(Double, Double)>.isolateLocal((double dx, double dy) {
      require(PluginPermission.input);
      services.scroll(dx, dy);
    });
    _closers.add(scroll.close);
    t.scroll = scroll.nativeFunction;

    final captureScreen = NativeCallable<
        Int32 Function(Int32, Int32, Int32, Int32, Pointer<Uint8>, Int32)>.isolateLocal(
      (int x, int y, int w, int h, Pointer<Uint8> out, int capacity) {
        if (!manifest.permissions.contains(PluginPermission.screen)) {
          return -1;
        }
        final need = w * h * 4;
        if (capacity < need) return -2;
        // captureScreen 是异步签名；此处为同步 C 回调，采用同步执行 Future
        final data = _captureSync(x, y, w, h);
        if (data == null) return -3;
        out.asTypedList(need).setAll(0, data);
        return need;
      },
      exceptionalReturn: -1,
    );
    _closers.add(captureScreen.close);
    t.captureScreen = captureScreen.nativeFunction;

    final storageGet =
        NativeCallable<Int32 Function(Pointer<Utf8>, Pointer<Utf8>, Int32)>.isolateLocal(
      (Pointer<Utf8> key, Pointer<Utf8> out, int outSize) {
        if (!manifest.permissions.contains(PluginPermission.storage)) return -1;
        final value = storage.getSync(key.toDartString());
        if (value == null) return -2;
        final bytes = utf8.encode(value is String ? value : jsonEncode(value));
        if (bytes.length + 1 > outSize) return -3;
        out.cast<Uint8>().asTypedList(outSize).setAll(0, bytes);
        out.cast<Uint8>().asTypedList(outSize)[bytes.length] = 0;
        return bytes.length;
      },
      exceptionalReturn: -1,
    );
    _closers.add(storageGet.close);
    t.storageGet = storageGet.nativeFunction;

    final storageSet = NativeCallable<Int32 Function(Pointer<Utf8>, Pointer<Utf8>)>.isolateLocal(
      (Pointer<Utf8> key, Pointer<Utf8> value) {
        if (!manifest.permissions.contains(PluginPermission.storage)) return -1;
        storage.setSync(key.toDartString(), value.toDartString());
        return 0;
      },
      exceptionalReturn: -1,
    );
    _closers.add(storageSet.close);
    t.storageSet = storageSet.nativeFunction;

    final emitEvent = NativeCallable<Void Function(Pointer<Utf8>, Pointer<Utf8>)>.isolateLocal(
      (Pointer<Utf8> event, Pointer<Utf8> data) {
        final raw = data.toDartString();
        onEvent(event.toDartString(), raw.isEmpty ? null : raw);
      },
    );
    _closers.add(emitEvent.close);
    t.emitEvent = emitEvent.nativeFunction;

    final showNotification =
        NativeCallable<Void Function(Pointer<Utf8>, Pointer<Utf8>)>.isolateLocal(
      (Pointer<Utf8> title, Pointer<Utf8> msg) {
        if (!manifest.permissions.contains(PluginPermission.notifications)) return;
        services.showNotification(title.toDartString(), msg.toDartString());
      },
    );
    _closers.add(showNotification.close);
    t.showNotification = showNotification.nativeFunction;

    final readClipboard = NativeCallable<Int32 Function(Pointer<Utf8>, Int32)>.isolateLocal(
      (Pointer<Utf8> out, int outSize) {
        if (!manifest.permissions.contains(PluginPermission.clipboard)) return -1;
        final text = _clipboardSync();
        if (text == null) return -2;
        final bytes = utf8.encode(text);
        if (bytes.length + 1 > outSize) return -3;
        out.cast<Uint8>().asTypedList(outSize).setAll(0, bytes);
        out.cast<Uint8>().asTypedList(outSize)[bytes.length] = 0;
        return bytes.length;
      },
      exceptionalReturn: -1,
    );
    _closers.add(readClipboard.close);
    t.readClipboard = readClipboard.nativeFunction;

    final writeClipboard = NativeCallable<Void Function(Pointer<Utf8>)>.isolateLocal(
      (Pointer<Utf8> text) {
        if (!manifest.permissions.contains(PluginPermission.clipboard)) return;
        _writeClipboardSync(text.toDartString());
      },
    );
    _closers.add(writeClipboard.close);
    t.writeClipboard = writeClipboard.nativeFunction;

    final freeBuffer = NativeCallable<Void Function(Pointer<Void>)>.isolateLocal((Pointer<Void> p) {
      calloc.free(p);
    });
    _closers.add(freeBuffer.close);
    t.freeBuffer = freeBuffer.nativeFunction;

    return _table!;
  }

  /// 同步屏幕捕获（原生回调场景）
  Uint8List? _captureSync(int x, int y, int w, int h) {
    return _syncCaptureHook?.call(x, y, w, h);
  }

  String? _clipboardSync() => _clipboardHook?.call();
  void _writeClipboardSync(String text) => _writeClipboardHook?.call(text);

  /// 同步捕获钩子（由宿主注入，避免异步 Future）
  static Future<Uint8List?> Function(int, int, int, int)? asyncCapture;
  static Future<String?> Function()? asyncClipboardRead;
  static Future<void> Function(String)? asyncClipboardWrite;

  static Uint8List? Function(int, int, int, int)? _syncCaptureHook;
  static String? Function()? _clipboardHook;
  static void Function(String)? _writeClipboardHook;

  static void installSyncHooks({
    Uint8List? Function(int, int, int, int)? capture,
    String? Function()? readClipboard,
    void Function(String)? writeClipboard,
  }) {
    _syncCaptureHook = capture;
    _clipboardHook = readClipboard;
    _writeClipboardHook = writeClipboard;
  }

  /// 释放函数表与全部 callable
  void dispose() {
    for (final close in _closers) {
      try { close(); } catch (_) {}
    }
    _closers.clear();
    if (_table != null) {
      calloc.free(_table!);
      _table = null;
    }
  }

  static String _buttonName(int button) {
    switch (button) {
      case 0: return 'left';
      case 1: return 'right';
      case 2: return 'middle';
      case 3: return 'x1';
      case 4: return 'x2';
      default: return 'left';
    }
  }

  static String _vkToName(int vk) => 'vk:$vk';
}

// ─── 原生插件实例 ──────────────────────────────────────────

/// 已加载的原生插件实例
class NativePluginInstance {
  final PluginManifest manifest;
  final String libraryPath;
  final String pluginDir;

  DynamicLibrary? _lib;
  bool _isV2 = false;
  bool _loaded = false;
  bool _initialized = false;
  bool _activated = false;
  NativeHostApiTable? _hostTable;

  // 符号
  GetInfoV2Dart? _getInfoV2;
  InitializeV2Dart? _initializeV2;
  ActivateV2Dart? _activateV2;
  DisposeV2Dart? _disposeV2;
  DisposeV2Dart? _deactivateV2;
  ExecuteCommandV2Dart? _executeCommandV2;
  InitializeV1Dart? _initializeV1;
  DisposeV1Dart? _disposeV1;
  ExecuteActionDart? _executeActionV1;
  TemplateMatchDart? _templateMatch;
  OcrDart? _ocr;

  NativePluginInstance({
    required this.manifest,
    required this.libraryPath,
    required this.pluginDir,
  });

  bool get isLoaded => _loaded;
  bool get isActivated => _activated;
  bool get isV2 => _isV2;
  bool get supportsTemplateMatch => _templateMatch != null;
  bool get supportsOcr => _ocr != null;

  /// 打开动态库并绑定符号（不初始化）
  bool open() {
    if (_loaded) return true;
    try {
      _lib = DynamicLibrary.open(libraryPath);
    } catch (_) {
      return false;
    }
    final lib = _lib!;
    // v2 探测
    _getInfoV2 = _lookupOpt(lib, 'plugin_get_info_v2', _bindGetInfoV2);
    _initializeV2 = _lookupOpt(lib, 'plugin_initialize_v2', _bindInitV2);
    _activateV2 = _lookupOpt(lib, 'plugin_activate_v2', _bindActivateV2);
    _deactivateV2 = _lookupOpt(lib, 'plugin_deactivate_v2', _bindDisposeV2);
    _disposeV2 = _lookupOpt(lib, 'plugin_dispose_v2', _bindDisposeV2);
    _executeCommandV2 = _lookupOpt(lib, 'plugin_execute_command_v2', _bindExecCmdV2);
    _isV2 = _initializeV2 != null;

    // v1 兼容符号
    _initializeV1 = _lookupOpt(lib, 'plugin_initialize', _bindInitV1);
    _disposeV1 = _lookupOpt(lib, 'plugin_dispose', _bindDisposeV1);
    _executeActionV1 = _lookupOpt(lib, 'plugin_execute_action', _bindExecActionV1);
    _templateMatch = _lookupOpt(lib, 'plugin_template_match', _bindTemplateMatch);
    _ocr = _lookupOpt(lib, 'plugin_ocr', _bindOcr);

    _loaded = true;
    return true;
  }

  /// 初始化：v2 传入宿主函数表；v1 直接调用
  bool initialize(NativeHostApiTable hostTable) {
    if (!_loaded || _initialized) return _initialized;
    _hostTable = hostTable;
    try {
      if (_isV2) {
        // 身份校验：库声明的 id 必须与 manifest 一致（防止目录伪装）
        final info = _getInfoV2?.call();
        if (info != null && info.ref.id != nullptr) {
          final libId = info.ref.id.toDartString();
          if (libId.isNotEmpty && libId != manifest.id) {
            return false;
          }
        }
        final dirPtr = pluginDir.toNativeUtf8();
        try {
          final rc = _initializeV2!(hostTable.create(), dirPtr);
          if (rc != 0) return false;
        } finally {
          calloc.free(dirPtr);
        }
      } else {
        final init = _initializeV1;
        if (init != null && init() != 0) return false;
      }
      _initialized = true;
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 激活
  bool activate(String activationEvent) {
    if (!_initialized || _activated) return _activated;
    if (_isV2 && _activateV2 != null) {
      final evPtr = activationEvent.toNativeUtf8();
      try {
        if (_activateV2!(evPtr) != 0) return false;
      } finally {
        calloc.free(evPtr);
      }
    }
    // v1 无激活概念，初始化即激活
    _activated = true;
    return true;
  }

  /// 停用（释放原生资源；动态库句柄保留以便重新激活）
  void deactivate() {
    if (!_activated) return;
    try { _deactivateV2?.call(); } catch (_) {}
    _activated = false;
  }

  /// 卸载前清理
  void dispose() {
    deactivate();
    try { _disposeV2?.call(); } catch (_) {}
    try { _disposeV1?.call(); } catch (_) {}
    _hostTable?.dispose();
    _hostTable = null;
    _initialized = false;
    _loaded = false;
    _lib = null;
    _getInfoV2 = null;
    _initializeV2 = null;
    _activateV2 = null;
    _deactivateV2 = null;
    _disposeV2 = null;
    _executeCommandV2 = null;
    _initializeV1 = null;
    _disposeV1 = null;
    _executeActionV1 = null;
    _templateMatch = null;
    _ocr = null;
  }

  /// 执行命令。返回 JSON 字符串结果；失败返回 null / [error]
  ({bool ok, String? result, String? error}) executeCommand(
    String commandId,
    Map<String, dynamic> params,
  ) {
    final exec = _executeCommandV2 ?? _executeActionV1;
    if (exec == null) return (ok: false, result: null, error: '插件未导出命令接口');
    final idPtr = commandId.toNativeUtf8();
    final paramsPtr = jsonEncode(params).toNativeUtf8();
    final outBuf = calloc<Uint8>(65536);
    try {
      outBuf.cast<Uint8>().asTypedList(65536).fillRange(0, 65536, 0);
      final rc = exec(idPtr, paramsPtr, outBuf.cast<Utf8>(), 65536);
      final out = outBuf.cast<Utf8>().toDartString();
      if (rc != 0) {
        return (ok: false, result: null, error: out.isNotEmpty ? out : '错误码 $rc');
      }
      return (ok: true, result: out.isNotEmpty ? out : null, error: null);
    } catch (e) {
      return (ok: false, result: null, error: e.toString());
    } finally {
      calloc.free(idPtr);
      calloc.free(paramsPtr);
      calloc.free(outBuf);
    }
  }

  /// 模板匹配（视觉插件）
  List<({int x, int y, int width, int height, double score})>? templateMatch(
    Uint8List regionPixels, int regionW, int regionH,
    Uint8List tplPixels, int tplW, int tplH,
    double threshold, int maxResults,
  ) {
    if (_templateMatch == null) return null;
    final regionPtr = calloc<Uint8>(regionPixels.length);
    final tplPtr = calloc<Uint8>(tplPixels.length);
    final results = calloc<NativeTemplateMatchResult>(maxResults);
    try {
      regionPtr.asTypedList(regionPixels.length).setAll(0, regionPixels);
      tplPtr.asTypedList(tplPixels.length).setAll(0, tplPixels);
      final count = _templateMatch!(regionPtr, regionW, regionH,
          tplPtr, tplW, tplH, threshold, results, maxResults);
      return List.generate(count.clamp(0, maxResults), (i) {
        final r = results[i];
        return (x: r.x, y: r.y, width: r.width, height: r.height, score: r.score);
      });
    } catch (_) {
      return null;
    } finally {
      calloc.free(regionPtr);
      calloc.free(tplPtr);
      calloc.free(results);
    }
  }

  /// OCR（视觉插件）
  ({String text, int x, int y, int w, int h})? ocr(
    Uint8List pixels, int w, int h, String language,
  ) {
    if (_ocr == null) return null;
    final imgPtr = calloc<Uint8>(pixels.length);
    final langPtr = language.toNativeUtf8();
    final result = calloc<NativeOcrResult>();
    try {
      imgPtr.asTypedList(pixels.length).setAll(0, pixels);
      if (_ocr!(imgPtr, w, h, langPtr, result) != 0) return null;
      final r = result.ref;
      final lines = <String>[];
      for (int i = 0; i < r.lineCount.clamp(0, 64); i++) {
        // lines 是 NativeOcrResult 首字段（偏移 0）；text 是 NativeOcrLine 首字段（偏移 0）
        final textPtr = Pointer<Uint8>.fromAddress(
            result.address + i * sizeOf<NativeOcrLine>());
        final bytes = textPtr.asTypedList(256);
        final end = bytes.indexOf(0);
        lines.add(utf8.decode(end < 0 ? bytes : bytes.sublist(0, end), allowMalformed: true));
      }
      return (text: lines.join('\n'), x: r.totalX, y: r.totalY, w: r.totalWidth, h: r.totalHeight);
    } catch (_) {
      return null;
    } finally {
      calloc.free(imgPtr);
      calloc.free(langPtr);
      calloc.free(result);
    }
  }

  // ─── 符号绑定辅助 ─────────────────────────────────────

  GetInfoV2Dart? _bindGetInfoV2(DynamicLibrary lib) =>
      lib.lookupFunction<GetInfoV2Native, GetInfoV2Dart>('plugin_get_info_v2');
  InitializeV2Dart? _bindInitV2(DynamicLibrary lib) =>
      lib.lookupFunction<InitializeV2Native, InitializeV2Dart>('plugin_initialize_v2');
  ActivateV2Dart? _bindActivateV2(DynamicLibrary lib) =>
      lib.lookupFunction<ActivateV2Native, ActivateV2Dart>('plugin_activate_v2');
  DisposeV2Dart? _bindDisposeV2(DynamicLibrary lib) =>
      lib.lookupFunction<DisposeV2Native, DisposeV2Dart>('plugin_dispose_v2');
  ExecuteCommandV2Dart? _bindExecCmdV2(DynamicLibrary lib) =>
      lib.lookupFunction<ExecuteCommandV2Native, ExecuteCommandV2Dart>('plugin_execute_command_v2');
  InitializeV1Dart? _bindInitV1(DynamicLibrary lib) =>
      lib.lookupFunction<InitializeV1Native, InitializeV1Dart>('plugin_initialize');
  DisposeV1Dart? _bindDisposeV1(DynamicLibrary lib) =>
      lib.lookupFunction<DisposeV1Native, DisposeV1Dart>('plugin_dispose');
  ExecuteActionDart? _bindExecActionV1(DynamicLibrary lib) =>
      lib.lookupFunction<ExecuteActionNative, ExecuteActionDart>('plugin_execute_action');
  TemplateMatchDart? _bindTemplateMatch(DynamicLibrary lib) =>
      lib.lookupFunction<TemplateMatchNative, TemplateMatchDart>('plugin_template_match');
  OcrDart? _bindOcr(DynamicLibrary lib) =>
      lib.lookupFunction<OcrNative, OcrDart>('plugin_ocr');

  T? _lookupOpt<T>(DynamicLibrary lib, String symbol, T? Function(DynamicLibrary) binder) {
    try {
      return binder(lib);
    } catch (_) {
      return null;
    }
  }
}

/// 解析原生库路径
String? resolveNativeLibraryPath(PluginManifest manifest, String pluginDir) {
  final rel = manifest.entry[currentPluginPlatform];
  if (rel == null) return null;
  return '$pluginDir${Platform.pathSeparator}$rel';
}
