/// Native plugin loader — loads external .dll/.so/.dylib plugins via dart:ffi.
/// Each plugin implements the C API defined in sdk/clicker_plugin.h.
library;

import 'dart:ffi';
import 'dart:io';
import 'dart:convert';
import 'package:ffi/ffi.dart';
import 'package:path_provider/path_provider.dart';

// ─── FFI Type Definitions ──────────────────────────────────

/// PluginInfo struct in C
final class PluginInfoC extends Struct {
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

/// PluginMatchResult struct in C
final class PluginMatchResultC extends Struct {
  @Int32()
  external int x;
  @Int32()
  external int y;
  @Int32()
  external int width;
  @Int32()
  external int height;
  @Double()
  external double score;
}

/// PluginOcrLine struct in C
/// C: { char text[256]; int32_t x, y, width, height; }
final class PluginOcrLineC extends Struct {
  @Array(256)
  external Array<Uint8> text;
  @Int32()
  external int x;
  @Int32()
  external int y;
  @Int32()
  external int width;
  @Int32()
  external int height;
}

/// PluginOcrResult struct in C
/// C: { PluginOcrLine lines[64]; int32_t line_count, total_x, total_y, total_width, total_height; }
final class PluginOcrResultC extends Struct {
  @Array(64)
  external Array<PluginOcrLineC> lines;
  @Int32()
  external int lineCount;
  @Int32()
  external int totalX;
  @Int32()
  external int totalY;
  @Int32()
  external int totalWidth;
  @Int32()
  external int totalHeight;
}

// ─── Function Typedefs ─────────────────────────────────────

typedef GetInfoNative     = Pointer<PluginInfoC> Function();
typedef GetInfoDart       = Pointer<PluginInfoC> Function();

typedef InitializeNative  = Int32 Function();
typedef InitializeDart    = int Function();

typedef DisposeNative     = Void Function();
typedef DisposeDart       = void Function();

typedef TemplateMatchNative = Int32 Function(
  Pointer<Uint8> regionData, Int32 regionW, Int32 regionH,
  Pointer<Uint8> tplData, Int32 tplW, Int32 tplH,
  Double threshold,
  Pointer<PluginMatchResultC> outResults, Int32 maxResults,
);
typedef TemplateMatchDart = int Function(
  Pointer<Uint8> regionData, int regionW, int regionH,
  Pointer<Uint8> tplData, int tplW, int tplH,
  double threshold,
  Pointer<PluginMatchResultC> outResults, int maxResults,
);

typedef OcrNative = Int32 Function(
  Pointer<Uint8> imageData, Int32 w, Int32 h,
  Pointer<Utf8> language,
  Pointer<PluginOcrResultC> outResult,
);
typedef OcrDart = int Function(
  Pointer<Uint8> imageData, int w, int h,
  Pointer<Utf8> language,
  Pointer<PluginOcrResultC> outResult,
);

typedef ExecuteActionNative = Int32 Function(
  Pointer<Utf8> actionId,
  Pointer<Utf8> params,
  Pointer<Utf8> outBuf, Int32 outSize,
);
typedef ExecuteActionDart = int Function(
  Pointer<Utf8> actionId,
  Pointer<Utf8> params,
  Pointer<Utf8> outBuf, int outSize,
);

// ─── Plugin Manifest ───────────────────────────────────────

class PluginManifest {
  final String id;
  final String name;
  final String version;
  final String author;
  final String description;
  final String category;
  final List<String> platforms;
  final Map<String, String> entryPoints; // platform -> relative path
  final String? iconPath;
  final int minAppVersion;

  const PluginManifest({
    required this.id,
    required this.name,
    required this.version,
    this.author = '',
    this.description = '',
    this.category = 'extension',
    this.platforms = const [],
    this.entryPoints = const {},
    this.iconPath,
    this.minAppVersion = 1,
  });

  factory PluginManifest.fromJson(Map<String, dynamic> json) => PluginManifest(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? '',
    version: json['version'] as String? ?? '1.0.0',
    author: json['author'] as String? ?? '',
    description: json['description'] as String? ?? '',
    category: json['category'] as String? ?? 'extension',
    platforms: (json['platforms'] as List?)?.cast<String>() ?? [],
    entryPoints: (json['entry'] as Map<String, dynamic>?)?.map(
      (k, v) => MapEntry(k, v.toString())) ?? {},
    iconPath: json['icon'] as String?,
    minAppVersion: json['minAppVersion'] as int? ?? 1,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'version': version,
    'author': author,
    'description': description,
    'category': category,
    'platforms': platforms,
    'entry': entryPoints,
    if (iconPath != null) 'icon': iconPath,
    'minAppVersion': minAppVersion,
  };
}

// ─── Loaded Native Plugin ──────────────────────────────────

class LoadedNativePlugin {
  final PluginManifest manifest;
  final String pluginDir;
  DynamicLibrary? _library;

  // Function pointers (null if not available)
  GetInfoDart?       _getInfo;
  InitializeDart?    _initialize;
  DisposeDart?       _dispose;
  TemplateMatchDart? _templateMatch;
  OcrDart?           _ocr;
  ExecuteActionDart? _executeAction;

  bool _isLoaded = false;
  bool get isLoaded => _isLoaded;

  LoadedNativePlugin({required this.manifest, required this.pluginDir});

  /// Load the native library for the current platform
  bool load() {
    if (_isLoaded) return true;

    final libPath = _getLibraryPath();
    if (libPath == null) return false;

    try {
      _library = DynamicLibrary.open(libPath);
      _bindFunctions();
      _isLoaded = true;
      return true;
    } catch (e) {
      _library = null;
      return false;
    }
  }

