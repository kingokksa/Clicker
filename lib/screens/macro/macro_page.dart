/// Macro page — macro recording, list, playback, and keyboard sequence builder.
/// Fluent UI design.
library;

import 'package:fluent_ui/fluent_ui.dart';
import 'package:provider/provider.dart';
import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import '../../services/app_state.dart';
import '../../models/macro_model.dart';

class MacroPage extends StatelessWidget {
  const MacroPage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final macros = state.macros;

    return ScaffoldPage.scrollable(
      padding: const EdgeInsets.all(20),
      children: [
        // Recording / Playing status
        if (state.isRecording) _buildRecordingStatus(state),
        if (state.isPlaying) _buildPlayingStatus(state),

        if (state.isRecording || state.isPlaying) const SizedBox(height: 12),

        // Action buttons
        _buildRecordButton(context, state),
        const SizedBox(height: 8),

        if (!state.isRecording && !state.isPlaying) ...[
          Row(children: [
            Expanded(child: Button(onPressed: () => _showKeySequenceBuilder(context, state), child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(FluentIcons.keyboard_classic, size: 16), SizedBox(width: 6), Text('按键序列')]))),
            const SizedBox(width: 8),
            Expanded(child: Button(onPressed: () => _showComboBuilder(context, state), child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(FluentIcons.merge, size: 16), SizedBox(width: 6), Text('组合键')]))),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: Button(onPressed: () => _showTextTypeBuilder(context, state), child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(FluentIcons.font, size: 14), SizedBox(width: 4), Text('自动打字')]))),
            const SizedBox(width: 8),
            Expanded(child: Button(onPressed: () => _showScrollBuilder(context, state), child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(FluentIcons.scroll_up_down, size: 14), SizedBox(width: 4), Text('滚轮宏')]))),
            const SizedBox(width: 8),
            Expanded(child: Button(onPressed: () => _showDelayBuilder(context, state), child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(FluentIcons.stopwatch, size: 14), SizedBox(width: 4), Text('延时宏')]))),
          ]),
        ],

        const SizedBox(height: 16),
        Row(children: [
          Text('已保存的宏 (${macros.length})', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          const Spacer(),
          Button(onPressed: () => _importMacro(context, state), child: const Row(mainAxisSize: MainAxisSize.min, children: [Icon(FluentIcons.open_file, size: 14), SizedBox(width: 4), Text('导入')])),
          const SizedBox(width: 6),
          Button(onPressed: macros.isEmpty ? null : () => _exportAllMacros(context, state), child: const Row(mainAxisSize: MainAxisSize.min, children: [Icon(FluentIcons.save, size: 14), SizedBox(width: 4), Text('导出全部')])),
        ]),
        const SizedBox(height: 8),

        if (macros.isEmpty)
          const Center(child: Padding(padding: EdgeInsets.all(32), child: Column(children: [
            Icon(FluentIcons.video_off, size: 48),
            SizedBox(height: 12),
            Text('暂无宏', style: TextStyle(fontSize: 14)),
            Text('点击"开始录制"或"按键序列"创建宏', style: TextStyle(fontSize: 12)),
          ])))
        else
          ...macros.map((macro) => _buildMacroCard(context, macro, state)),
      ],
    );
  }

  // ─── Status Bars ──────────────────────────────────────────

  Widget _buildRecordingStatus(AppState state) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.red.withOpacity(0.08), borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.red.withOpacity(0.3))),
      child: Row(children: [
        Icon(FluentIcons.record2, color: Colors.red, size: 16),
        const SizedBox(width: 8),
        Text('录制中 · ${state.recordingEventCount} 个事件', style: TextStyle(color: Colors.red, fontSize: 13)),
        const Spacer(),
        Text('按 ${state.hotkeyConfig.startStopRecording} 停止', style: TextStyle(color: Colors.red.withOpacity(0.7), fontSize: 12)),
      ]),
    );
  }

  Widget _buildPlayingStatus(AppState state) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: const Color(0xFF00E676).withOpacity(0.08), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFF00E676).withOpacity(0.3))),
      child: Row(children: [
        const Icon(FluentIcons.play, color: Color(0xFF00E676), size: 16),
        const SizedBox(width: 8),
        Text('播放中 · ${state.playbackEventIndex}/${state.playbackTotalEvents}', style: const TextStyle(color: Color(0xFF00E676), fontSize: 13)),
        const Spacer(),
        if (state.playbackTotalEvents > 0)
          Expanded(child: Padding(padding: const EdgeInsets.only(left: 12), child: ProgressBar(
            value: state.playbackTotalEvents > 0 ? (state.playbackEventIndex / state.playbackTotalEvents * 100) : 0,
          ))),
      ]),
    );
  }

  // ─── Record Button ────────────────────────────────────────

  Widget _buildRecordButton(BuildContext context, AppState state) {
    if (state.isRecording) {
      return SizedBox(width: double.infinity, height: 48, child: FilledButton(
        onPressed: () => _stopRecording(context, state),
        style: ButtonStyle(backgroundColor: WidgetStatePropertyAll(Colors.red)),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(FluentIcons.stop, size: 18, color: Colors.white), SizedBox(width: 8), Text('停止录制', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white))]),
      ));
    }
    if (state.isPlaying) {
      return SizedBox(width: double.infinity, height: 48, child: FilledButton(
        onPressed: () => state.stopMacro(),
        style: ButtonStyle(backgroundColor: WidgetStatePropertyAll(Colors.orange)),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(FluentIcons.stop, size: 18, color: Colors.white), SizedBox(width: 8), Text('停止播放', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white))]),
      ));
    }
    return SizedBox(width: double.infinity, height: 48, child: FilledButton(
      onPressed: () => state.startRecording(),
      style: ButtonStyle(backgroundColor: WidgetStatePropertyAll(FluentTheme.of(context).accentColor)),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(FluentIcons.record2, size: 18, color: Colors.white), SizedBox(width: 8), Text('开始录制', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white))]),
    ));
  }

  Future<void> _stopRecording(BuildContext context, AppState state) async {
    // Stop the hook FIRST so no more events are captured while dialog is open
    state.pauseRecording();

    final nameController = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => ContentDialog(
        title: const Text('保存宏'),
        content: TextBox(controller: nameController, autofocus: true, placeholder: '输入宏名称'),
        actions: [
          Button(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, nameController.text), child: const Text('保存')),
        ],
      ),
    );
    if (name != null && context.mounted) {
      await state.stopRecording(name: name.isNotEmpty ? name : '录制的宏');
    }
  }

  // ─── Macro Card ───────────────────────────────────────────

  Widget _buildMacroCard(BuildContext context, MacroModel macro, AppState state) {
    final isDark = FluentTheme.of(context).brightness == Brightness.dark;
    final accent = FluentTheme.of(context).accentColor;
    final disabledBg = isDark ? const Color(0xFF303050) : const Color(0xFFE8E8F0);
    final tagBg = isDark ? const Color(0xFF303050) : const Color(0xFFF0F0F8);
    final disabledIcon = isDark ? const Color(0xFF9090B0) : const Color(0xFF8A8A9A);
    final duration = macro.totalDurationMs;
    final durationStr = duration >= 1000 ? '${(duration / 1000).toStringAsFixed(1)}s' : '${duration}ms';
    final canPlay = !state.isRecording && !state.isPlaying;

    final keyCount = macro.events.where((e) => e.type == MacroEventType.keyPress || e.type == MacroEventType.keyRelease).length;
    final clickCount = macro.events.where((e) => e.type == MacroEventType.click).length;
    final scrollCount = macro.events.where((e) => e.type == MacroEventType.scroll).length;
    final waitCount = macro.events.where((e) => e.type == MacroEventType.wait).length;

    return Card(
      padding: const EdgeInsets.all(12),
      child: Row(children: [
        // Play button
        GestureDetector(
          onTap: canPlay ? () => state.playMacro(macro) : null,
          child: Container(
            width: 38, height: 38,
            decoration: BoxDecoration(
              color: canPlay ? accent.withOpacity(0.15) : disabledBg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(FluentIcons.play, size: 18, color: canPlay ? accent : disabledIcon),
          ),
        ),
        const SizedBox(width: 12),

        // Info
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(macro.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13), overflow: TextOverflow.ellipsis),
          const SizedBox(height: 4),
          Row(children: [
            if (clickCount > 0) ...[_eventTag(FluentIcons.touch_pointer, '$clickCount'), const SizedBox(width: 6)],
            if (keyCount > 0) ...[_eventTag(FluentIcons.keyboard_classic, '${keyCount ~/ 2}'), const SizedBox(width: 6)],
            if (scrollCount > 0) ...[_eventTag(FluentIcons.scroll_up_down, '$scrollCount'), const SizedBox(width: 6)],
            if (waitCount > 0) ...[_eventTag(FluentIcons.stopwatch, '$waitCount'), const SizedBox(width: 6)],
            _infoTag(durationStr, bg: tagBg),
            if (macro.repeatCount > 1) ...[const SizedBox(width: 4), _infoTag('x${macro.repeatCount}', bg: tagBg)],
          ]),
        ])),

        // Menu
        IconButton(
          icon: const Icon(FluentIcons.more, size: 16),
          onPressed: () => _showMacroMenu(context, state, macro),
        ),
      ]),
    );
  }

  Widget _eventTag(IconData icon, String count) {
    return Builder(builder: (context) {
      final accent = FluentTheme.of(context).accentColor;
      return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: accent.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 12, color: accent), const SizedBox(width: 2), Text(count, style: TextStyle(fontSize: 11, color: accent))]),
    );
    });
  }

  Widget _infoTag(String text, {Color? bg, Color? textColor}) {
    return Builder(builder: (context) {
      final isDark = FluentTheme.of(context).brightness == Brightness.dark;
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(color: bg ?? (isDark ? const Color(0xFF303050) : const Color(0xFFF0F0F8)), borderRadius: BorderRadius.circular(4)),
        child: Text(text, style: TextStyle(fontSize: 11, color: textColor ?? (isDark ? const Color(0xFFC0C0D8) : const Color(0xFF5A5A70)))),
      );
    });
  }

  void _showMacroMenu(BuildContext context, AppState state, MacroModel macro) async {
    final result = await showDialog<String>(context: context, builder: (ctx) => ContentDialog(
      title: Text(macro.name),
      content: SizedBox(width: 280, child: Column(mainAxisSize: MainAxisSize.min, children: [
        _menuRow(FluentIcons.play, '播放', 'play'),
        const Divider(),
        _menuRow(FluentIcons.edit, '重命名', 'rename'),
        _menuRow(FluentIcons.settings, '编辑', 'edit'),
        const Divider(),
        _menuRow(FluentIcons.save, '导出 JSON', 'export_json'),
        _menuRow(FluentIcons.save, '导出 AHK', 'export_ahk'),
        const Divider(),
        _menuRow(FluentIcons.delete, '删除', 'delete', isDestructive: true),
      ])),
      actions: [Button(onPressed: () => Navigator.pop(ctx), child: const Text('取消'))],
    ));

    if (!context.mounted) return;
    switch (result) {
      case 'play': state.playMacro(macro); break;
      case 'rename': await _renameMacro(context, state, macro); break;
      case 'edit': _showMacroEditor(context, state, macro); break;
      case 'export_json': await _exportMacroJson(macro); break;
      case 'export_ahk': await _exportMacroAhk(macro); break;
      case 'delete': await _deleteMacro(context, state, macro); break;
    }
  }

  Widget _menuRow(IconData icon, String label, String value, {bool isDestructive = false}) {
    return Builder(builder: (menuContext) {
      final accent = FluentTheme.of(menuContext).accentColor;
      return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => Navigator.pop(menuContext, value),
        child: Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Row(children: [
          Icon(icon, size: 16, color: isDestructive ? Colors.red : accent),
          const SizedBox(width: 10),
          Text(label, style: TextStyle(fontSize: 13, color: isDestructive ? Colors.red : null)),
        ])),
      ),
    );
    });
  }

  Future<void> _renameMacro(BuildContext context, AppState state, MacroModel macro) async {
    final ctrl = TextEditingController(text: macro.name);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => ContentDialog(
        title: const Text('重命名'),
        content: TextBox(controller: ctrl, autofocus: true, placeholder: '新名称'),
        actions: [
          Button(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('确定')),
        ],
      ),
    );
    if (newName != null && newName.isNotEmpty) await state.renameMacro(macro, newName);
  }

  Future<void> _deleteMacro(BuildContext context, AppState state, MacroModel macro) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => ContentDialog(
        title: const Text('删除宏'),
        content: Text('确定要删除 "${macro.name}" 吗?'),
        actions: [
          Button(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), style: ButtonStyle(backgroundColor: WidgetStatePropertyAll(Colors.red)), child: const Text('删除')),
        ],
      ),
    );
    if (confirm == true) await state.deleteMacro(macro);
  }

  // ─── Macro Editor ──────────────────────────────────────────

  void _showMacroEditor(BuildContext context, AppState state, MacroModel macro) {
    showDialog(context: context, builder: (ctx) => _MacroEditorDialog(macro: macro, onSave: (updatedMacro) async {
      await state.saveMacroFromBuilder(updatedMacro);
      if (ctx.mounted) Navigator.pop(ctx);
    }));
  }

  // ─── Key Sequence Builder ──────────────────────────────────

  void _showKeySequenceBuilder(BuildContext context, AppState state) {
    showDialog(context: context, builder: (ctx) => _KeySequenceBuilderDialog(onConfirm: (name, events) async {
      final macro = MacroModel(id: DateTime.now().millisecondsSinceEpoch.toString(), name: name, events: events, repeatCount: 1);
      await state.saveMacroFromBuilder(macro);
      if (ctx.mounted) Navigator.pop(ctx);
    }));
  }

  // ─── Combo Builder ────────────────────────────────────────

  void _showComboBuilder(BuildContext context, AppState state) {
    showDialog(context: context, builder: (ctx) => _ComboBuilderDialog(onConfirm: (name, events) async {
      final macro = MacroModel(id: DateTime.now().millisecondsSinceEpoch.toString(), name: name, events: events, repeatCount: 1);
      await state.saveMacroFromBuilder(macro);
      if (ctx.mounted) Navigator.pop(ctx);
    }));
  }

  // ─── Text Type Builder ─────────────────────────────────────

  void _showTextTypeBuilder(BuildContext context, AppState state) {
    showDialog(context: context, builder: (ctx) => _TextTypeBuilderDialog(onConfirm: (name, events) async {
      final macro = MacroModel(id: DateTime.now().millisecondsSinceEpoch.toString(), name: name, events: events, repeatCount: 1);
      await state.saveMacroFromBuilder(macro);
      if (ctx.mounted) Navigator.pop(ctx);
    }));
  }

  // ─── Scroll Builder ───────────────────────────────────────

  void _showScrollBuilder(BuildContext context, AppState state) {
    showDialog(context: context, builder: (ctx) => _ScrollBuilderDialog(onConfirm: (name, events) async {
      final macro = MacroModel(id: DateTime.now().millisecondsSinceEpoch.toString(), name: name, events: events, repeatCount: 1);
      await state.saveMacroFromBuilder(macro);
      if (ctx.mounted) Navigator.pop(ctx);
    }));
  }

  // ─── Delay Builder ────────────────────────────────────────

  void _showDelayBuilder(BuildContext context, AppState state) {
    showDialog(context: context, builder: (ctx) => _DelayBuilderDialog(onConfirm: (name, events) async {
      final macro = MacroModel(id: DateTime.now().millisecondsSinceEpoch.toString(), name: name, events: events, repeatCount: 1);
      await state.saveMacroFromBuilder(macro);
      if (ctx.mounted) Navigator.pop(ctx);
    }));
  }

  // ─── Import / Export ──────────────────────────────────────

  Future<void> _importMacro(BuildContext context, AppState state) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json', 'ahk', 'txt'],
      dialogTitle: '导入宏',
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    if (file.path == null) return;

    try {
      final content = await File(file.path!).readAsString();
      final ext = p.extension(file.path!).toLowerCase();
      List<MacroModel> imported;

      if (ext == '.ahk' || ext == '.txt') {
        imported = _parseAhkScript(content, p.basenameWithoutExtension(file.path!));
      } else {
        // JSON: can be single macro or list
        final decoded = jsonDecode(content);
        if (decoded is List) {
          imported = decoded.map((e) => MacroModel.fromJson(e as Map<String, dynamic>)).toList();
        } else {
          imported = [MacroModel.fromJson(decoded as Map<String, dynamic>)];
        }
      }

      for (final macro in imported) {
        await state.saveMacroFromBuilder(MacroModel(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          name: macro.name,
          events: macro.events,
          repeatCount: macro.repeatCount,
          speed: macro.speed,
        ));
      }
      if (context.mounted) {
        await showDialog(context: context, builder: (ctx) => ContentDialog(
          title: const Text('导入成功'),
          content: Text('已导入 ${imported.length} 个宏'),
          actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('确定'))],
        ));
      }
    } catch (e) {
      if (context.mounted) {
        await showDialog(context: context, builder: (ctx) => ContentDialog(
          title: const Text('导入失败'),
          content: Text('无法解析文件: $e'),
          actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('确定'))],
        ));
      }
    }
  }

  Future<void> _exportMacroJson(MacroModel macro) async {
    final path = await FilePicker.platform.saveFile(
      dialogTitle: '导出 JSON',
      fileName: '${macro.name}.json',
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (path == null) return;
    final json = const JsonEncoder.withIndent('  ').convert(macro.toJson());
    await File(path).writeAsString(json);
  }

  Future<void> _exportMacroAhk(MacroModel macro) async {
    final path = await FilePicker.platform.saveFile(
      dialogTitle: '导出 AHK',
      fileName: '${macro.name}.ahk',
      type: FileType.custom,
      allowedExtensions: ['ahk'],
    );
    if (path == null) return;
    final ahk = _macroToAhk(macro);
    await File(path).writeAsString(ahk);
  }

  Future<void> _exportAllMacros(BuildContext context, AppState state) async {
    final path = await FilePicker.platform.saveFile(
      dialogTitle: '导出全部宏',
      fileName: 'clicker_macros.json',
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (path == null) return;
    final list = state.macros.map((m) => m.toJson()).toList();
    final json = const JsonEncoder.withIndent('  ').convert(list);
    await File(path).writeAsString(json);
  }

  /// Convert macro to AutoHotKey v1 script
  String _macroToAhk(MacroModel macro) {
    final buf = StringBuffer();
    buf.writeln('#NoEnv');
    buf.writeln('#SingleInstance Force');
    buf.writeln('SetWorkingDir %A_ScriptDir%');
    buf.writeln();
    buf.writeln('; ${macro.name}');
    buf.writeln('; Exported from Clicker');
    buf.writeln();

    for (int r = 0; r < macro.repeatCount; r++) {
      for (final event in macro.events) {
        final delayMs = (1.0 / macro.speed).round();
        switch (event.type) {
          case MacroEventType.click:
            final btn = event.button == 'right' ? 'R' : (event.button == 'middle' ? 'M' : '');
            if (event.x != null && event.y != null) {
              buf.writeln('Click, $btn${event.x}, ${event.y}');
            } else {
              buf.writeln('Click, $btn');
            }
            break;
          case MacroEventType.keyPress:
            if (event.key != null) buf.writeln('Send, {${_ahkKeyName(event.key!)}}');
            break;
          case MacroEventType.keyRelease:
            break; // AHK Send handles release automatically
          case MacroEventType.scroll:
            final dy = event.scrollDy ?? 0;
            if (dy > 0) {
              buf.writeln('Click, WheelDown, ${dy.abs().round()}');
            } else if (dy < 0) {
              buf.writeln('Click, WheelUp, ${dy.abs().round()}');
            }
            break;
          case MacroEventType.wait:
            final ms = delayMs > 0 ? delayMs : 10;
            buf.writeln('Sleep, $ms');
            break;
        }
      }
    }
    buf.writeln();
    buf.writeln('ExitApp');
    return buf.toString();
  }

  /// Parse AutoHotKey script into macros
  List<MacroModel> _parseAhkScript(String content, String defaultName) {
    final events = <MacroEvent>[];
    int ts = 0;

    for (final line in content.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith(';') || trimmed.startsWith('#') ||
          trimmed.startsWith('SetWorkingDir') || trimmed.startsWith('ExitApp') ||
          trimmed.startsWith('#NoEnv') || trimmed.startsWith('#SingleInstance')) {
        continue;
      }

      // Click x, y [button]
      if (trimmed.startsWith('Click')) {
        final parts = trimmed.substring(5).trim().split(RegExp(r'[,\s]+')).where((s) => s.isNotEmpty).toList();
        String button = 'left';
        int? x, y;
        if (parts.isNotEmpty) {
          // Check if first part is a button modifier
          if (parts[0] == 'R' || parts[0] == 'Right') { button = 'right'; parts.removeAt(0); }
          else if (parts[0] == 'M' || parts[0] == 'Middle') { button = 'middle'; parts.removeAt(0); }
          else if (parts[0] == 'WheelDown' || parts[0] == 'WheelUp') {
            final count = parts.length > 1 ? int.tryParse(parts[1]) ?? 1 : 1;
            events.add(MacroEvent(type: MacroEventType.scroll, timestampMs: ts, scrollDy: parts[0] == 'WheelDown' ? count.toDouble() : -count.toDouble()));
            ts += 10;
            continue;
          }
          if (parts.length >= 2) {
            x = int.tryParse(parts[0]);
            y = int.tryParse(parts[1]);
          }
        }
        events.add(MacroEvent(type: MacroEventType.click, timestampMs: ts, x: x, y: y, button: button));
        ts += 10;
      }
      // Send, {key} or Send, text
      else if (trimmed.startsWith('Send')) {
        final arg = trimmed.substring(4).replaceFirst(RegExp(r'^[,\s]+'), '');
        if (arg.startsWith('{') && arg.endsWith('}')) {
          final key = arg.substring(1, arg.length - 1);
          events.add(MacroEvent(type: MacroEventType.keyPress, timestampMs: ts, key: key));
          ts += 10;
        }
      }
      // Sleep, ms
      else if (trimmed.startsWith('Sleep')) {
        final msStr = trimmed.substring(5).replaceFirst(RegExp(r'^[,\s]+'), '');
        final ms = int.tryParse(msStr) ?? 100;
        events.add(MacroEvent(type: MacroEventType.wait, timestampMs: ts));
        ts += ms;
      }
    }

    return [MacroModel(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: defaultName,
      events: events,
      repeatCount: 1,
      speed: 1.0,
    )];
  }

  /// Map key names to AHK format
  String _ahkKeyName(String key) {
    const map = {
      'enter': 'Enter', 'tab': 'Tab', 'escape': 'Escape', 'backspace': 'Backspace',
      'space': 'Space', 'delete': 'Delete', 'insert': 'Insert', 'home': 'Home',
      'end': 'End', 'pageup': 'PgUp', 'pagedown': 'PgDn',
      'up': 'Up', 'down': 'Down', 'left': 'Left', 'right': 'Right',
      'shift': 'Shift', 'ctrl': 'Ctrl', 'alt': 'Alt', 'win': 'LWin',
      'f1': 'F1', 'f2': 'F2', 'f3': 'F3', 'f4': 'F4', 'f5': 'F5', 'f6': 'F6',
      'f7': 'F7', 'f8': 'F8', 'f9': 'F9', 'f10': 'F10', 'f11': 'F11', 'f12': 'F12',
    };
    return map[key.toLowerCase()] ?? key;
  }
}

