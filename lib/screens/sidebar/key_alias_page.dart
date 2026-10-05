
import 'package:file_picker/file_picker.dart';
import 'package:fluent_ui/fluent_ui.dart';

import '../../models/key_alias.dart';
import '../../services/app_paths.dart';
import '../../services/key_alias_service.dart';

class KeyAliasPage extends StatefulWidget {
  const KeyAliasPage({super.key});

  @override
  State<KeyAliasPage> createState() => _KeyAliasPageState();
}

class _KeyAliasPageState extends State<KeyAliasPage> {
  final KeyAliasService _svc = KeyAliasService.instance;
  late final TextEditingController _profileNameCtrl;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _profileNameCtrl = TextEditingController();
    _svc.ensureLoaded().then((_) {
      if (!mounted) return;
      setState(() => _profileNameCtrl.text = _svc.activeProfile?.name ?? '');
    });
  }

  @override
  void dispose() {
    _profileNameCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickProfile(int index) async {
    await _svc.setActive(index);
    if (!mounted) return;
    setState(() => _profileNameCtrl.text = _svc.activeProfile?.name ?? '');
  }

  Future<void> _addAlias() async {
    final result = await showDialog<(String, String)>(
      context: context,
      builder: (ctx) => const _AliasEditDialog(),
    );
    if (result == null) return;
    await _svc.addAlias(result.$1, result.$2);
  }

  Future<void> _editAlias(int index) async {
    final current = _svc.aliases[index];
    final result = await showDialog<(String, String)>(
      context: context,
      builder: (ctx) => _AliasEditDialog(initial: current),
    );
    if (result == null) return;
    await _svc.updateAlias(index, name: result.$1, key: result.$2);
  }

  Future<void> _export() async {
    setState(() => _busy = true);
    try {
      final dir = await AppPaths.getDataDir();
      final stamp = DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first;
      final path = await FilePicker.platform.saveFile(
        dialogTitle: '导出按键别名',
        fileName: 'key_aliases_$stamp.json',
        initialDirectory: dir,
        type: FileType.custom,
        allowedExtensions: const ['json'],
      );
      if (path == null) return;
      await _svc.exportTo(path);
      if (!mounted) return;
      _toast('已导出到 $path');
    } catch (e) {
      if (!mounted) return;
      _toast('导出失败: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    setState(() => _busy = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['json'],
        withData: false,
      );
      final path = result?.files.firstOrNull?.path;
      if (path == null) return;
      final count = await _svc.importFrom(path);
      if (!mounted) return;
      _toast(count > 0 ? '已导入 $count 个方案' : '文件里没有可用方案');
    } catch (e) {
      if (!mounted) return;
      _toast('导入失败: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toast(String message) {
    showDialog<void>(
      context: context,
      builder: (ctx) => ContentDialog(
        title: const Text('按键别名'),
        content: Text(message),
        actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('确定'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = FluentTheme.of(context).brightness == Brightness.dark;
    return ListenableBuilder(
      listenable: _svc,
      builder: (context, _) {
        final profiles = _svc.profiles;
        final aliases = _svc.aliases;
        return ScaffoldPage.scrollable(
          padding: const EdgeInsets.all(20),
          children: [
            Row(children: [
              const Icon(FluentIcons.keyboard_classic, size: 20),
              const SizedBox(width: 10),
              const Text('按键别名',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
              const Spacer(),
              if (_busy)
                const SizedBox(
                    width: 16,
                    height: 16,
                    child: ProgressRing(strokeWidth: 2)),
            ]),
            const SizedBox(height: 16),
            _card(
              isDark,
              title: '方案',
              icon: FluentIcons.list,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  SizedBox(
                    width: 200,
                    child: ComboBox<int>(
                      isExpanded: true,
                      value: _svc.activeIndex,
                      items: [
                        for (var i = 0; i < profiles.length; i++)
                          ComboBoxItem(value: i, child: Text(profiles[i].name)),
                      ],
                      onChanged: (v) {
                        if (v != null) _pickProfile(v);
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 180,
                    child: TextBox(
                      controller: _profileNameCtrl,
                      placeholder: '方案名称',
                      onSubmitted: (v) => _svc.renameProfile(_svc.activeIndex, v),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Button(
                    onPressed: () => _svc.renameProfile(_svc.activeIndex, _profileNameCtrl.text),
                    child: const Text('重命名'),
                  ),
                ]),
                const SizedBox(height: 8),
                Row(children: [
                  Button(
                    onPressed: () async {
                      await _svc.addProfile('方案 ${profiles.length + 1}');
                      if (!mounted) return;
                      setState(() =>
                          _profileNameCtrl.text = _svc.activeProfile?.name ?? '');
                    },
                    child: const Text('新建方案'),
                  ),
                  const SizedBox(width: 8),
                  Button(
                    onPressed: profiles.length > 1
                        ? () async {
                            await _svc.removeProfile(_svc.activeIndex);
                            if (!mounted) return;
                            setState(() =>
                                _profileNameCtrl.text = _svc.activeProfile?.name ?? '');
                          }
                        : null,
                    child: const Text('删除方案'),
                  ),
                  const Spacer(),
                  Button(onPressed: _busy ? null : _import, child: const Text('导入')),
                  const SizedBox(width: 8),
                  Button(onPressed: _busy ? null : _export, child: const Text('导出')),
                ]),
              ]),
            ),
            const SizedBox(height: 12),
            _card(
              isDark,
              title: '别名 (${aliases.length})',
              icon: FluentIcons.tag,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (aliases.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 4),
                    child: Text('暂无别名', style: TextStyle(fontSize: 12)),
                  )
                else
                  for (var i = 0; i < aliases.length; i++)
                    _aliasRow(isDark, i, aliases[i]),
                const SizedBox(height: 8),
                Button(
                  onPressed: _addAlias,
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(FluentIcons.add, size: 12),
                    SizedBox(width: 6),
                    Text('添加别名'),
                  ]),
                ),
              ]),
            ),
          ],
        );
      },
    );
  }

  Widget _aliasRow(bool isDark, int index, KeyAlias alias) {
    final muted = isDark ? const Color(0xFF9090B0) : const Color(0xFF8A8A9A);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(children: [
        Expanded(
          child: Text('$keyAliasPrefix${alias.name}',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 140,
          child: Text(keySpecLabel(alias.key),
              style: TextStyle(fontSize: 12, color: muted),
              overflow: TextOverflow.ellipsis),
        ),
        IconButton(
          icon: const Icon(FluentIcons.edit, size: 12),
          onPressed: () => _editAlias(index),
        ),
        IconButton(
          icon: const Icon(FluentIcons.delete, size: 12),
          onPressed: () => _svc.removeAlias(index),
        ),
      ]),
    );
  }

  Widget _card(bool isDark, {required String title, required IconData icon, required Widget child}) {
    return Card(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 16),
          const SizedBox(width: 8),
          Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        ]),
        const SizedBox(height: 12),
        child,
      ]),
    );
  }
}

