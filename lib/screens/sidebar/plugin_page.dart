/// Plugin center — two tabs: "已安装" and "商店".
/// The store fetches a remote index from GitHub; Dart plugins are
/// compiled into the app but start disabled until "installed" from the store.
library;

import 'dart:convert';
import 'dart:io';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../../services/app_state.dart';
import '../../services/plugin_system.dart';
import '../../services/plugin_registry.dart';
import '../../services/native_plugin_loader.dart';
import '../../services/plugin_store.dart';

class PluginPage extends StatefulWidget {
  const PluginPage({super.key});

  @override
  State<PluginPage> createState() => _PluginPageState();
}

class _PluginPageState extends State<PluginPage> {
  bool _isInstalling = false;
  int _tabIndex = 0;

  @override
  void initState() {
    super.initState();
    // Auto-fetch store index on first build
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await PluginStore.instance.fetchIndex();
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final isDark = FluentTheme.of(context).brightness == Brightness.dark;
    final registry = PluginRegistry.instance;
    final allPlugins = registry.plugins;
    final config = state.clickerConfig;

    return ScaffoldPage.scrollable(
      padding: const EdgeInsets.all(20),
      children: [
        // Header
        Row(children: [
          Icon(FluentIcons.puzzle, size: 20, color: state.accentColor),
          const SizedBox(width: 10),
          const Text('插件中心', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          const Spacer(),
          Text('${registry.enabledPlugins.length} / ${allPlugins.length} 已启用',
            style: TextStyle(fontSize: 12, color: isDark ? const Color(0xFF9090B0) : const Color(0xFF8A8A9A))),
        ]),
        const SizedBox(height: 16),

        // Action buttons row
        Row(children: [
          _actionButton(
            icon: FluentIcons.open_folder_horizontal,
            label: '安装插件',
            isDark: isDark,
            accent: state.accentColor,
            onPressed: _installPlugin,
          ),
          const SizedBox(width: 8),
          _actionButton(
            icon: FluentIcons.folder_open,
            label: '插件目录',
            isDark: isDark,
            accent: state.accentColor,
            onPressed: () => PluginRegistry.instance.openPluginsDir(),
          ),
          const SizedBox(width: 8),
          _actionButton(
            icon: FluentIcons.c_plus_plus,
            label: '新建插件',
            isDark: isDark,
            accent: state.accentColor,
            onPressed: () => _showCreatePluginDialog(context),
          ),
          const SizedBox(width: 8),
          _actionButton(
            icon: FluentIcons.refresh,
            label: '刷新',
            isDark: isDark,
            accent: state.accentColor,
            onPressed: () async {
              await registry.discoverExternalPlugins();
              await PluginStore.instance.fetchIndex();
              setState(() {});
            },
          ),
        ]),
        const SizedBox(height: 20),

        // Tab switcher
        Row(children: [
          _tabButton('已安装', FluentIcons.download, 0, isDark, state.accentColor),
          const SizedBox(width: 4),
          _tabButton('商店', FluentIcons.shop, 1, isDark, state.accentColor),
        ]),
        const SizedBox(height: 16),

        // Tab content
        if (_tabIndex == 0) ..._buildInstalledTab(allPlugins, config, isDark, state),
        if (_tabIndex == 1) ..._buildStoreTab(isDark, state),
      ],
    );
  }

  // ──── Installed Tab ────

  List<Widget> _buildInstalledTab(
    List<ClickerPlugin> allPlugins, dynamic config, bool isDark, AppState state,
  ) {
    return [
      // Installed plugins grouped by category
      ..._buildCategoryGroups(
        allPlugins.where((p) => p.installed).toList(), isDark),

      if (allPlugins.where((p) => p.installed).isEmpty)
        Center(child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 40),
          child: Column(children: [
            Icon(FluentIcons.puzzle, size: 48, color: isDark ? const Color(0xFF404060) : const Color(0xFFC0C0D0)),
            const SizedBox(height: 12),
            Text('还没有安装插件', style: TextStyle(fontSize: 14, color: isDark ? const Color(0xFF9090B0) : const Color(0xFF8A8A9A))),
            const SizedBox(height: 6),
            Text('前往「商店」标签页安装官方插件', style: TextStyle(fontSize: 12, color: isDark ? const Color(0xFF707090) : const Color(0xFFA0A0B0))),
          ]),
        )),
    ];
  }

  // ──── Store Tab ────

  List<Widget> _buildStoreTab(bool isDark, AppState state) {
    final store = PluginStore.instance;
    final accent = FluentTheme.of(context).accentColor;

    if (store.isLoading) {
      return [
        Center(child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 40),
          child: Column(children: [
            const ProgressRing(),
            const SizedBox(height: 12),
            Text('正在获取插件列表...', style: TextStyle(fontSize: 13, color: isDark ? const Color(0xFF9090B0) : const Color(0xFF8A8A9A))),
          ]),
        )),
      ];
    }

    if (store.error != null && store.plugins.isEmpty) {
      return [
        Center(child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 40),
          child: Column(children: [
            Icon(FluentIcons.warning, size: 48, color: Colors.orange),
            const SizedBox(height: 12),
            Text('无法连接到插件商店', style: TextStyle(fontSize: 14, color: isDark ? const Color(0xFF9090B0) : const Color(0xFF8A8A9A))),
            const SizedBox(height: 6),
            Text(store.error!, style: TextStyle(fontSize: 11, color: isDark ? const Color(0xFF707090) : const Color(0xFFA0A0B0))),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => store.fetchIndex(),
              child: const Text('重试'),
            ),
          ]),
        )),
      ];
    }

    if (store.plugins.isEmpty) {
      return [
        Center(child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 40),
          child: Text('暂无可用插件', style: TextStyle(fontSize: 14, color: isDark ? const Color(0xFF9090B0) : const Color(0xFF8A8A9A))),
        )),
      ];
    }

    return [
      // Store header
      Row(children: [
        Icon(FluentIcons.shop, size: 16, color: accent),
        const SizedBox(width: 8),
        Text('官方插件', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700,
          color: isDark ? const Color(0xFFC0C0E8) : const Color(0xFF5A5A80))),
        const Spacer(),
        Text('从远程仓库获取 · ${store.plugins.length} 个插件',
          style: TextStyle(fontSize: 11, color: isDark ? const Color(0xFF9090B0) : const Color(0xFF8A8A9A))),
      ]),
      const SizedBox(height: 12),

      // Plugin list
      ...store.plugins.map((entry) => _buildStoreCard(entry, isDark, accent)),
    ];
  }

  Widget _buildStoreCard(StorePluginEntry entry, bool isDark, Color accent) {
    final currentPlatform = LoadedNativePlugin.currentPlatform;
    final isSupported = entry.supportsCurrentPlatform;
    final isInstalled = entry.isInstalled;
    final isEnabled = entry.isEnabled;

    final cardBg = isDark ? const Color(0xFF252540).withValues(alpha: 0.5) : const Color(0xFFF0F0FA).withValues(alpha: 0.5);
    final disabledColor = isDark ? const Color(0xFF606080) : const Color(0xFFB0B0C0);
    final activeColor = isSupported ? accent : disabledColor;

    // Icon mapping
    final iconMap = {
      'keyboard_classic': FluentIcons.keyboard_classic,
      'image_pixel': FluentIcons.image_pixel,
      'record2': FluentIcons.record2,
      'color': FluentIcons.color,
      'remote': FluentIcons.remote,
      'machine_learning': FluentIcons.machine_learning,
    };
    final icon = iconMap[entry.icon] ?? FluentIcons.puzzle;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: isDark ? const Color(0xFF303050) : const Color(0xFFD0D0E0)),
        ),
        child: Row(children: [
          // Icon
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: activeColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(icon, size: 16, color: activeColor),
          ),
          const SizedBox(width: 12),
          // Info
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(entry.name, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13,
                color: isSupported ? null : disabledColor)),
              const SizedBox(width: 6),
              // Type badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: entry.type == 'dart'
                    ? const Color(0xFF00E676).withValues(alpha: 0.12)
                    : const Color(0xFF42A5F5).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(entry.type == 'dart' ? 'Dart' : '原生',
                  style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600,
                    color: entry.type == 'dart' ? const Color(0xFF00E676) : const Color(0xFF42A5F5))),
              ),
              const SizedBox(width: 4),
              // Platform badges
              ...entry.platforms.map((p) => Padding(
                padding: const EdgeInsets.only(right: 3),
                child: _platformBadge(p, p == currentPlatform, isDark),
              )),
              if (!isSupported) ...[
                const SizedBox(width: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text('不支持', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: Colors.red)),
                ),
              ],
            ]),
            const SizedBox(height: 2),
            Text(entry.description,
              style: TextStyle(fontSize: 11, color: isDark ? const Color(0xFF9090B0) : const Color(0xFF8A8A9A))),
            const SizedBox(height: 1),
            Text('v${entry.version}${entry.author.isNotEmpty ? " · ${entry.author}" : ""}',
              style: TextStyle(fontSize: 10, color: isDark ? const Color(0xFF707090) : const Color(0xFFA0A0B0))),
          ])),
          // Action button
          if (!isSupported)
            const Button(
              onPressed: null,
              style: ButtonStyle(
                padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 12, vertical: 6)),
              ),
              child: Text('不兼容', style: TextStyle(fontSize: 12)),
            )
          else if (isEnabled)
            Button(
              onPressed: () async {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => ContentDialog(
                    title: const Text('确认卸载'),
                    content: Text('确定要卸载「${entry.name}」吗？相关文件将被删除。'),
                    actions: [
                      Button(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
                      FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('卸载')),
                    ],
                  ),
                );
                if (confirmed == true) {
                  await PluginStore.instance.uninstallPlugin(entry);
                  setState(() {});
                }
              },
              style: const ButtonStyle(
                padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 12, vertical: 6)),
              ),
              child: const Text('卸载', style: TextStyle(fontSize: 12)),
            )
          else if (isInstalled)
            FilledButton(
              onPressed: () async {
                final registry = PluginRegistry.instance;
                await registry.enablePlugin(entry.dartPluginId ?? entry.id);
                setState(() {});
              },
              style: ButtonStyle(
                backgroundColor: WidgetStatePropertyAll(accent.withValues(alpha: 0.15)),
                padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 12, vertical: 6)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(FluentIcons.play, size: 12, color: accent),
                const SizedBox(width: 4),
                Text('启用', style: TextStyle(color: accent, fontSize: 12)),
              ]),
            )
          else
            FilledButton(
              onPressed: _isInstalling ? null : () async {
                setState(() => _isInstalling = true);
                final success = await PluginStore.instance.installPlugin(entry);
                if (mounted) {
                  setState(() => _isInstalling = false);
                  if (!success) {
                    await _showInstallResult(false);
                  }
                }
              },
              style: ButtonStyle(
                backgroundColor: WidgetStatePropertyAll(accent.withValues(alpha: 0.15)),
                padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 12, vertical: 6)),
              ),
              child: _isInstalling
                ? const SizedBox(width: 14, height: 14, child: ProgressRing(strokeWidth: 2))
                : Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(FluentIcons.download, size: 12, color: accent),
                    const SizedBox(width: 4),
                    Text('安装', style: TextStyle(color: accent, fontSize: 12)),
                  ]),
            ),
        ]),
      ),
    );
  }

  // ──── Shared helpers ────

  List<Widget> _buildCategoryGroups(List<ClickerPlugin> plugins, bool isDark, {String? groupTitle}) {
    if (plugins.isEmpty) return [];
    const categories = PluginCategory.values;
    return categories.expand((cat) {
      final catPlugins = plugins.where((p) => p.manifest.category == cat).toList();
      if (catPlugins.isEmpty) return <Widget>[];
      return [
        _buildGroup(groupTitle != null ? '$groupTitle · ${cat.label}' : cat.label,
          isDark, catPlugins.map((p) => _buildPluginCard(p, isDark)).toList()),
      ];
    }).toList();
  }

  Widget _tabButton(String label, IconData icon, int index, bool isDark, Color accent) {
    final isActive = _tabIndex == index;
    return GestureDetector(
      onTap: () => setState(() => _tabIndex = index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? accent.withValues(alpha: 0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: isActive ? Border.all(color: accent.withValues(alpha: 0.3)) : null,
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14, color: isActive ? accent : (isDark ? const Color(0xFF9090B0) : const Color(0xFF8A8A9A))),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(
            fontSize: 13, fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
            color: isActive ? accent : (isDark ? const Color(0xFF9090B0) : const Color(0xFF8A8A9A)),
          )),
        ]),
      ),
    );
  }

  Widget _actionButton({
    required IconData icon,
    required String label,
    required bool isDark,
    required Color accent,
    required VoidCallback onPressed,
  }) {
    return Button(
      onPressed: _isInstalling ? null : onPressed,
      style: ButtonStyle(
        padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
        backgroundColor: WidgetStatePropertyAll(accent.withValues(alpha: 0.08)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 12, color: accent),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(fontSize: 12, color: accent, fontWeight: FontWeight.w600)),
      ]),
    );
  }

  Future<void> _installPlugin() async {
    setState(() => _isInstalling = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['zip'],
        dialogTitle: '选择插件包 (.zip)',
      );
      if (result == null || result.files.isEmpty) return;

      final filePath = result.files.single.path;
      if (filePath == null) return;

      final success = await PluginRegistry.instance.installFromZip(filePath);
      if (mounted) {
        await _showInstallResult(success);
      }
    } catch (e) {
      if (mounted) await _showInstallResult(false, error: e.toString());
    } finally {
      if (mounted) setState(() => _isInstalling = false);
    }
  }

  Future<void> _showInstallResult(bool success, {String? error}) async {
    showDialog(
      context: context,
      builder: (ctx) => ContentDialog(
        title: Text(success ? '安装成功' : '安装失败'),
        content: Text(success ? '插件已安装并启用，可在导航栏中找到。'
          : '插件安装失败${error != null ? "：$error" : ""}'),
        actions: [Button(onPressed: () => Navigator.pop(ctx), child: const Text('确定'))],
      ),
    );
  }

  void _showCreatePluginDialog(BuildContext context) {
    final isDark = FluentTheme.of(context).brightness == Brightness.dark;
    final idCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    final authorCtrl = TextEditingController();
    String selectedCategory = 'extension';

    showDialog(
      context: context,
      builder: (ctx) => ContentDialog(
        title: const Text('新建插件项目'),
        constraints: const BoxConstraints(maxWidth: 460),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          _dialogField('插件ID', idCtrl, 'com.example.my_plugin', isDark),
          const SizedBox(height: 10),
          _dialogField('插件名称', nameCtrl, '我的插件', isDark),
          const SizedBox(height: 10),
          _dialogField('作者', authorCtrl, '', isDark),
          const SizedBox(height: 10),
          Row(children: [
            Text('分类', style: TextStyle(fontSize: 13, color: isDark ? const Color(0xFF9090B0) : const Color(0xFF8A8A9A))),
            const SizedBox(width: 12),
            DropDownButton(
              title: Text(PluginCategory.fromString(selectedCategory).label),
              items: PluginCategory.values.map((cat) => MenuFlyoutItem(
                text: Text(cat.label),
                onPressed: () => selectedCategory = cat.id,
              )).toList(),
            ),
          ]),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1A1A30) : const Color(0xFFF5F5FF),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('将生成以下文件结构：', style: TextStyle(fontSize: 11, color: isDark ? const Color(0xFF9090B0) : const Color(0xFF8A8A9A))),
              const SizedBox(height: 6),
              Text('my_plugin/\n'
                '  manifest.json\n'
                '  windows/my_plugin.dll\n'
                '  linux/my_plugin.so\n'
                '  darwin/my_plugin.dylib\n'
                '  src/\n'
                '    clicker_plugin.h\n'
                '    main.c',
                style: TextStyle(fontSize: 11, fontFamily: 'Consolas, monospace',
                  color: isDark ? const Color(0xFF70E070) : const Color(0xFF2E7D32))),
            ]),
          ),
        ]),
        actions: [
          Button(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(onPressed: () async {
            final id = idCtrl.text.trim();
            final name = nameCtrl.text.trim();
            if (id.isEmpty || name.isEmpty) return;
            await _createPluginProject(id, name, authorCtrl.text.trim(), selectedCategory);
            if (ctx.mounted) Navigator.pop(ctx);
          }, child: const Text('生成')),
        ],
      ),
    );
  }

  Widget _dialogField(String label, TextEditingController ctrl, String hint, bool isDark) {
    return Row(children: [
      SizedBox(width: 60, child: Text(label, style: TextStyle(fontSize: 13, color: isDark ? const Color(0xFF9090B0) : const Color(0xFF8A8A9A)))),
      Expanded(child: TextBox(controller: ctrl, placeholder: hint, padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6))),
    ]);
  }

  Future<void> _createPluginProject(String id, String name, String author, String category) async {
    final dir = await PluginDirManager.getPluginsDir();
    final pluginDir = Directory('${dir.path}${Platform.pathSeparator}${id.replaceAll('.', '_')}');
    if (!await pluginDir.exists()) await pluginDir.create(recursive: true);

    // manifest.json
    final manifest = {
      'id': id,
      'name': name,
      'version': '1.0.0',
      'author': author,
      'description': '',
      'category': category,
      'platforms': ['windows', 'linux', 'macos'],
      'entry': {
        'windows': 'windows/${id.replaceAll('.', '_')}.dll',
        'linux': 'linux/${id.replaceAll('.', '_')}.so',
        'darwin': 'darwin/${id.replaceAll('.', '_')}.dylib',
      },
      'minAppVersion': 1,
    };
    await File('${pluginDir.path}${Platform.pathSeparator}manifest.json')
      .writeAsString(_jsonPretty(manifest));

    // Platform directories
    for (final plat in ['windows', 'linux', 'darwin']) {
      await Directory('${pluginDir.path}${Platform.pathSeparator}$plat').create(recursive: true);
    }

    // src directory with template
    final srcDir = Directory('${pluginDir.path}${Platform.pathSeparator}src');
    await srcDir.create(recursive: true);

    final libName = id.replaceAll('.', '_');
    await File('${srcDir.path}${Platform.pathSeparator}main.c').writeAsString('''
/**
 * $name — Clicker native plugin
 * Build:
 *   Windows: cl /LD main.c /I.. /Fe:../windows/$libName.dll
 *   Linux:   gcc -shared -fPIC main.c -I.. -o ../linux/$libName.so
 *   macOS:   clang -shared -fPIC main.c -I.. -o ../darwin/$libName.dylib
 */

#include "../clicker_plugin.h"
#include <string.h>

static PluginInfo g_info = {
    .id          = "$id",
    .name        = "$name",
    .version     = "1.0.0",
    .author      = "$author",
    .description = "",
    .category    = ${_categoryToCEnum(category)},
    .capabilities = 0,
};

PLUGIN_EXPORT const PluginInfo* PLUGIN_CALL plugin_get_info(void) {
    return &g_info;
}

PLUGIN_EXPORT int32_t PLUGIN_CALL plugin_initialize(void) {
    /* Initialize your plugin here */
    return 0;
}

PLUGIN_EXPORT void PLUGIN_CALL plugin_dispose(void) {
    /* Cleanup resources here */
}
''');

    // Copy SDK header to src dir
    final sdkSrc = File('sdk${Platform.pathSeparator}clicker_plugin.h');
    if (await sdkSrc.exists()) {
      await sdkSrc.copy('${srcDir.path}${Platform.pathSeparator}clicker_plugin.h');
    }

    // Refresh plugin list
    await PluginRegistry.instance.discoverExternalPlugins();
    if (mounted) setState(() {});
  }

  String _categoryToCEnum(String category) {
    const map = {
      'core': 'PLUGIN_CAT_CORE',
      'click': 'PLUGIN_CAT_CLICK',
      'vision': 'PLUGIN_CAT_VISION',
      'automation': 'PLUGIN_CAT_AUTOMATION',
      'ui': 'PLUGIN_CAT_UI',
      'extension': 'PLUGIN_CAT_EXTENSION',
    };
    return map[category] ?? 'PLUGIN_CAT_EXTENSION';
  }

  String _jsonPretty(Map<String, dynamic> json) {
    return const JsonEncoder.withIndent('  ').convert(json);
  }

  Widget _buildGroup(String title, bool isDark, List<Widget> children) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700,
        color: isDark ? const Color(0xFFC0C0E8) : const Color(0xFF5A5A80))),
      const SizedBox(height: 8),
      ...children,
      const SizedBox(height: 16),
    ]);
  }

  Widget _buildCoreToggle(BuildContext context, {
    required IconData icon,
    required String name,
    required bool enabled,
    required ValueChanged<bool> onChanged,
  }) {
    final isDark = FluentTheme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF252540).withValues(alpha: 0.5) : const Color(0xFFF0F0FA).withValues(alpha: 0.5);
    final accent = FluentTheme.of(context).accentColor;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: isDark ? const Color(0xFF303050) : const Color(0xFFD0D0E0)),
        ),
        child: Row(children: [
          Container(
            width: 32, height: 32,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(icon, size: 14, color: accent),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
          ToggleSwitch(checked: enabled, onChanged: onChanged),
        ]),
      ),
    );
  }

  Widget _buildPluginCard(ClickerPlugin plugin, bool isDark) {
    final manifest = plugin.manifest;
    final accent = FluentTheme.of(context).accentColor;
    final cardBg = isDark ? const Color(0xFF252540).withValues(alpha: 0.5) : const Color(0xFFF0F0FA).withValues(alpha: 0.5);
    final disabledColor = isDark ? const Color(0xFF606080) : const Color(0xFFB0B0C0);
    final activeColor = plugin.enabled ? accent : disabledColor;
    final currentPlatform = LoadedNativePlugin.currentPlatform;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: isDark ? const Color(0xFF303050) : const Color(0xFFD0D0E0)),
        ),
        child: Row(children: [
          Container(
            width: 32, height: 32,
            decoration: BoxDecoration(
              color: activeColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(manifest.icon, size: 14, color: activeColor),
          ),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(manifest.name, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13,
                color: plugin.enabled ? null : disabledColor)),
              const SizedBox(width: 6),
              if (manifest.source == PluginSource.builtin)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00E676).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: const Text('内置', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: Color(0xFF00E676))),
                )
              else
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: const Color(0xFF42A5F5).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: const Text('外部', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: Color(0xFF42A5F5))),
                ),
              const SizedBox(width: 4),
              ...manifest.platforms.map((p) => Padding(
                padding: const EdgeInsets.only(right: 3),
                child: _platformBadge(p, p == currentPlatform, isDark),
              )),
            ]),
            const SizedBox(height: 2),
            Text('v${manifest.version}${manifest.author.isNotEmpty ? ' · ${manifest.author}' : ''}',
              style: TextStyle(fontSize: 11, color: isDark ? const Color(0xFF9090B0) : const Color(0xFF8A8A9A))),
          ])),
          // Toggle
          ToggleSwitch(
            checked: plugin.enabled,
            onChanged: plugin.installed ? (v) async {
              if (v) {
                await PluginRegistry.instance.enablePlugin(manifest.id);
              } else {
                await PluginRegistry.instance.disablePlugin(manifest.id);
              }
              setState(() {});
            } : null,
          ),
          const SizedBox(width: 6),
          IconButton(
            icon: Icon(FluentIcons.delete, size: 12, color: Colors.red.withValues(alpha: 0.7)),
            onPressed: () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (ctx) => ContentDialog(
                  title: const Text('确认卸载'),
                  content: Text('确定要卸载「${manifest.name}」吗？相关文件将被删除。'),
                  actions: [
                    Button(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
                    FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('卸载')),
                  ],
                ),
              );
              if (confirmed == true) {
                await PluginRegistry.instance.uninstallPlugin(manifest.id);
                setState(() {});
              }
            },
          ),
        ]),
      ),
    );
  }

  Widget _platformBadge(String platform, bool isCurrent, bool isDark) {
    final color = isCurrent
      ? const Color(0xFFFFB74D)
      : (isDark ? const Color(0xFF606080) : const Color(0xFFB0B0C0));
    final label = {
      'windows': 'Win',
      'linux': 'Linux',
      'macos': 'macOS',
      'darwin': 'macOS',
    }[platform] ?? platform;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(3),
        border: isCurrent ? Border.all(color: color.withValues(alpha: 0.3)) : null,
      ),
      child: Text(label, style: TextStyle(fontSize: 8, fontWeight: FontWeight.w600, color: color)),
    );
  }
}