// ─── Shared Chip Builder ─────────────────────────────────────

Widget _chip(String label, bool selected, VoidCallback onTap, {IconData? icon}) {
  return Builder(builder: (context) {
    final isDark = FluentTheme.of(context).brightness == Brightness.dark;
    final accent = FluentTheme.of(context).accentColor;
    final unselectedBg = isDark ? const Color(0xFF303050) : const Color(0xFFE8E8F0);
    final unselectedBorder = isDark ? const Color(0xFF404060) : const Color(0xFFD0D0D8);
    final unselectedText = isDark ? const Color(0xFFC0C0D8) : const Color(0xFF5A5A70);
    final unselectedIcon = isDark ? const Color(0xFF9090B0) : const Color(0xFF8A8A9A);
    return MouseRegion(cursor: SystemMouseCursors.click, child: GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? accent.withOpacity(0.2) : unselectedBg,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: selected ? accent : unselectedBorder),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: 12, color: selected ? accent : unselectedIcon), const SizedBox(width: 4)],
          Text(label, style: TextStyle(fontSize: 11, fontWeight: selected ? FontWeight.w600 : FontWeight.normal, color: selected ? accent : unselectedText)),
        ]),
      ),
    ));
  });
}

// ─── Macro Editor Dialog ─────────────────────────────────────