class _AliasEditDialog extends StatefulWidget {
  final KeyAlias? initial;
  const _AliasEditDialog({this.initial});

  @override
  State<_AliasEditDialog> createState() => _AliasEditDialogState();
}

class _AliasEditDialogState extends State<_AliasEditDialog> {
  late final TextEditingController _nameCtrl;
  late int _categoryIndex;
  late String _key;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.initial?.name ?? '');
    _key = widget.initial?.key ?? 'space';
    _categoryIndex = keySpecCategories
        .indexWhere((c) => c.$2.contains(_key))
        .clamp(0, keySpecCategories.length - 1);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final category = keySpecCategories[_categoryIndex];
    return ContentDialog(
      title: Text(widget.initial == null ? '添加别名' : '编辑别名'),
      content: SizedBox(
        width: 380,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            const Text('名称', style: TextStyle(fontSize: 12)),
            const SizedBox(width: 8),
            Expanded(
              child: TextBox(
                controller: _nameCtrl,
                placeholder: '别名',
                autofocus: true,
              ),
            ),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            const Text('类别', style: TextStyle(fontSize: 12)),
            const SizedBox(width: 8),
            SizedBox(
              width: 110,
              child: ComboBox<int>(
                isExpanded: true,
                value: _categoryIndex,
                items: [
                  for (var i = 0; i < keySpecCategories.length; i++)
                    ComboBoxItem(value: i, child: Text(keySpecCategories[i].$1)),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  setState(() {
                    _categoryIndex = v;
                    _key = keySpecCategories[v].$2.first;
                  });
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ComboBox<String>(
                isExpanded: true,
                value: category.$2.contains(_key) ? _key : category.$2.first,
                items: [
                  for (final k in category.$2)
                    ComboBoxItem(value: k, child: Text(keySpecLabel(k))),
                ],
                onChanged: (v) {
                  if (v != null) setState(() => _key = v);
                },
              ),
            ),
          ]),
        ]),
      ),
      actions: [
        Button(onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton(
          onPressed: () {
            final name = _nameCtrl.text.trim();
            if (name.isEmpty) return;
            Navigator.pop(context, (name, _key));
          },
          child: const Text('确定'),
        ),
      ],
    );
  }
}
