
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show Widget;

import '../app_paths.dart';
import 'plugin_api.dart';
import 'plugin_event_bus.dart';
import 'plugin_host.dart';
import 'plugin_integrity.dart';
import 'plugin_manifest.dart';
import 'plugin_storage.dart';
import 'native_plugin_runtime.dart';

enum PluginState {
  discovered,
  installed,
  activating,
  active,
  deactivating,
  error,
}

class PluginDescriptor {
  final PluginManifest manifest;
  final bool isBuiltin;

  PluginState _state = PluginState.discovered;
  PluginState get state => _state;

  String? errorMessage;

  Plugin? dartInstance;
  PluginContext? activeContext;
  CachedPluginStorage? cachedStorage;

  NativePluginInstance? nativeInstance;

  PluginDescriptor({required this.manifest, required this.isBuiltin});

  bool get isActive => _state == PluginState.active;
  bool get isInstalled => _state != PluginState.discovered;
  String get id => manifest.id;

  void _setState(PluginState s) {
    _state = s;
    if (s != PluginState.error) errorMessage = null;
  }
}

class PluginManager extends ChangeNotifier
    implements PluginManagerCommandActivator {
  PluginManager._();
  static final PluginManager instance = PluginManager._();

  final PluginHost _host = PluginHost.instance;
  final Map<String, PluginDescriptor> _plugins = {};
  final Map<String, PluginFactory> _dartFactories = {};
  final Set<String> _installedIds = {};
  final Set<String> _enabledIds = {};
  final Set<String> _knownBuiltinIds = {};

  List<PluginDescriptor> get plugins => _plugins.values.toList();

  List<PluginDescriptor> get installedPlugins =>
      _plugins.values.where((p) => p.isInstalled).toList();

  List<PluginDescriptor> get activePlugins =>
      _plugins.values.where((p) => p.isActive).toList();

  PluginDescriptor? byId(String id) => _plugins[id];

  bool isInstalled(String id) => _installedIds.contains(id);
  bool isEnabled(String id) => _enabledIds.contains(id);

  Future<String> get pluginsDirPath => AppPaths.getPluginsDir();


  void registerDartPlugin(PluginFactory factory) {
    final probe = factory();
    final manifest = probe.manifest;
    final id = manifest.id;
    _dartFactories[id] = factory;
    _plugins[id] = PluginDescriptor(manifest: manifest, isBuiltin: true);
    notifyListeners();
  }


  Future<void> discoverExternalPlugins() async {
    try {
      final pluginsDir = await AppPaths.getPluginsDir();
      final dir = Directory(pluginsDir);
      if (!await dir.exists()) return;
      await for (final entity in dir.list()) {
        if (entity is! Directory) continue;
        final manifestFile =
            File('${entity.path}${Platform.pathSeparator}manifest.json');
        if (!await manifestFile.exists()) continue;
        try {
          final manifest = PluginManifest.fromJsonString(
            await manifestFile.readAsString(),
          );
          if (manifest.id.isEmpty) continue;
          if (_plugins.containsKey(manifest.id)) continue;
          _plugins[manifest.id] = PluginDescriptor(
            manifest: manifest,
            isBuiltin: false,
          );
        } catch (_) {
        }
      }
      notifyListeners();
    } catch (_) {}
  }

  Future<bool> installFromZip(String zipPath,
      {Future<bool> Function(PluginManifest)? beforeRegister}) async {
    final manifest = await _extractZipToPluginsDir(zipPath);
    if (manifest == null) return false;
    return _registerExternal(manifest, beforeRegister: beforeRegister);
  }

  Future<bool> installFromDirectory(String sourceDir,
      {Future<bool> Function(PluginManifest)? beforeRegister}) async {
    try {
      final srcManifest =
          File('$sourceDir${Platform.pathSeparator}manifest.json');
      if (!await srcManifest.exists()) return false;
      final manifest =
          PluginManifest.fromJsonString(await srcManifest.readAsString());
      final pluginsDir = await AppPaths.getPluginsDir();
      final destDir =
          Directory('$pluginsDir${Platform.pathSeparator}${manifest.id}');
      if (await destDir.exists()) await destDir.delete(recursive: true);
      await _copyDirectory(Directory(sourceDir), destDir);
      await PluginIntegrity.instance.dropNativeLibAnchor(manifest.id);
      return _registerExternal(manifest, beforeRegister: beforeRegister);
    } catch (_) {
      return false;
    }
  }

  Future<bool> _registerExternal(PluginManifest manifest,
      {Future<bool> Function(PluginManifest)? beforeRegister}) async {
    if (beforeRegister != null) {
      final proceed = await beforeRegister(manifest);
      if (!proceed) return false;
    }
    _plugins[manifest.id] = PluginDescriptor(manifest: manifest, isBuiltin: false);
    await installPlugin(manifest.id);
    return true;
  }

  Future<PluginManifest?> _extractZipToPluginsDir(String zipPath) async {
    try {
      final tempDir = await AppPaths.getTempDir();
      final extractDir =
          Directory('$tempDir${Platform.pathSeparator}plugin_install_'
              '${DateTime.now().millisecondsSinceEpoch}');
      final bytes = await File(zipPath).readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);
      for (final file in archive) {
        final path = '${extractDir.path}${Platform.pathSeparator}${file.name}';
        if (file.isFile) {
          final f = File(path);
          await f.parent.create(recursive: true);
          await f.writeAsBytes(file.content as List<int>);
        } else {
          await Directory(path).create(recursive: true);
        }
      }
      String root = extractDir.path;
      final items = await extractDir.list().toList();
      if (items.length == 1 && items.first is Directory) root = items.first.path;
      final manifestFile = File('$root${Platform.pathSeparator}manifest.json');
      if (!await manifestFile.exists()) return null;
      final manifest =
          PluginManifest.fromJsonString(await manifestFile.readAsString());
      final pluginsDir = await AppPaths.getPluginsDir();
      final destDir =
          Directory('$pluginsDir${Platform.pathSeparator}${manifest.id}');
      if (await destDir.exists()) await destDir.delete(recursive: true);
      await _copyDirectory(Directory(root), destDir);
      await PluginIntegrity.instance.dropNativeLibAnchor(manifest.id);
      try { await extractDir.delete(recursive: true); } catch (_) {}
      return manifest;
    } catch (_) {
      return null;
    }
  }


  Future<void> installPlugin(String id) async {
    final desc = _plugins[id];
    if (desc == null || desc.isInstalled) return;
    desc._setState(PluginState.installed);
    _installedIds.add(id);
    await saveState();
    notifyListeners();
  }

  Future<void> uninstallPlugin(String id) async {
    final desc = _plugins[id];
    if (desc == null || !desc.isInstalled) return;
    if (desc.isActive) await deactivatePlugin(id);
    _installedIds.remove(id);
    _enabledIds.remove(id);

    if (!desc.isBuiltin) {
      final pluginsDir = await AppPaths.getPluginsDir();
      final dir = Directory('$pluginsDir${Platform.pathSeparator}$id');
      for (int i = 0; i < 3; i++) {
        try {
          if (await dir.exists()) await dir.delete(recursive: true);
          break;
        } catch (_) {
          await Future.delayed(const Duration(milliseconds: 300));
        }
      }
      _plugins.remove(id);
    } else {
      desc._setState(PluginState.discovered);
    }
    await saveState();
    notifyListeners();
  }


  Future<bool> enablePlugin(String id) async {
    final desc = _plugins[id];
    if (desc == null) return false;
    if (!desc.isInstalled) await installPlugin(id);
    _enabledIds.add(id);
    bool ok = true;
    if (desc.manifest.activationEvents.contains('onStartup')) {
      ok = await activatePlugin(id, reason: 'onStartup');
    }
    await saveState();
    notifyListeners();
    return ok;
  }

  Future<void> disablePlugin(String id) async {
    final desc = _plugins[id];
    if (desc == null) return;
    _enabledIds.remove(id);
    if (desc.isActive) await deactivatePlugin(id);
    await saveState();
    notifyListeners();
  }

  Future<void> togglePlugin(String id) async {
    if (_enabledIds.contains(id)) {
      await disablePlugin(id);
    } else {
      await enablePlugin(id);
    }
  }


  Future<bool> activatePlugin(String id, {String reason = 'manual'}) async {
    final desc = _plugins[id];
    if (desc == null || desc.isActive || desc.state == PluginState.activating) {
      return desc?.isActive ?? false;
    }
    if (!desc.manifest.supportsCurrentPlatform) return false;

    desc._setState(PluginState.activating);
    notifyListeners();
    final ok = await _activateCore(desc, reason);
    desc._setState(ok ? PluginState.active : PluginState.error);
    if (!ok && desc.errorMessage == null) {
      desc.errorMessage = '激活失败';
    }
    notifyListeners();
    if (ok) {
      await _host.events.emit(PluginEvents.pluginActivated, {'pluginId': id});
    }
    return ok;
  }

  Future<bool> _activateCore(PluginDescriptor desc, String reason) async {
    try {
      if (desc.manifest.runtime == PluginRuntime.dart) {
        return await _activateDart(desc, reason);
      } else {
        return await _activateNative(desc, reason);
      }
    } catch (e) {
      desc.errorMessage = e.toString();
      return false;
    }
  }

  Future<bool> _activateDart(PluginDescriptor desc, String reason) async {
    final factory = _dartFactories[desc.id];
    if (factory == null) {
      desc.errorMessage = '未注册的 Dart 插件';
      return false;
    }
    final plugin = factory();
    final ctx = _createContext(desc);
    await plugin.onActivate(ctx);
    desc.dartInstance = plugin;
    desc.activeContext = ctx;
    return true;
  }

  Future<bool> _activateNative(PluginDescriptor desc, String reason) async {
    final pluginsDir = await AppPaths.getPluginsDir();
    final pluginDir = '$pluginsDir${Platform.pathSeparator}${desc.id}';
    final libPath = resolveNativeLibraryPath(desc.manifest, pluginDir);
    if (libPath == null || !File(libPath).existsSync()) {
      desc.errorMessage = '未找到当前平台的插件库';
      return false;
    }

    final verdict = await PluginIntegrity.instance.checkNativeLib(desc.id, libPath);
    if (verdict == IntegrityVerdict.changed) {
      desc.errorMessage = '插件库已发生变化（SHA256 不匹配），已拒绝加载；请重新安装该插件';
      return false;
    }

    final instance = NativePluginInstance(
      manifest: desc.manifest,
      libraryPath: libPath,
      pluginDir: pluginDir,
    );
    if (!instance.open()) {
      desc.errorMessage = '动态库加载失败: $libPath';
      return false;
    }

    final storage = PluginStorage.forPlugin(pluginsDir, desc.id);
    await storage.applyDefaults(desc.manifest.contributions.settings);
    final cached = CachedPluginStorage(storage);
    await cached.load();
    desc.cachedStorage = cached;

    final hostTable = NativeHostApiTable(
      pluginId: desc.id,
      manifest: desc.manifest,
      services: _host.services,
      storage: cached,
      onEvent: (event, data) {
        _host.events.emit(event, data != null ? jsonDecode(data) : {});
      },
      onLog: (level, tag, msg) {
        debugPrint('[plugin:${desc.id}] $tag: $msg');
      },
    );

    if (!instance.initialize(hostTable)) {
      desc.errorMessage = '插件初始化失败（plugin_initialize）';
      instance.dispose();
      return false;
    }
    if (!instance.activate(reason)) {
      desc.errorMessage = '插件激活失败（plugin_activate）';
      instance.dispose();
      return false;
    }
    desc.nativeInstance = instance;

    _registerNativeContributions(desc, instance, cached);
    return true;
  }

  void _registerNativeContributions(
    PluginDescriptor desc,
    NativePluginInstance instance,
    CachedPluginStorage storage,
  ) {
    final contribs = desc.manifest.contributions;
    final host = _host;

    for (final cmd in contribs.commands) {
      final commandId = cmd.id.contains('.') ? cmd.id : '${desc.id}.${cmd.id}';
      host.registerCommand(desc.id, CommandRegistration(
        CommandContribution(
          id: commandId,
          title: cmd.title,
          category: cmd.category ?? desc.manifest.category,
        ),
        (params) async {
          final r = instance.executeCommand(commandId, params);
          if (!r.ok) throw Exception('命令 $commandId 失败: ${r.error}');
          return r.result;
        },
        desc.id,
      ));
    }

    for (final page in contribs.pages) {
      final pageId = resolveFullPageId(desc.id, page.id);
      host.registerPage(desc.id, PageRegistration(
        PageContribution(
          id: pageId,
          title: page.title,
          icon: page.icon ?? desc.manifest.icon,
          order: page.order,
          showInNav: page.showInNav,
          description: page.description,
        ),
        (context) => _declarativePageBuilder(desc, storage),
        desc.id,
      ));
    }
  }

  static Widget Function(PluginDescriptor desc, CachedPluginStorage storage)?
      declarativePageFactory;

  Widget _declarativePageBuilder(PluginDescriptor desc, CachedPluginStorage storage) {
    final factory = declarativePageFactory;
    if (factory != null) return factory(desc, storage);
    throw StateError('declarativePageFactory 未注入');
  }

  PluginContext _createContext(PluginDescriptor desc) {
    return PluginContext(
      pluginId: desc.id,
      manifest: desc.manifest,
      services: _host.services,
      events: _host.events,
      onPageRegistered: _host.registerPage,
      onCommandRegistered: _host.registerCommand,
      onInputBackendRegistered: _host.registerInputBackend,
      onVisionProviderRegistered: _host.registerVisionProvider,
    );
  }

  Future<void> deactivatePlugin(String id) async {
    final desc = _plugins[id];
    if (desc == null || !desc.isActive) return;
    desc._setState(PluginState.deactivating);
    notifyListeners();

    try {
      await desc.dartInstance?.onDeactivate();
    } catch (_) {}
    desc.activeContext?.dispose();
    desc.nativeInstance?.dispose();
    await desc.cachedStorage?.dispose();

    desc.dartInstance = null;
    desc.activeContext = null;
    desc.nativeInstance = null;
    desc.cachedStorage = null;

    _host.removeContributions(id);
    _host.events.unsubscribeAll(id);
    desc._setState(PluginState.installed);
    notifyListeners();
    await _host.events.emit(PluginEvents.pluginDeactivated, {'pluginId': id});
  }


  @override
  Future<bool> activateForCommand(String commandId) async {
    for (final desc in _plugins.values) {
      if (desc.isActive || !_enabledIds.contains(desc.id)) continue;
      final commands = desc.manifest.contributions.commands;
      final declared = commands.any((c) =>
          c.id == commandId ||
          (c.id.contains('.') ? c.id : '${desc.id}.${c.id}') == commandId);
      final byEvent = desc.manifest.activationEvents
          .any((e) => e == 'onCommand:$commandId');
      if (declared || byEvent) {
        return activatePlugin(desc.id, reason: 'onCommand:$commandId');
      }
    }
    return false;
  }

  Future<bool> ensurePageActivated(String pageId) async {
    for (final desc in _plugins.values) {
      if (desc.isActive || !_enabledIds.contains(desc.id)) continue;
      final pages = desc.manifest.contributions.pages;
      final declared = pages.any((p) =>
          resolveFullPageId(desc.id, p.id) == pageId);
      final byEvent = desc.manifest.activationEvents
          .any((e) => e == 'onPage:$pageId');
      if (declared || byEvent) {
        return activatePlugin(desc.id, reason: 'onPage:$pageId');
      }
    }
    return false;
  }


  Future<void> initialize() async {
    await loadState();
    await discoverExternalPlugins();
    await _enableNewBuiltins();
    _host.pluginManagerActivator = this;

    for (final id in _enabledIds.toList()) {
      final desc = _plugins[id];
      if (desc == null) continue;
      if (desc.manifest.activationEvents.contains('onStartup')) {
        await activatePlugin(id, reason: 'onStartup');
      }
    }
    notifyListeners();
  }

  Future<void> _enableNewBuiltins() async {
    var changed = false;
    for (final desc in _plugins.values) {
      if (!desc.isBuiltin) continue;
      if (_knownBuiltinIds.contains(desc.id)) continue;
      _knownBuiltinIds.add(desc.id);
      changed = true;
      if (!_installedIds.contains(desc.id)) {
        _installedIds.add(desc.id);
        desc._setState(PluginState.installed);
      }
      _enabledIds.add(desc.id);
    }
    if (changed) await saveState();
  }

  Future<void> shutdown() async {
    await _host.events.emit(PluginEvents.appQuitting);
    for (final desc in activePlugins.toList()) {
      await deactivatePlugin(desc.id);
    }
  }

  Future<void> loadState() async {
    try {
      final dir = await AppPaths.getDataDir();
      final file =
          File('$dir${Platform.pathSeparator}plugin_state.json');
      if (await file.exists()) {
        final json = jsonDecode(await file.readAsString());
        _installedIds.clear();
        _enabledIds.clear();
        _knownBuiltinIds.clear();
        _installedIds.addAll((json['installed'] as List?)?.cast<String>() ?? []);
        _enabledIds.addAll((json['enabled'] as List?)?.cast<String>() ?? []);
        _knownBuiltinIds.addAll((json['known'] as List?)?.cast<String>() ?? []);
      }
    } catch (_) {}

    for (final desc in _plugins.values) {
      if (_installedIds.contains(desc.id)) {
        desc._setState(PluginState.installed);
      }
    }
  }

  Future<void> saveState() async {
    try {
      final dir = await AppPaths.getDataDir();
      final file =
          File('$dir${Platform.pathSeparator}plugin_state.json');
      await file.writeAsString(jsonEncode({
        'version': 3,
        'installed': _installedIds.toList(),
        'enabled': _enabledIds.toList(),
        'known': _knownBuiltinIds.toList(),
      }));
    } catch (_) {}
  }

  Future<void> openPluginsDir() async {
    final path = await AppPaths.getPluginsDir();
    try {
      if (Platform.isWindows) {
        await Process.run('explorer', [path]);
      } else if (Platform.isLinux) {
        await Process.run('xdg-open', [path]);
      } else if (Platform.isMacOS) {
        await Process.run('open', [path]);
      }
    } catch (_) {}
  }

  Future<void> _copyDirectory(Directory source, Directory destination) async {
    if (!await destination.exists()) await destination.create(recursive: true);
    await for (final entity in source.list()) {
      final newPath =
          '${destination.path}${Platform.pathSeparator}${entity.path.split(Platform.pathSeparator).last}';
      if (entity is Directory) {
        await _copyDirectory(entity, Directory(newPath));
      } else if (entity is File) {
        await entity.copy(newPath);
      }
    }
  }
}