class _MacroEditorDialog extends StatefulWidget {
  final MacroModel macro;
  final Future<void> Function(MacroModel macro) onSave;
  const _MacroEditorDialog({required this.macro, required this.onSave});
  @override
  State<_MacroEditorDialog> createState() => _MacroEditorDialogState();
}

class _MacroEditorDialogState extends State<_MacroEditorDialog> {
  late TextEditingController _nameCtrl;
  late int _repeatCount;
  late double _speed;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.macro.name);
    _repeatCount = widget.macro.repeatCount;
    _speed = widget.macro.speed;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = FluentTheme.of(context).brightness == Brightness.dark;
    final accent = FluentTheme.of(context).accentColor;
    final containerBg = isDark ? const Color(0xFF303050) : const Color(0xFFF0F0F8);
    final macro = widget.macro;
    final keyCount = macro.events.where((e) => e.type == MacroEventType.keyPress || e.type == MacroEventType.keyRelease).length;
    final clickCount = macro.events.where((e) => e.type == MacroEventType.click).length;

    return ContentDialog(
      title: const Text('编辑宏'),
      content: SizedBox(width: 380, child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextBox(controller: _nameCtrl, placeholder: '宏名称'),
        const SizedBox(height: 12),
        // Event summary
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: containerBg, borderRadius: BorderRadius.circular(8)),
          child: Row(children: [
            if (clickCount > 0) ...[Icon(FluentIcons.touch_pointer, size: 14, color: accent), const SizedBox(width: 4), Text('$clickCount 点击', style: const TextStyle(fontSize: 12)), const SizedBox(width: 12)],
            if (keyCount > 0) ...[Icon(FluentIcons.keyboard_classic, size: 14, color: accent), const SizedBox(width: 4), Text('${keyCount ~/ 2} 按键', style: const TextStyle(fontSize: 12)), const SizedBox(width: 12)],
            Icon(FluentIcons.timer, size: 14, color: accent), const SizedBox(width: 4), Text('${macro.totalDurationMs}ms', style: const TextStyle(fontSize: 12)),
          ]),
        ),
        const SizedBox(height: 12),
        // Repeat count
        Row(children: [
          const Text('重复次数:', style: TextStyle(fontSize: 13)),
          const SizedBox(width: 8),
          SizedBox(width: 80, child: TextBox(
            controller: TextEditingController(text: _repeatCount == 0 ? '∞' : _repeatCount.toString()),
            onChanged: (v) { final p = int.tryParse(v); if (p != null) setState(() => _repeatCount = p); },
          )),
          const SizedBox(width: 8),
          const Text('(0=无限)', style: TextStyle(fontSize: 11)),
        ]),
        const SizedBox(height: 12),
        // Speed
        Row(children: [
          const Text('播放速度:', style: TextStyle(fontSize: 13)),
          const SizedBox(width: 8),
          Text('${_speed.toStringAsFixed(1)}x', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          Expanded(child: Slider(value: _speed, min: 0.1, max: 5.0, divisions: 49, onChanged: (v) => setState(() => _speed = v))),
        ]),
      ])),
      actions: [FilledButton(onPressed: () {
        final updated = widget.macro.copyWith(name: _nameCtrl.text.isNotEmpty ? _nameCtrl.text : widget.macro.name, repeatCount: _repeatCount, speed: _speed);
        widget.onSave(updated);
      }, child: const Text('保存'))],
    );
  }
}