  /// Unload the native library
  void unload() {
    if (!_isLoaded) return;
    try {
      _dispose?.call();
    } catch (_) {}
    // DynamicLibrary doesn't have close(), but we can release references
    _library = null;
    _getInfo = null;
    _initialize = null;
    _dispose = null;
    _templateMatch = null;
    _ocr = null;
    _executeAction = null;
    _isLoaded = false;
  }

  /// Initialize the plugin
  bool initialize() {
    if (!_isLoaded || _initialize == null) return false;
    try {
      return _initialize!() == 0;
    } catch (_) {
      return false;
    }
  }

  /// Get plugin info from native library
  Pointer<PluginInfoC>? getInfo() {
    if (!_isLoaded || _getInfo == null) return null;
    try {
      return _getInfo!();
    } catch (_) {
      return null;
    }
  }

  /// Check if plugin supports template matching
  bool get supportsTemplateMatch => _templateMatch != null;

  /// Check if plugin supports OCR
  bool get supportsOcr => _ocr != null;

  /// Check if plugin supports custom actions
  bool get supportsCustomActions => _executeAction != null;

  void _bindFunctions() {
    final lib = _library!;
    try { _getInfo = lib.lookupFunction<GetInfoNative, GetInfoDart>('plugin_get_info'); } catch (_) {}
    try { _initialize = lib.lookupFunction<InitializeNative, InitializeDart>('plugin_initialize'); } catch (_) {}
    try { _dispose = lib.lookupFunction<DisposeNative, DisposeDart>('plugin_dispose'); } catch (_) {}
    try { _templateMatch = lib.lookupFunction<TemplateMatchNative, TemplateMatchDart>('plugin_template_match'); } catch (_) {}
    try { _ocr = lib.lookupFunction<OcrNative, OcrDart>('plugin_ocr'); } catch (_) {}
    try { _executeAction = lib.lookupFunction<ExecuteActionNative, ExecuteActionDart>('plugin_execute_action'); } catch (_) {}
  }

  String? _getLibraryPath() {
    final platform = _currentPlatform();
    if (platform == null) return null;
    final relativePath = manifest.entryPoints[platform];
    if (relativePath == null) return null;
    return '$pluginDir${Platform.pathSeparator}$relativePath';
  }

  static String? _currentPlatform() {
    if (Platform.isWindows) return 'windows';
    if (Platform.isLinux) return 'linux';
    if (Platform.isMacOS) return 'darwin';
    return null;
  }

  static String get currentPlatform => _currentPlatform() ?? 'unknown';
}

// ─── Plugin Directory Manager ──────────────────────────────

class PluginDirManager {
  static Future<Directory> getPluginsDir() async {
    final appDir = await getApplicationSupportDirectory();
    final dir = Directory('${appDir.path}${Platform.pathSeparator}plugins');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Discover all installed plugin directories
  static Future<List<PluginManifest>> discoverPlugins() async {
    final pluginsDir = await getPluginsDir();
    final manifests = <PluginManifest>[];

    await for (final entity in pluginsDir.list()) {
      if (entity is Directory) {
        final manifestFile = File('${entity.path}${Platform.pathSeparator}manifest.json');
        if (await manifestFile.exists()) {
          try {
            final json = jsonDecode(await manifestFile.readAsString()) as Map<String, dynamic>;
            manifests.add(PluginManifest.fromJson(json));
          } catch (_) {}
        }
      }
    }
    return manifests;
  }

  /// Install a plugin from a zip file
  static Future<PluginManifest?> installFromZip(String zipPath) async {
    final pluginsDir = await getPluginsDir();
    // Extract zip to plugins directory
    final result = await Process.run('powershell', [
      '-NoProfile', '-Command',
      'Expand-Archive -Path "\'$zipPath\'" -DestinationPath \'${pluginsDir.path}\' -Force',
    ]);
    if (result.exitCode != 0) return null;

    // Find the manifest in the extracted directory
    final manifests = await discoverPlugins();
    return manifests.isNotEmpty ? manifests.last : null;
  }

  /// Install a plugin from a directory
  static Future<PluginManifest?> installFromDirectory(String sourceDir) async {
    final pluginsDir = await getPluginsDir();
    final sourceManifest = File('$sourceDir${Platform.pathSeparator}manifest.json');
    if (!await sourceManifest.exists()) return null;

    try {
      final json = jsonDecode(await sourceManifest.readAsString()) as Map<String, dynamic>;
      final manifest = PluginManifest.fromJson(json);

      // Copy directory to plugins folder
      final destDir = Directory('${pluginsDir.path}${Platform.pathSeparator}${manifest.id}');
      if (await destDir.exists()) await destDir.delete(recursive: true);

      await Process.run('powershell', [
        '-NoProfile', '-Command',
        'Copy-Item -Path \'$sourceDir\' -Destination \'${destDir.parent.path}\' -Recurse -Force',
      ]);

      return manifest;
    } catch (_) {
      return null;
    }
  }

  /// Uninstall a plugin by id
  static Future<bool> uninstall(String pluginId) async {
    final pluginsDir = await getPluginsDir();
    final dir = Directory('${pluginsDir.path}${Platform.pathSeparator}$pluginId');
    if (await dir.exists()) {
      await dir.delete(recursive: true);
      return true;
    }
    return false;
  }

  /// Get the plugin directory for a given id
  static Future<String?> getPluginDir(String pluginId) async {
    final pluginsDir = await getPluginsDir();
    final dir = Directory('${pluginsDir.path}${Platform.pathSeparator}$pluginId');
    return await dir.exists() ? dir.path : null;
  }
}
