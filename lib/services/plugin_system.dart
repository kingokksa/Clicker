/// Clicker plugin system — supports both built-in Dart plugins and
/// external native plugins (.dll/.so/.dylib) loaded via FFI.
/// Built-in Dart plugins use lazy initialization: code is compiled in
/// but resources (pages, services) are only created when enabled and
/// released when disabled.
library;

import 'package:fluent_ui/fluent_ui.dart';
import 'native_plugin_loader.dart';

enum PluginCategory {
  core('核心', 'core'),
  click('点击增强', 'click'),
  vision('图像识别', 'vision'),
  automation('自动化', 'automation'),
  ui('界面', 'ui'),
  extension('扩展', 'extension');

  final String label;
  final String id;
  const PluginCategory(this.label, this.id);

  static PluginCategory fromString(String s) {
    return PluginCategory.values.firstWhere(
      (c) => c.id == s || c.name == s,
      orElse: () => PluginCategory.extension,
    );
  }
}

enum PluginSource {
  builtin,
  local,
  store,
}

class ClickerPluginManifest {
  final String id;
  final String name;
  final String version;
  final String author;
  final String description;
  final IconData icon;
  final PluginCategory category;
  final PluginSource source;
  final List<String> platforms;
  final bool supportsCurrentPlatform;
  final bool showInNav;

  const ClickerPluginManifest({
    required this.id,
    required this.name,
    required this.version,
    this.author = '',
    this.description = '',
    required this.icon,
    this.category = PluginCategory.extension,
    this.source = PluginSource.builtin,
    this.platforms = const [],
    this.supportsCurrentPlatform = true,
    this.showInNav = true,
  });
}

abstract class ClickerPlugin {
  ClickerPluginManifest get manifest;

  bool _enabled = false;
  bool get enabled => _enabled;
  set enabled(bool v) {
    _enabled = v;
    onStateChanged?.call();
  }

  bool _installed = false;
  bool get installed => _installed;
  set installed(bool v) {
    _installed = v;
    onStateChanged?.call();
  }

  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  VoidCallback? onStateChanged;

  Widget? _cachedPage;

  Future<void> initialize() async {
    if (_isInitialized) return;
    _isInitialized = true;
    await onInitialize();
  }

  Future<void> dispose() async {
    if (!_isInitialized) return;
    _isInitialized = false;
    _cachedPage = null;
    await onDispose();
  }

  Future<void> onInitialize();
  Future<void> onDispose();
  Future<void> onUninstall() async {}

  Widget buildPage(BuildContext context) {
    _cachedPage ??= onCreatePage(context);
    return _cachedPage!;
  }

  Widget onCreatePage(BuildContext context);
  Widget? buildSettings(BuildContext context) => null;
}

class NativeClickerPlugin extends ClickerPlugin {
  final LoadedNativePlugin _nativePlugin;

  NativeClickerPlugin(this._nativePlugin);

  @override
  late final ClickerPluginManifest manifest;

  void initManifest() {
    final nm = _nativePlugin.manifest;
    final cat = PluginCategory.fromString(nm.category);
    final currentPlatform = LoadedNativePlugin.currentPlatform;
    manifest = ClickerPluginManifest(
      id: nm.id,
      name: nm.name,
      version: nm.version,
      author: nm.author,
      description: nm.description,
      icon: _categoryIcon(cat),
      category: cat,
      source: PluginSource.local,
      platforms: nm.platforms,
      supportsCurrentPlatform: nm.platforms.contains(currentPlatform),
    );
  }

  @override
  Future<void> onInitialize() async {
    if (!_nativePlugin.isLoaded) {
      _nativePlugin.load();
    }
    _nativePlugin.initialize();
  }

  @override
  Future<void> onDispose() async {
    _nativePlugin.unload();
  }

  @override
  Widget onCreatePage(BuildContext context) {
    return _NativePluginPage(plugin: this);
  }

  LoadedNativePlugin get native => _nativePlugin;

  static IconData _categoryIcon(PluginCategory cat) {
    switch (cat) {
      case PluginCategory.core: return FluentIcons.puzzle;
      case PluginCategory.click: return FluentIcons.touch;
      case PluginCategory.vision: return FluentIcons.image_pixel;
      case PluginCategory.automation: return FluentIcons.process_meta_task;
      case PluginCategory.ui: return FluentIcons.color;
      case PluginCategory.extension: return FluentIcons.puzzle;
    }
  }
}

class _NativePluginPage extends StatelessWidget {
  final NativeClickerPlugin plugin;
  const _NativePluginPage({required this.plugin});

  @override
  Widget build(BuildContext context) {
    final isDark = FluentTheme.of(context).brightness == Brightness.dark;
    final native = plugin.native;
    return ScaffoldPage.scrollable(
      padding: const EdgeInsets.all(20),
      children: [
        Row(children: [
          Icon(plugin.manifest.icon, size: 20, color: FluentTheme.of(context).accentColor),
          const SizedBox(width: 10),
          Text(plugin.manifest.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 20),
        _infoRow('版本', plugin.manifest.version, isDark),
        _infoRow('作者', plugin.manifest.author, isDark),
        _infoRow('平台', plugin.manifest.platforms.join(', '), isDark),
        _infoRow('模板匹配', native.supportsTemplateMatch ? '支持' : '不支持', isDark),
        _infoRow('OCR', native.supportsOcr ? '支持' : '不支持', isDark),
        _infoRow('自定义动作', native.supportsCustomActions ? '支持' : '不支持', isDark),
        if (plugin.manifest.description.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(plugin.manifest.description, style: TextStyle(fontSize: 13, color: isDark ? const Color(0xFF9090B0) : const Color(0xFF8A8A9A))),
        ],
      ],
    );
  }

  Widget _infoRow(String label, String value, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        SizedBox(width: 80, child: Text(label, style: TextStyle(fontSize: 13, color: isDark ? const Color(0xFF9090B0) : const Color(0xFF8A8A9A)))),
        Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}