// ─── Key Sequence Builder Dialog ──────────────────────────────

class _KeySequenceBuilderDialog extends StatefulWidget {
  final Future<void> Function(String name, List<MacroEvent> events) onConfirm;
  const _KeySequenceBuilderDialog({required this.onConfirm});
  @override
  State<_KeySequenceBuilderDialog> createState() => _KeySequenceBuilderDialogState();
}

class _KeySequenceBuilderDialogState extends State<_KeySequenceBuilderDialog> {
  final _nameCtrl = TextEditingController(text: '按键序列');
  final List<_KeyEntry> _entries = [];
  int _delayMs = 50;

  static const _keyCategories = <(String, List<String>)>[
    ('功能键', ['F1','F2','F3','F4','F5','F6','F7','F8','F9','F10','F11','F12']),
    ('编辑键', ['Space','Enter','Tab','Escape','Backspace','Delete','Insert']),
    ('方向键', ['Up','Down','Left','Right','Home','End','PageUp','PageDown']),
    ('数字', ['0','1','2','3','4','5','6','7','8','9']),
    ('字母', ['A','B','C','D','E','F','G','H','I','J','K','L','M','N','O','P','Q','R','S','T','U','V','W','X','Y','Z']),
  ];

  static const _templates = <(String, List<_KeyEntry>)>[
    ('WASD移动', [_KeyEntry(key: 'w', delayMs: 100), _KeyEntry(key: 'a', delayMs: 100), _KeyEntry(key: 's', delayMs: 100), _KeyEntry(key: 'd', delayMs: 100)]),
    ('连招1234', [_KeyEntry(key: '1', delayMs: 200), _KeyEntry(key: '2', delayMs: 200), _KeyEntry(key: '3', delayMs: 200), _KeyEntry(key: '4', delayMs: 200)]),
    ('方向循环', [_KeyEntry(key: 'up', delayMs: 150), _KeyEntry(key: 'right', delayMs: 150), _KeyEntry(key: 'down', delayMs: 150), _KeyEntry(key: 'left', delayMs: 150)]),
    ('空格连跳', [_KeyEntry(key: 'space', delayMs: 80), _KeyEntry(key: 'space', delayMs: 80), _KeyEntry(key: 'space', delayMs: 80)]),
  ];

