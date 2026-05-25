/// Plugin center — install external plugins, manage built-in plugins,
/// create new plugin projects, and browse by platform/category.
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

class PluginPage extends StatefulWidget {
  const PluginPage({super.key});

  @override
  State<PluginPage> createState() => _PluginPageState();
}

class _PluginPageState extends State<PluginPage> {
  bool _isInstalling = false;

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
              setState(() {});
            },
          ),
        ]),
        const SizedBox(height: 20),

        // Core settings (always available, not plugins)
        _buildGroup('核心设置', isDark, [
          _buildCoreToggle(context, icon: FluentIcons.accounts, name: '拟人模式',
            enabled: config.humanLikeEnabled,
            onChanged: (v) => state.setClickerConfig(config.copyWith(
              humanLikeEnabled: v, smartDelayEnabled: v, randomOffsetEnabled: v))),
          _buildCoreToggle(context, icon: FluentIcons.volume2, name: '声音反馈',
            enabled: config.soundFeedbackEnabled,
            onChanged: (v) => state.setClickerConfig(config.copyWith(soundFeedbackEnabled: v))),
          _buildCoreToggle(context, icon: FluentIcons.chart, name: '统计追踪',
            enabled: config.statsEnabled,
            onChanged: (v) => state.setClickerConfig(config.copyWith(statsEnabled: v))),
        ]),

        // Built-in plugins
        ..._buildCategoryGroups(
          allPlugins.where((p) => p.manifest.source == PluginSource.builtin).toList(), isDark),

        // External plugins
        ..._buildCategoryGroups(
          allPlugins.where((p) => p.manifest.source != PluginSource.builtin).toList(), isDark,
          groupTitle: '外部插件'),
      ],
    );
  }

  List<Widget> _buildCategoryGroups(List<ClickerPlugin> plugins, bool isDark, {String? groupTitle}) {
    if (plugins.isEmpty) return [];
    final categories = PluginCategory.values;
    return categories.expand((cat) {
      final catPlugins = plugins.where((p) => p.manifest.category == cat).toList();
      if (catPlugins.isEmpty) return <Widget>[];
      return [
        _buildGroup(groupTitle != null ? '$groupTitle · ${cat.label}' : cat.label,
          isDark, catPlugins.map((p) => _buildPluginCard(p, isDark)).toList()),
      ];
    }).toList();
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
        padding: WidgetStatePropertyAll(const EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
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
      final result = await FilePicker.pickFiles(
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

    // Copy SDK header
    final sdkHeader = File('${pluginDir.path}${Platform.pathSeparator}src${Platform.pathSeparator}clicker_plugin.h');
    // We'll reference the SDK header, but also create a template main.c
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

/* Uncomment to implement template matching:
PLUGIN_EXPORT int32_t PLUGIN_CALL plugin_template_match(
    const uint8_t* region_data, int32_t region_w, int32_t region_h,
    const uint8_t* tpl_data,    int32_t tpl_w,    int32_t tpl_h,
    double threshold,
    PluginMatchResult* out_results, int32_t max_results) {
    return 0;
}
*/

/* Uncomment to implement OCR:
PLUGIN_EXPORT int32_t PLUGIN_CALL plugin_ocr(
    const uint8_t* image_data, int32_t w, int32_t h,
    const char* language,
    PluginOcrResult* out_result) {
    return 1;
}
*/

/* Uncomment to implement custom actions:
PLUGIN_EXPORT int32_t PLUGIN_CALL plugin_execute_action(
    const char* action_id,
    const char* params,
    char* out_buf, int32_t out_size) {
    return 1;
}
*/
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
          // Icon
          Container(
            width: 32, height: 32,
            decoration: BoxDecoration(
              color: activeColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(manifest.icon, size: 14, color: activeColor),
          ),
          const SizedBox(width: 10),
          // Info
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(manifest.name, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13,
                color: plugin.enabled ? null : disabledColor)),
              const SizedBox(width: 6),
              // Source badge
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
              // Platform badges
              ...manifest.platforms.map((p) => Padding(
                padding: const EdgeInsets.only(right: 3),
                child: _platformBadge(p, p == currentPlatform, isDark),
              )),
            ]),
            const SizedBox(height: 2),
            Text('v${manifest.version}${manifest.author.isNotEmpty ? ' · ${manifest.author}' : ''}',
              style: TextStyle(fontSize: 11, color: isDark ? const Color(0xFF9090B0) : const Color(0xFF8A8A9A))),
          ])),
          // Controls
          if (!plugin.installed && manifest.source != PluginSource.builtin) ...[
            FilledButton(
              onPressed: () async {
                await PluginRegistry.instance.installPlugin(manifest.id);
                setState(() {});
              },
              style: ButtonStyle(
                backgroundColor: WidgetStatePropertyAll(accent.withValues(alpha: 0.15)),
                padding: WidgetStatePropertyAll(const EdgeInsets.symmetric(horizontal: 12, vertical: 6)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(FluentIcons.download, size: 12, color: accent),
                const SizedBox(width: 4),
                Text('安装', style: TextStyle(color: accent, fontSize: 12)),
              ]),
            ),
          ] else if (plugin.installed && !plugin.enabled) ...[
            Button(
              onPressed: () async {
                await PluginRegistry.instance.enablePlugin(manifest.id);
                setState(() {});
              },
              style: ButtonStyle(
                padding: WidgetStatePropertyAll(const EdgeInsets.symmetric(horizontal: 12, vertical: 6)),
              ),
              child: const Text('启用', style: TextStyle(fontSize: 12)),
            ),
            const SizedBox(width: 6),
            if (manifest.source != PluginSource.builtin)
              IconButton(
                icon: Icon(FluentIcons.delete, size: 12, color: Colors.red.withValues(alpha: 0.7)),
                onPressed: () async {
                  await PluginRegistry.instance.uninstallPlugin(manifest.id);
                  setState(() {});
                },
              ),
          ] else ...[
            ToggleSwitch(
              checked: plugin.enabled,
              onChanged: (v) async {
                if (v) {
                  await PluginRegistry.instance.enablePlugin(manifest.id);
                } else {
                  await PluginRegistry.instance.disablePlugin(manifest.id);
                }
                setState(() {});
              },
            ),
            const SizedBox(width: 6),
            if (manifest.source != PluginSource.builtin)
              IconButton(
                icon: Icon(FluentIcons.delete, size: 12, color: Colors.red.withValues(alpha: 0.7)),
                onPressed: () async {
                  await PluginRegistry.instance.uninstallPlugin(manifest.id);
                  setState(() {});
                },
              ),
          ],
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
