import 'package:fluent_ui/fluent_ui.dart';
import 'package:provider/provider.dart';

import '../../services/app_state.dart';
import '../../services/script_engine.dart';

class ScriptPage extends StatelessWidget {
  const ScriptPage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final scripts = state.scripts;
    final enabled = state.clickerConfig.scriptEngineEnabled;
    final running = state.scriptStatus == ScriptStatus.running;
    final isDark = FluentTheme.of(context).brightness == Brightness.dark;
    final subColor = isDark ? const Color(0xFF9090B0) : const Color(0xFF8A8A9A);

    return ScaffoldPage.scrollable(
      padding: const EdgeInsets.all(20),
      children: [
        Row(children: [
          Icon(FluentIcons.command_prompt, size: 20, color: state.accentColor),
          const SizedBox(width: 10),
          const Text('脚本', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          const Spacer(),
          if (running)
            Button(
              onPressed: state.stopScript,
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(FluentIcons.stop, size: 14),
                SizedBox(width: 6),
                Text('停止'),
              ]),
            ),
        ]),
        const SizedBox(height: 16),
        Card(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            const Text('脚本功能', style: TextStyle(fontSize: 13)),
            const Spacer(),
            ToggleSwitch(checked: enabled, onChanged: state.setScriptEngineEnabled),
          ]),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: Text('共 ${scripts.length} 个脚本',
                style: TextStyle(fontSize: 13, color: subColor)),
          ),
          Button(
            onPressed: () => _edit(context, state, null),
            child: const Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(FluentIcons.add, size: 14),
              SizedBox(width: 6),
              Text('新建脚本'),
            ]),
          ),
        ]),
        const SizedBox(height: 12),
        if (scripts.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 48),
            child: Center(
              child: Text('还没有脚本', style: TextStyle(fontSize: 13, color: subColor)),
            ),
          ),
        for (final script in scripts) ...[
          _ScriptCard(
            script: script,
            engineEnabled: enabled,
            subColor: subColor,
            isDark: isDark,
            onRun: () => state.runScript(script),
            onEdit: () => _edit(context, state, script),
            onDelete: () => state.removeScript(script.id),
            onToggle: (value) {
              script.enabled = value;
              state.updateScript(script);
            },
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }

  Future<void> _edit(BuildContext context, AppState state, ScriptModel? script) async {
    final result = await showDialog<(String, String)>(
      context: context,
      builder: (context) => _ScriptEditDialog(initial: script),
    );
    if (result == null) return;
    final commands = ScriptEngine.parseScript(result.$2);
    if (commands.isEmpty) return;
    if (script == null) {
      await state.addScript(ScriptModel(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        name: result.$1,
        commands: commands,
      ));
    } else {
      script.name = result.$1;
      script.commands = commands;
      await state.updateScript(script);
    }
  }
}

class _ScriptCard extends StatelessWidget {
  final ScriptModel script;
  final bool engineEnabled;
  final Color subColor;
  final bool isDark;
  final VoidCallback onRun;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final ValueChanged<bool> onToggle;

  const _ScriptCard({
    required this.script,
    required this.engineEnabled,
    required this.subColor,
    required this.isDark,
    required this.onRun,
    required this.onEdit,
    required this.onDelete,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final dangerColor = isDark ? const Color(0xFFE06666) : const Color(0xFFC0392B);
    return Card(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(script.name,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          ),
          Text('${script.commands.length} 条命令', style: TextStyle(fontSize: 12, color: subColor)),
          const SizedBox(width: 10),
          ToggleSwitch(checked: script.enabled, onChanged: onToggle),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Button(
            onPressed: engineEnabled && script.enabled ? onRun : null,
            child: const Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(FluentIcons.play, size: 14),
              SizedBox(width: 6),
              Text('运行'),
            ]),
          ),
          const SizedBox(width: 8),
          Button(
            onPressed: onEdit,
            child: const Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(FluentIcons.edit, size: 14),
              SizedBox(width: 6),
              Text('编辑'),
            ]),
          ),
          const Spacer(),
          GestureDetector(
            onTap: onDelete,
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(FluentIcons.delete, size: 14, color: dangerColor),
                const SizedBox(width: 4),
                Text('删除', style: TextStyle(fontSize: 12, color: dangerColor)),
              ]),
            ),
          ),
        ]),
      ]),
    );
  }
}

class _ScriptEditDialog extends StatefulWidget {
  final ScriptModel? initial;
  const _ScriptEditDialog({this.initial});

  @override
  State<_ScriptEditDialog> createState() => _ScriptEditDialogState();
}

class _ScriptEditDialogState extends State<_ScriptEditDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _textController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initial?.name ?? '');
    _textController = TextEditingController(
      text: widget.initial == null ? '' : ScriptEngine.formatScript(widget.initial!.commands),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ContentDialog(
      constraints: const BoxConstraints(maxWidth: 560, maxHeight: 700),
      title: Text(widget.initial == null ? '新建脚本' : '编辑脚本'),
      content: SizedBox(
        width: 500,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          TextBox(controller: _nameController, placeholder: '名称'),
          const SizedBox(height: 12),
          TextBox(
            controller: _textController,
            maxLines: 16,
            placeholder: 'click 100 200',
            style: const TextStyle(fontFamily: 'Consolas', fontSize: 13),
          ),
          const SizedBox(height: 8),
          const Text(
            'click x y [按键] · key 键名 · delay 毫秒 · move x y · scroll dx dy · type 文本 延迟 · repeat 次数 · start_clicker · stop_clicker',
            style: TextStyle(fontSize: 12),
          ),
        ]),
      ),
      actions: [
        Button(onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton(
          onPressed: () {
            final name = _nameController.text.trim();
            Navigator.pop(context, (name.isEmpty ? '未命名脚本' : name, _textController.text));
          },
          child: const Text('保存'),
        ),
      ],
    );
  }
}