  void _addKey(String key) => setState(() => _entries.add(_KeyEntry(key: key, delayMs: _delayMs)));
  void _removeEntry(int i) => setState(() => _entries.removeAt(i));

  void _confirm() {
    if (_entries.isEmpty) return;
    final events = <MacroEvent>[];
    int ts = 0;
    for (final entry in _entries) {
      events.add(MacroEvent(type: MacroEventType.keyPress, timestampMs: ts, key: entry.key));
      ts += 20;
      events.add(MacroEvent(type: MacroEventType.keyRelease, timestampMs: ts, key: entry.key));
      ts += entry.delayMs;
    }
    widget.onConfirm(_nameCtrl.text, events);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = FluentTheme.of(context).brightness == Brightness.dark;
    final containerBg = isDark ? const Color(0xFF303050) : const Color(0xFFF0F0F8);
    return ContentDialog(
      title: const Text('按键序列构建器'),
      content: SizedBox(width: 440, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextBox(controller: _nameCtrl, placeholder: '宏名称'),
        const SizedBox(height: 10),
        // Sequence display
        Container(
          constraints: const BoxConstraints(maxHeight: 100),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: containerBg, borderRadius: BorderRadius.circular(8)),
          child: _entries.isEmpty
            ? const Center(child: Text('点击下方按键添加到序列', style: TextStyle(fontSize: 12)))
            : SingleChildScrollView(child: Wrap(spacing: 4, runSpacing: 4, children: [
                for (int i = 0; i < _entries.length; i++) ...[
                  _keyChip(_entries[i].key, () => _removeEntry(i)),
                  if (i < _entries.length - 1) const Icon(FluentIcons.forward, size: 10),
                ],
              ])),
        ),
        if (_entries.isNotEmpty) ...[
          const SizedBox(height: 4),
          Row(children: [
            Text('共 ${_entries.length} 个按键', style: TextStyle(fontSize: 11, color: FluentTheme.of(context).brightness == Brightness.dark ? const Color(0xFF9090B0) : const Color(0xFF8A8A9A))),
            const Spacer(),
            HyperlinkButton(onPressed: () => setState(() => _entries.clear()), child: const Text('清空')),
          ]),
        ],
        const SizedBox(height: 8),
        // Delay
        Row(children: [
          const Text('延迟:', style: TextStyle(fontSize: 12)),
          const SizedBox(width: 6),
          Text('${_delayMs}ms', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
          Expanded(child: Slider(value: _delayMs.toDouble(), min: 0, max: 1000, divisions: 50, onChanged: (v) => setState(() => _delayMs = v.round()))),
        ]),
        const SizedBox(height: 6),
        // Templates
        const Text('快速模板', style: TextStyle(fontSize: 12)),
        const SizedBox(height: 4),
        Wrap(spacing: 4, runSpacing: 4, children: _templates.map((t) => _chip(t.$1, false, () => setState(() => _entries.addAll(t.$2)))).toList()),
        const SizedBox(height: 8),
        // Key categories
        ..._keyCategories.map((cat) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(cat.$1, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 11)),
          const SizedBox(height: 3),
          Wrap(spacing: 3, runSpacing: 3, children: cat.$2.map((key) => _chip(key, false, () => _addKey(key.toLowerCase()))).toList()),
          const SizedBox(height: 6),
        ])),
      ]))),
      actions: [FilledButton(onPressed: _entries.isEmpty ? null : _confirm, child: const Text('创建宏'))],
    );
  }

  Widget _keyChip(String key, VoidCallback onDelete) {
    final accent = FluentTheme.of(context).accentColor;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(color: accent.withOpacity(0.1), borderRadius: BorderRadius.circular(4), border: Border.all(color: accent.withOpacity(0.3))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(key.toUpperCase(), style: TextStyle(color: accent, fontWeight: FontWeight.w600, fontFamily: 'monospace', fontSize: 11)),
        const SizedBox(width: 3),
        GestureDetector(onTap: onDelete, child: Icon(FluentIcons.clear, size: 10, color: accent)),
      ]),
    );
  }
}

