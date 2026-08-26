/// Mobile vision page — 图片识别：模板管理 / 找图测试 / 视觉连点 / OCR。
/// 原生层（截屏、NCC 匹配、OCR）已就绪，此页为移动端 UI 入口。
/// 视觉连点由原生线程驱动：切到其他应用后仍持续工作。
library;


import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/mobile_app_state.dart';
import '../../services/platform/android_input.dart';
import '../../services/screen_overlay_service.dart';
import '../../services/system_tray_service.dart';
import '../../services/vision_service.dart';
import '../../services/vision_template_store.dart';

class MobileVisionPage extends StatefulWidget {
  const MobileVisionPage({super.key});

  @override
  State<MobileVisionPage> createState() => MobileVisionPageState();
}

class MobileVisionPageState extends State<MobileVisionPage> {
  final _channel = MethodChannelProxy();

  List<VisionTemplate> _templates = [];
  String? _selectedId;
  bool _visionRunning = false;
  int _visionCount = 0;
  int _intervalMs = 500;
  int _maxCount = 0; // 0 = unlimited
  bool _accessibilityOk = true;
  bool _testing = false;
  String? _ocrText;
  bool _ocrLoading = false;

  @override
  void initState() {
    super.initState();
    _loadTemplates();
    checkAccessibility();
    _channel.register(_onNativeCall);
  }

  @override
  void dispose() {
    _channel.unregister();
    if (_visionRunning) {
      VisionService.instance.stopVisionClicker();
    }
    super.dispose();
  }

  Future<void> _loadTemplates() async {
    final list = await VisionTemplateStore.instance.loadAll();
    if (mounted) {
      setState(() {
        _templates = list;
        _selectedId ??= list.isNotEmpty ? list.first.id : null;
      });
    }
  }

  Future<void> checkAccessibility() async {
    final state = context.read<MobileAppState>();
    final input = state.platformInput;
    if (input is AndroidInput) {
      final ok = await input.isAccessibilityServiceEnabled();
      if (mounted) setState(() => _accessibilityOk = ok);
    }
  }

  void _onNativeCall(String method, dynamic args) {
    switch (method) {
      case 'onVisionClickerTick':
        final count = (args as Map?)?['count'] as int? ?? 0;
        if (mounted) setState(() => _visionCount = count);
        break;
      case 'onVisionClickerStopped':
        if (mounted) setState(() => _visionRunning = false);
        break;
    }
  }