class _KeyEntry {
  final String key;
  final int delayMs;
  const _KeyEntry({required this.key, this.delayMs = 50});
}

// ─── Combo Builder Dialog ────────────────────────────────────

class _ComboBuilderDialog extends StatefulWidget {
  final Future<void> Function(String name, List<MacroEvent> events) onConfirm;
  const _ComboBuilderDialog({required this.onConfirm});
  @override
  State<_ComboBuilderDialog> createState() => _ComboBuilderDialogState();
}

class _ComboBuilderDialogState extends State<_ComboBuilderDialog> {
  final _nameCtrl = TextEditingController(text: '组合键宏');
  final List<String> _keys = [];

  static const _modifierKeys = ['Ctrl', 'Alt', 'Shift'];
  static const _regularCategories = <(String, List<String>)>[
    ('功能键', ['F1','F2','F3','F4','F5','F6','F7','F8','F9','F10','F11','F12']),
    ('编辑键', ['Space','Enter','Tab','Escape','Backspace','Delete','Insert']),
    ('方向键', ['Up','Down','Left','Right','Home','End','PageUp','PageDown']),
    ('数字', ['0','1','2','3','4','5','6','7','8','9']),
    ('字母', ['A','B','C','D','E','F','G','H','I','J','K','L','M','N','O','P','Q','R','S','T','U','V','W','X','Y','Z']),
  ];

  static const _comboTemplates = <(String, List<String>)>[
    ('Ctrl+C', ['ctrl', 'c']), ('Ctrl+V', ['ctrl', 'v']), ('Ctrl+Z', ['ctrl', 'z']),
    ('Ctrl+S', ['ctrl', 's']), ('Ctrl+A', ['ctrl', 'a']), ('Alt+F4', ['alt', 'f4']),
    ('Alt+Tab', ['alt', 'tab']), ('Ctrl+Shift+Esc', ['ctrl', 'shift', 'escape']),
  ];

  void _confirm() {
    if (_keys.isEmpty) return;
    final events = <MacroEvent>[];
    int ts = 0;
    for (final key in _keys) { events.add(MacroEvent(type: MacroEventType.keyPress, timestampMs: ts, key: key)); ts += 10; }
    ts += 50;
    for (final key in _keys.reversed) { events.add(MacroEvent(type: MacroEventType.keyRelease, timestampMs: ts, key: key)); ts += 10; }
    widget.onConfirm(_nameCtrl.text, events);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = FluentTheme.of(context).brightness == Brightness.dark;
    final accent = FluentTheme.of(context).accentColor;
    final containerBg = isDark ? const Color(0xFF303050) : const Color(0xFFF0F0F8);
    return ContentDialog(
      title: const Text('组合键构建器'),
      content: SizedBox(width: 440, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextBox(controller: _nameCtrl, placeholder: '宏名称'),
        const SizedBox(height: 10),
        // Combo display
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: containerBg, borderRadius: BorderRadius.circular(8)),
          child: _keys.isEmpty
            ? const Center(child: Text('点击下方按键添加组合', style: TextStyle(fontSize: 12)))
            : Wrap(spacing: 4, runSpacing: 4, children: [
                for (int i = 0; i < _keys.length; i++) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: accent.withOpacity(0.1), borderRadius: BorderRadius.circular(6), border: Border.all(color: accent.withOpacity(0.3))),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(_keys[i].toUpperCase(), style: TextStyle(color: accent, fontWeight: FontWeight.w600, fontFamily: 'monospace', fontSize: 12)),
                      const SizedBox(width: 3),
                      GestureDetector(onTap: () => setState(() => _keys.removeAt(i)), child: Icon(FluentIcons.clear, size: 10, color: accent)),
                    ]),
                  ),
                  if (i < _keys.length - 1) Text('+', style: TextStyle(fontWeight: FontWeight.bold, color: accent)),
                ],
              ]),
        ),
        const SizedBox(height: 8),
        // Templates
        const Text('常用组合', style: TextStyle(fontSize: 12)),
        const SizedBox(height: 4),
        Wrap(spacing: 4, runSpacing: 4, children: _comboTemplates.map((t) => _chip(t.$1, false, () => setState(() { _keys.clear(); _keys.addAll(t.$2); }))).toList()),
        const SizedBox(height: 8),
        // Modifier keys
        const Text('修饰键', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 11)),
        const SizedBox(height: 4),
        Wrap(spacing: 4, children: _modifierKeys.map((key) {
          final isAdded = _keys.contains(key.toLowerCase());
          return _chip(key, isAdded, () => setState(() { if (isAdded) {
            _keys.remove(key.toLowerCase());
          } else {
            _keys.add(key.toLowerCase());
          } }));
        }).toList()),
        const SizedBox(height: 8),
        // Regular keys
        ..._regularCategories.map((cat) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(cat.$1, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 11)),
          const SizedBox(height: 3),
          Wrap(spacing: 3, runSpacing: 3, children: cat.$2.map((key) => _chip(key, false, () => setState(() => _keys.add(key.toLowerCase())))).toList()),
          const SizedBox(height: 6),
        ])),
      ]))),
      actions: [FilledButton(onPressed: _keys.isEmpty ? null : _confirm, child: const Text('创建宏'))],
    );
  }
}

// ─── Text Type Builder Dialog ────────────────────────────────

class _TextTypeBuilderDialog extends StatefulWidget {
  final Future<void> Function(String name, List<MacroEvent> events) onConfirm;
  const _TextTypeBuilderDialog({required this.onConfirm});
  @override
  State<_TextTypeBuilderDialog> createState() => _TextTypeBuilderDialogState();
}

class _TextTypeBuilderDialogState extends State<_TextTypeBuilderDialog> {
  final _nameCtrl = TextEditingController(text: '自动打字宏');
  final _textCtrl = TextEditingController();
  int _charDelayMs = 50;

  static const _quickTexts = <(String, String)>[
    ('Hello World', 'Hello World!'), ('测试文本', '这是一段测试文本。'), ('数字序列', '1 2 3 4 5 6 7 8 9 10'),
    ('邮箱格式', 'user@example.com'), ('JSON模板', '{"key": "value"}'),
  ];

  void _confirm() {
    final text = _textCtrl.text;
    if (text.isEmpty) return;
    final events = <MacroEvent>[];
    int ts = 0;
    for (final c in text.split('')) {
      events.add(MacroEvent(type: MacroEventType.keyPress, timestampMs: ts, key: c));
      ts += 15;
      events.add(MacroEvent(type: MacroEventType.keyRelease, timestampMs: ts, key: c));
      ts += _charDelayMs;
    }
    widget.onConfirm(_nameCtrl.text, events);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = FluentTheme.of(context).brightness == Brightness.dark;
    final containerBg = isDark ? const Color(0xFF303050) : const Color(0xFFF0F0F8);
    return ContentDialog(
      title: const Text('自动打字宏'),
      content: SizedBox(width: 400, child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextBox(controller: _nameCtrl, placeholder: '宏名称'),
        const SizedBox(height: 10),
        TextBox(maxLines: 4, controller: _textCtrl, placeholder: '在此输入文本内容...'),
        const SizedBox(height: 10),
        Row(children: [
          const Text('速度:', style: TextStyle(fontSize: 12)),
          const SizedBox(width: 6),
          Text('${_charDelayMs}ms/字', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
          Expanded(child: Slider(value: _charDelayMs.toDouble(), min: 10, max: 500, divisions: 49, onChanged: (v) => setState(() => _charDelayMs = v.round()))),
        ]),
        const SizedBox(height: 6),
        const Text('快速填充', style: TextStyle(fontSize: 12)),
        const SizedBox(height: 4),
        Wrap(spacing: 4, runSpacing: 4, children: _quickTexts.map((t) => _chip(t.$1, false, () => setState(() => _textCtrl.text = t.$2))).toList()),
        if (_textCtrl.text.isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: containerBg, borderRadius: BorderRadius.circular(8)),
            child: Row(children: [
              Icon(FluentIcons.info, size: 14, color: FluentTheme.of(context).accentColor),
              const SizedBox(width: 6),
              Expanded(child: Text('将输入 ${_textCtrl.text.length} 个字符，预计耗时 ${_textCtrl.text.length * _charDelayMs}ms', style: const TextStyle(fontSize: 11))),
            ]),
          ),
        ],
      ])),
      actions: [FilledButton(onPressed: _textCtrl.text.isEmpty ? null : _confirm, child: const Text('创建宏'))],
    );
  }
}

// ─── Scroll Builder Dialog ───────────────────────────────────

class _ScrollBuilderDialog extends StatefulWidget {
  final Future<void> Function(String name, List<MacroEvent> events) onConfirm;
  const _ScrollBuilderDialog({required this.onConfirm});
  @override
  State<_ScrollBuilderDialog> createState() => _ScrollBuilderDialogState();
}

class _ScrollBuilderDialogState extends State<_ScrollBuilderDialog> {
  final _nameCtrl = TextEditingController(text: '滚轮宏');
  double _scrollDy = 3.0;
  int _scrollCount = 5;
  int _scrollIntervalMs = 100;

  static const _presets = <(String, double, int, int)>[
    ('向下5次', 3.0, 5, 100), ('向上5次', -3.0, 5, 100), ('快速向下10次', 5.0, 10, 50),
    ('缓慢向下3次', 1.0, 3, 300), ('翻页向下', 10.0, 3, 200), ('翻页向上', -10.0, 3, 200),
  ];

  void _confirm() {
    final events = <MacroEvent>[];
    int ts = 0;
    for (int i = 0; i < _scrollCount; i++) {
      events.add(MacroEvent(type: MacroEventType.scroll, timestampMs: ts, scrollDx: 0, scrollDy: _scrollDy));
      ts += _scrollIntervalMs;
    }
    widget.onConfirm(_nameCtrl.text, events);
  }