  VisionTemplate? get _selectedTemplate {
    final id = _selectedId;
    if (id == null) return null;
    for (final t in _templates) {
      if (t.id == id) return t;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<MobileAppState>();
    final isDark = state.themeMode == 'dark';
    final accent = state.accentColor;

    return Scaffold(
      appBar: AppBar(
        title: const Text('图片识别'),
        centerTitle: true,
        backgroundColor: isDark ? const Color(0xFF1A1A2E) : accent.withValues(alpha: 0.1),
        foregroundColor: isDark ? Colors.white : accent,
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(Icons.document_scanner, color: isDark ? Colors.white : accent),
            tooltip: '全屏 OCR',
            onPressed: _ocrLoading ? null : _runOcr,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _captureTemplate,
        icon: const Icon(Icons.add_a_photo),
        label: const Text('截取模板'),
        backgroundColor: accent,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
        children: [
          if (!_accessibilityOk) ...[
            _accessibilityCard(state, accent, isDark),
            const SizedBox(height: 12),
          ],
          _visionClickerCard(state, accent, isDark),
          const SizedBox(height: 16),
          if (_ocrText != null || _ocrLoading) ...[
            _ocrCard(state, accent, isDark),
            const SizedBox(height: 16),
          ],
          _sectionTitle('模板库（${_templates.length}）', isDark),
          if (_templates.isEmpty)
            _emptyCard(isDark)
          else
            ..._templates.map((t) => _templateCard(t, state, accent, isDark)),
        ],
      ),
    );
  }

  // ─── 卡片 ─────────────────────────────────────────────────

  Widget _accessibilityCard(MobileAppState state, Color accent, bool isDark) {
    return Card(
      color: isDark ? const Color(0xFF2A2230) : const Color(0xFFFFF3E0),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          Icon(Icons.accessibility_new, color: Colors.orange.shade700, size: 22),
          const SizedBox(width: 10),
          Expanded(child: Text('无障碍服务未开启，视觉连点无法点击',
              style: TextStyle(fontSize: 13, color: isDark ? Colors.white70 : Colors.black87))),
          TextButton(
            onPressed: () async {
              final input = state.platformInput;
              if (input is AndroidInput) await input.openAccessibilitySettings();
            },
            child: Text('去开启', style: TextStyle(color: accent, fontWeight: FontWeight.w600)),
          ),
        ]),
      ),
    );
  }

  Widget _visionClickerCard(MobileAppState state, Color accent, bool isDark) {
    final tpl = _selectedTemplate;
    return Card(
      color: isDark ? const Color(0xFF22223A) : Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.center_focus_strong, color: accent, size: 20),
            const SizedBox(width: 8),
            Text('视觉连点', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : Colors.black87)),
            const Spacer(),
            if (_visionRunning)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF00E676).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('已点击 $_visionCount 次',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                        color: Color(0xFF00E676))),
              ),
          ]),
          const SizedBox(height: 10),
          if (_templates.isEmpty)
            Text('先截取一个模板', style: TextStyle(fontSize: 13,
                color: isDark ? Colors.grey : Colors.black54))
          else ...[
            // 模板选择
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: _templates.take(6).map((t) {
                final selected = t.id == _selectedId;
                return GestureDetector(
                  onTap: () => setState(() => _selectedId = t.id),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: selected ? accent.withValues(alpha: 0.15) : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: selected ? accent : (isDark ? const Color(0xFF404060) : const Color(0xFFD0D0E0))),
                    ),
                    child: Text(t.name, style: TextStyle(fontSize: 12,
                        color: selected ? accent : (isDark ? Colors.grey : Colors.black54),
                        fontWeight: selected ? FontWeight.w600 : FontWeight.normal)),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 10),
            // 间隔
            Row(children: [
              Text('间隔', style: TextStyle(fontSize: 13, color: isDark ? Colors.white70 : Colors.black87)),
              const SizedBox(width: 10),
              Expanded(child: Slider(
                value: _intervalMs.clamp(100, 5000).toDouble(),
                min: 100, max: 5000,
                activeColor: accent,
                onChanged: (v) => setState(() => _intervalMs = v.round()),
              )),
              Text('$_intervalMs ms', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white70 : Colors.black87)),
            ]),
            const SizedBox(height: 10),
            // 最多点击次数 (0 = 无限)
            Row(children: [
              Text('最多点击', style: TextStyle(fontSize: 13, color: isDark ? Colors.white70 : Colors.black87)),
              const Spacer(),
              DropdownButton<int>(
                value: _maxCount,
                isDense: true,
                underline: const SizedBox(),
                dropdownColor: isDark ? const Color(0xFF2A2A3E) : Colors.white,
                items: [0, 50, 100, 200, 500, 1000].map((n) => DropdownMenuItem(
                  value: n,
                  child: Text(n == 0 ? '无限' : '$n 次',
                      style: TextStyle(fontSize: 13, color: isDark ? Colors.white : Colors.black87)),
                )).toList(),
                onChanged: (v) => setState(() => _maxCount = v ?? 0),
              ),
            ]),
          ],
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: FilledButton(
              onPressed: (tpl == null || _testing) ? null : (_visionRunning ? _stopVision : () => _startVision(tpl)),
              style: FilledButton.styleFrom(
                backgroundColor: _visionRunning ? Colors.red : accent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: Text(_visionRunning ? '停止' : '开始找图即点',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _ocrCard(MobileAppState state, Color accent, bool isDark) {
    return Card(
      color: isDark ? const Color(0xFF22223A) : Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.document_scanner, color: accent, size: 20),
            const SizedBox(width: 8),
            Text('OCR 识别结果', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : Colors.black87)),
            const Spacer(),
            IconButton(
              icon: Icon(Icons.close, size: 16, color: isDark ? Colors.grey : Colors.black45),
              onPressed: () => setState(() => _ocrText = null),
            ),
          ]),
          const SizedBox(height: 4),
          Text(_ocrLoading ? '识别中…' : (_ocrText ?? ''),
              style: TextStyle(fontSize: 13, height: 1.5,
                  color: isDark ? Colors.white70 : Colors.black87)),
        ]),
      ),
    );
  }

  Widget _emptyCard(bool isDark) {
    return Card(
      color: isDark ? const Color(0xFF22223A) : Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 28),
        child: Column(children: [
          Icon(Icons.image_search, size: 40, color: isDark ? Colors.grey.shade700 : Colors.grey.shade400),
          const SizedBox(height: 10),
          Text('还没有模板', style: TextStyle(fontSize: 14, color: isDark ? Colors.grey : Colors.black54)),
          const SizedBox(height: 4),
          Text('点击下方按钮截取屏幕区域作为模板', style: TextStyle(fontSize: 12, color: isDark ? Colors.grey : Colors.black45)),
        ]),
      ),
    );
  }

  Widget _templateCard(VisionTemplate t, MobileAppState state, Color accent, bool isDark) {
    return Card(
      color: isDark ? const Color(0xFF22223A) : Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(children: [
          Row(children: [
            // 缩略图
            Container(
              width: 52, height: 52,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: isDark ? const Color(0xFF404060) : const Color(0xFFD0D0E0)),
              ),
              clipBehavior: Clip.antiAlias,
              child: Image.memory(t.toBmp(), fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => Icon(Icons.broken_image, size: 20, color: Colors.grey.shade600)),
            ),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t.name, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : Colors.black87)),
              const SizedBox(height: 2),
              Text('${t.width}×${t.height} · 阈值 ${t.threshold.toStringAsFixed(2)}',
                  style: TextStyle(fontSize: 11, color: isDark ? Colors.grey : Colors.black54)),
            ])),
            // 测试查找
            _testing
                ? const SizedBox(width: 20, height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : IconButton(
                    icon: Icon(Icons.travel_explore, size: 20, color: accent),
                    tooltip: '测试查找',
                    onPressed: () => _testFind(t),
                  ),
            IconButton(
              icon: Icon(Icons.delete_outline, size: 20, color: Colors.red.withValues(alpha: 0.7)),
              tooltip: '删除',
              onPressed: () => _deleteTemplate(t),
            ),
          ]),
          const SizedBox(height: 6),
          // 阈值调节
          Row(children: [
            Text('阈值', style: TextStyle(fontSize: 12, color: isDark ? Colors.grey : Colors.black54)),
            Expanded(child: Slider(
              value: t.threshold,
              min: 0.5, max: 1.0,
              activeColor: accent,
              onChanged: (v) async {
                setState(() => t.threshold = v);
                await VisionTemplateStore.instance.save(t);
              },
            )),
            Text(t.threshold.toStringAsFixed(2),
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white70 : Colors.black87)),
          ]),
        ]),
      ),
    );
  }

  // ─── 操作 ─────────────────────────────────────────────────

  Future<void> _captureTemplate() async {
    // 区域选择覆盖层 → 截屏取模板
    final area = await ScreenOverlayService.instance.startAreaSelect();
    if (area == null) return;
    final (x1, y1, x2, y2) = area;
    final w = x2 - x1, h = y2 - y1;
    if (w < 8 || h < 8) {
      _toast('区域太小');
      return;
    }
    // 触发截屏（首次会弹系统授权）
    final tpl = await VisionService.instance.captureTemplate(x1, y1, w, h);
    if (tpl == null) {
      _toast('截屏失败，请重试');
      return;
    }
    // 命名保存
    final name = await _promptName(context);
    if (name == null || name.isEmpty) return;
    final t = VisionTemplate(
      id: 'tpl_${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      width: tpl.width,
      height: tpl.height,
      pixels: tpl.pixels,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
    await VisionTemplateStore.instance.save(t);
    await _loadTemplates();
    if (mounted) setState(() => _selectedId = t.id);
    _toast('模板已保存');
  }

  Future<String?> _promptName(BuildContext context) {
    final ctrl = TextEditingController(text: '模板${_templates.length + 1}');
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('模板命名'),
        content: TextField(controller: ctrl, autofocus: true,
            decoration: const InputDecoration(hintText: '模板名称')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('保存')),
        ],
      ),
    );
  }

  Future<void> _testFind(VisionTemplate t) async {
    setState(() => _testing = true);
    try {
      final size = await VisionService.instance.getScreenSize();
      final w = size?.width ?? 1080;
      final h = size?.height ?? 1920;
      final match = await VisionService.instance.findImage(
        regionX: 0, regionY: 0, regionW: w, regionH: h,
        template: TemplateData(pixels: t.pixels, width: t.width, height: t.height),
        threshold: t.threshold,
      );
      if (!mounted) return;
      if (match != null) {
        _toast('找到：(${match.centerX}, ${match.centerY}) 相似度 ${match.score.toStringAsFixed(2)}');
      } else {
        _toast('未找到匹配');
      }
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _startVision(VisionTemplate t) async {
    // 无障碍检查
    final state = context.read<MobileAppState>();
    final input = state.platformInput;
    if (input is AndroidInput) {
      final ok = await input.isAccessibilityServiceEnabled();
      if (!ok) {
        setState(() => _accessibilityOk = false);
        _toast('请先开启无障碍服务');
        return;
      }
    }
    // 截屏授权检查 — 主动请求，不再依赖"测试查找"触发
    if (!await VisionService.instance.isScreenCaptureAvailable()) {
      final granted = await VisionService.instance.requestScreenCapture();
      if (!granted) {
        _toast('请先授权屏幕录制权限');
        return;
      }
      // Wait for the foreground service to initialise MediaProjection
      await Future.delayed(const Duration(milliseconds: 800));
    }
    final ok = await VisionService.instance.startVisionClicker(
      template: TemplateData(pixels: t.pixels, width: t.width, height: t.height),
      threshold: t.threshold,
      intervalMs: _intervalMs,
      maxCount: _maxCount,
    );
    if (ok) {
      setState(() {
        _visionRunning = true;
        _visionCount = 0;
      });
      _toast('已启动，切换到目标应用即可');
    } else {
      _toast('启动失败：请先截屏授权（用"测试查找"触发一次）');
    }
  }

  Future<void> _runOcr() async {
    setState(() => _ocrLoading = true);
    try {
      final size = await VisionService.instance.getScreenSize();
      final w = size?.width ?? 1080;
      final h = size?.height ?? 1920;
      final result = await VisionService.instance.ocrRegion(x: 0, y: 0, w: w, h: h);
      if (!mounted) return;
      setState(() {
        _ocrLoading = false;
        if (result == null) {
          _ocrText = '识别失败：请先截屏授权（用"测试查找"触发一次）';
        } else if (result.hasError) {
          _ocrText = result.error;
        } else if (!result.hasText) {
          _ocrText = '未识别到文字';
        } else {
          _ocrText = result.text;
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _ocrLoading = false;
          _ocrText = '识别失败：$e';
        });
      }
    }
  }

  Future<void> _stopVision() async {
    await VisionService.instance.stopVisionClicker();
    setState(() => _visionRunning = false);
  }

  Future<void> _deleteTemplate(VisionTemplate t) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除模板'),
        content: Text('确定删除"${t.name}"？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('删除')),
        ],
      ),
    );
    if (confirmed == true) {
      await VisionTemplateStore.instance.delete(t.id);
      if (_selectedId == t.id) _selectedId = null;
      await _loadTemplates();
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));
  }

  Widget _sectionTitle(String title, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
          color: isDark ? const Color(0xFF9090B0) : const Color(0xFF6A6A80))),
    );
  }
}

/// MethodChannel 回调注册代理 — 复用 SystemTrayService 的外部处理器注册表
class MethodChannelProxy {
  VoidCallback? _unregister;

  void register(void Function(String method, dynamic args) onCall) {
    _unregister?.call();
    _unregister = SystemTrayService().registerExternalHandler((call) async {
      onCall(call.method, call.arguments);
      return null;
    });
  }

  void unregister() {
    _unregister?.call();
    _unregister = null;
  }
}