  @override
  Widget build(BuildContext context) {
    final direction = _scrollDy >= 0 ? '向下' : '向上';
    return ContentDialog(
      title: const Text('滚轮宏'),
      content: SizedBox(width: 400, child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextBox(controller: _nameCtrl, placeholder: '宏名称'),
        const SizedBox(height: 10),
        // Direction
        Row(children: [
          Expanded(child: _chip('向下滚动', _scrollDy >= 0, () => setState(() => _scrollDy = _scrollDy.abs()))),
          const SizedBox(width: 8),
          Expanded(child: _chip('向上滚动', _scrollDy < 0, () => setState(() => _scrollDy = -_scrollDy.abs()))),
        ]),
        const SizedBox(height: 10),
        // Amount
        Row(children: [
          const Text('滚动量:', style: TextStyle(fontSize: 12)),
          const SizedBox(width: 6),
          Text('${_scrollDy.abs().toStringAsFixed(1)} $direction', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
          Expanded(child: Slider(value: _scrollDy.abs(), min: 0.5, max: 20.0, divisions: 39, onChanged: (v) => setState(() => _scrollDy = _scrollDy < 0 ? -v : v))),
        ]),
        const SizedBox(height: 8),
        // Count & interval
        Row(children: [
          const Text('次数:', style: TextStyle(fontSize: 12)),
          const SizedBox(width: 6),
          SizedBox(width: 60, child: TextBox(
            controller: TextEditingController(text: _scrollCount.toString()),
            onChanged: (v) { final p = int.tryParse(v); if (p != null && p > 0) setState(() => _scrollCount = p); },
          )),
          const SizedBox(width: 12),
          const Text('间隔:', style: TextStyle(fontSize: 12)),
          const SizedBox(width: 6),
          SizedBox(width: 60, child: TextBox(
            controller: TextEditingController(text: _scrollIntervalMs.toString()),
            onChanged: (v) { final p = int.tryParse(v); if (p != null && p > 0) setState(() => _scrollIntervalMs = p); },
          )),
          const Text(' ms', style: TextStyle(fontSize: 11)),
        ]),
        const SizedBox(height: 8),
        // Presets
        const Text('快速预设', style: TextStyle(fontSize: 12)),
        const SizedBox(height: 4),
        Wrap(spacing: 4, runSpacing: 4, children: _presets.map((p) => _chip(p.$1, false, () => setState(() { _scrollDy = p.$2; _scrollCount = p.$3; _scrollIntervalMs = p.$4; }))).toList()),
      ])),
      actions: [FilledButton(onPressed: _confirm, child: const Text('创建宏'))],
    );
  }
}

// ─── Delay Builder Dialog ────────────────────────────────────

class _DelayBuilderDialog extends StatefulWidget {
  final Future<void> Function(String name, List<MacroEvent> events) onConfirm;
  const _DelayBuilderDialog({required this.onConfirm});
  @override
  State<_DelayBuilderDialog> createState() => _DelayBuilderDialogState();
}

class _DelayBuilderDialogState extends State<_DelayBuilderDialog> {
  final _nameCtrl = TextEditingController(text: '延时宏');
  int _delayMs = 1000;
  int _repeatCount = 1;
  bool _addKeyPress = false;
  String _keyToPress = 'space';

  static const _delayPresets = <(String, int)>[
    ('500ms', 500), ('1秒', 1000), ('2秒', 2000), ('3秒', 3000), ('5秒', 5000), ('10秒', 10000),
  ];

  void _confirm() {
    final events = <MacroEvent>[];
    int ts = 0;
    for (int i = 0; i < _repeatCount; i++) {
      if (_addKeyPress) {
        events.add(MacroEvent(type: MacroEventType.keyPress, timestampMs: ts, key: _keyToPress));
        ts += 20;
        events.add(MacroEvent(type: MacroEventType.keyRelease, timestampMs: ts, key: _keyToPress));
        ts += 50;
      }
      events.add(MacroEvent(type: MacroEventType.wait, timestampMs: ts));
      ts += _delayMs;
    }
    widget.onConfirm(_nameCtrl.text, events);
  }

  @override
  Widget build(BuildContext context) {
    final delayStr = _delayMs >= 1000 ? '${(_delayMs / 1000).toStringAsFixed(1)} 秒' : '$_delayMs 毫秒';
    final isDark = FluentTheme.of(context).brightness == Brightness.dark;
    final containerBg = isDark ? const Color(0xFF303050) : const Color(0xFFF0F0F8);
    return ContentDialog(
      title: const Text('延时宏'),
      content: SizedBox(width: 400, child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextBox(controller: _nameCtrl, placeholder: '宏名称'),
        const SizedBox(height: 10),
        // Delay
        Row(children: [const Text('等待时长:', style: TextStyle(fontSize: 13)), const SizedBox(width: 8), Text(delayStr, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))]),
        Slider(value: _delayMs.toDouble(), min: 100, max: 30000, divisions: 299, label: delayStr, onChanged: (v) => setState(() => _delayMs = v.round())),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text('100ms', style: TextStyle(fontSize: 11, color: FluentTheme.of(context).brightness == Brightness.dark ? const Color(0xFF707090) : const Color(0xFF9A9AAA))), Text('30s', style: TextStyle(fontSize: 11, color: FluentTheme.of(context).brightness == Brightness.dark ? const Color(0xFF707090) : const Color(0xFF9A9AAA)))]),
        const SizedBox(height: 8),
        // Presets
        Wrap(spacing: 4, runSpacing: 4, children: _delayPresets.map((p) => _chip(p.$1, _delayMs == p.$2, () => setState(() => _delayMs = p.$2))).toList()),
        const SizedBox(height: 10),
        // Repeat
        Row(children: [
          const Text('重复次数:', style: TextStyle(fontSize: 13)),
          const SizedBox(width: 8),
          SizedBox(width: 70, child: TextBox(
            controller: TextEditingController(text: _repeatCount.toString()),
            onChanged: (v) { final p = int.tryParse(v); if (p != null && p > 0) setState(() => _repeatCount = p); },
          )),
          const SizedBox(width: 8),
          const Text('(1=单次)', style: TextStyle(fontSize: 11)),
        ]),
        const SizedBox(height: 10),
        // Key press toggle
        Row(children: [
          const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('等待前按键', style: TextStyle(fontSize: 13)),
            Text('每次等待前先按一次键', style: TextStyle(fontSize: 11)),
          ])),
          ToggleSwitch(checked: _addKeyPress, onChanged: (v) => setState(() => _addKeyPress = v)),
        ]),
        if (_addKeyPress) ...[
          const SizedBox(height: 8),
          Row(children: [
            const Text('按键:', style: TextStyle(fontSize: 12)),
            const SizedBox(width: 6),
            Wrap(spacing: 4, children: ['Space', 'Enter', 'Tab', 'Escape', 'F5'].map((key) =>
              _chip(key, _keyToPress.toLowerCase() == key.toLowerCase(), () => setState(() => _keyToPress = key.toLowerCase()))
            ).toList()),
          ]),
        ],
        const SizedBox(height: 8),
        // Summary
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: containerBg, borderRadius: BorderRadius.circular(8)),
          child: Row(children: [
            const Icon(FluentIcons.timer, size: 14),
            const SizedBox(width: 6),
            Expanded(child: Text(
              _addKeyPress ? '每 $_delayMs ms 按一次 ${_keyToPress.toUpperCase()}，共 $_repeatCount 次' : '等待 $_delayMs ms，共 $_repeatCount 次',
              style: const TextStyle(fontSize: 11),
            )),
          ]),
        ),
      ])),
      actions: [FilledButton(onPressed: _confirm, child: const Text('创建宏'))],
    );
  }
}
