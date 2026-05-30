library;

import 'dart:io';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'package:archive/archive.dart';
import '../../services/app_state.dart';
import '../../services/app_paths.dart';

class AiTrackerPage extends StatefulWidget {
  const AiTrackerPage({super.key});

  @override
  State<AiTrackerPage> createState() => _AiTrackerPageState();
}

class _AiTrackerPageState extends State<AiTrackerPage> {
  bool _checking = true;
  bool _downloading = false;
  String _downloadStatus = '';
  double _downloadProgress = 0;
  String _downloadSize = '';
  String _errorMsg = '';
  String _currentSource = 'GitHub';

  bool _onnxExists = false;
  bool _modelExists = false;

  String _pluginDir = '';

  static const _ortVersion = '1.21.0';
  static const _ortGithubUrl =
      'https://github.com/microsoft/onnxruntime/releases/download/v$_ortVersion/onnxruntime-win-x64-$_ortVersion.zip';
  static const _modelGithubUrl =
      'https://github.com/ultralytics/assets/releases/download/v8.4.0/yolo11n.onnx';

  static const _mirrors = <String, String>{
    'GitHub': '',
    'ghfast.top': 'https://ghfast.top/',
    'gh-proxy.com': 'https://gh-proxy.com/',
    'ghproxy.net': 'https://ghproxy.net/',
  };

  String _selectedMirror = 'GitHub';

  @override
  void initState() {
    super.initState();
    _checkDependencies();
  }

  Future<String> _getPluginDir() async {
    final path = await AppPaths.getPluginDir('ai_tracker');
    final dir = Directory(path);
    if (!await dir.exists()) await dir.create(recursive: true);
    return path;
  }

  bool _dllDeployed = false;

  Future<void> _checkDependencies() async {
    setState(() => _checking = true);
    final dir = await _getPluginDir();
    _pluginDir = dir;

    _onnxExists = await File('$dir\\onnxruntime.dll').exists();
    _modelExists = await File('$dir\\models\\yolo11n.onnx').exists();
    _dllDeployed = await _deployNativePlugin();

    setState(() => _checking = false);
  }

  Future<bool> _deployNativePlugin() async {
    final dir = _pluginDir;
    final windowsDir = Directory('$dir\\windows');
    if (!await windowsDir.exists()) await windowsDir.create(recursive: true);

    final exePath = Platform.resolvedExecutable;
    final exeDir = File(exePath).parent.path;

    final pluginDir = await AppPaths.getPluginDir('ai_tracker');

    final dllDest = File('$dir\\windows\\ai_tracker.dll');
    final manifestDest = File('$dir\\manifest.json');

    final dllSources = [
      '$exeDir\\plugins\\ai_tracker\\windows\\ai_tracker.dll',
      '$exeDir\\data\\plugins\\ai_tracker\\windows\\ai_tracker.dll',
      '$pluginDir\\windows\\ai_tracker.dll',
    ];

    final manifestSources = [
      '$exeDir\\plugins\\ai_tracker\\manifest.json',
      '$exeDir\\data\\plugins\\ai_tracker\\manifest.json',
      '$pluginDir\\manifest.json',
    ];

    bool dllOk = await dllDest.exists();
    bool manifestOk = await manifestDest.exists();

    if (!dllOk) {
      for (final src in dllSources) {
        final srcFile = File(src);
        if (await srcFile.exists()) {
          try {
            await srcFile.copy(dllDest.path);
            dllOk = true;
            break;
          } catch (_) {}
        }
      }
    }

    if (!manifestOk) {
      for (final src in manifestSources) {
        final srcFile = File(src);
        if (await srcFile.exists()) {
          try {
            await srcFile.copy(manifestDest.path);
            manifestOk = true;
            break;
          } catch (_) {}
        }
      }
    }

    return dllOk && manifestOk;
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Future<String> _resolveUrl(String url) async {
    if (_selectedMirror != 'GitHub') return url;

    final client = http.Client();
    try {
      final request = http.Request('GET', Uri.parse(url));
      request.followRedirects = false;
      final response = await client.send(request);

      if (response.statusCode == 302 || response.statusCode == 301) {
        final location = response.headers['location'];
        if (location != null) return location;
      }

      return url;
    } finally {
      client.close();
    }
  }

  Future<void> _downloadWithProgress({
    required String url,
    required String savePath,
    required String label,
  }) async {
    final client = http.Client();
    try {
      final request = http.Request('GET', Uri.parse(url));
      request.followRedirects = true;
      final response = await client.send(request);

      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}');
      }

      final total = response.contentLength ?? 0;
      int received = 0;
      final sink = File(savePath).openWrite();

      await response.stream.forEach((chunk) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) {
          final progress = received / total;
          setState(() {
            _downloadProgress = progress;
            _downloadSize = '${_formatBytes(received)} / ${_formatBytes(total)}';
            _downloadStatus = '$label ${_formatBytes(received)} / ${_formatBytes(total)}';
          });
        } else {
          setState(() {
            _downloadSize = _formatBytes(received);
            _downloadStatus = '$label ${_formatBytes(received)}';
          });
        }
      });

      await sink.close();

      final file = File(savePath);
      if (!await file.exists()) throw Exception('文件保存失败');
      final fileSize = await file.length();
      if (fileSize < 1024) {
        try {
          final content = await file.readAsString();
          if (content.contains('<!DOCTYPE') || content.contains('<html')) {
            await file.delete();
            throw Exception('下载到的是网页而非文件，可能链接已失效');
          }
        } catch (e) {
          if (e.toString().contains('网页而非文件')) rethrow;
        }
        throw Exception('文件过小(${_formatBytes(fileSize)})，下载可能不完整');
      }
    } finally {
      client.close();
    }
  }

  Future<String> _tryDownloadWithFallback({
    required String githubUrl,
    required String savePath,
    required String label,
  }) async {
    final mirrors = _mirrors.keys.toList();
    final startIndex = mirrors.indexOf(_selectedMirror);
    final order = startIndex >= 0
        ? [...mirrors.sublist(startIndex), ...mirrors.sublist(0, startIndex)]
        : mirrors;

    String? lastError;

    for (final mirror in order) {
      final prefix = _mirrors[mirror] ?? '';
      final url = prefix.isEmpty ? githubUrl : '$prefix$githubUrl';

      setState(() {
        _currentSource = mirror;
        _downloadStatus = '$label [源: $mirror]';
      });

      try {
        final realUrl = await _resolveUrl(url);
        await _downloadWithProgress(
          url: realUrl,
          savePath: savePath,
          label: '$label [源: $mirror]',
        );
        setState(() => _selectedMirror = mirror);
        return mirror;
      } catch (e) {
        lastError = e.toString().replaceFirst('Exception: ', '');
        final file = File(savePath);
        if (await file.exists()) {
          try { await file.delete(); } catch (_) {}
        }
        if (mirror != order.last) {
          setState(() {
            _downloadStatus = '源 $mirror 失败，尝试下一个镜像...';
          });
          await Future.delayed(const Duration(milliseconds: 500));
        }
      }
    }

    throw Exception('所有下载源均失败，最后一个错误: $lastError');
  }

  Future<void> _extractZip(String zipPath, String destDir) async {
    final bytes = await File(zipPath).readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);

    for (final file in archive) {
      final filePath = '$destDir\\${file.name}';
      if (file.isFile) {
        final outFile = File(filePath);
        await outFile.parent.create(recursive: true);
        await outFile.writeAsBytes(file.content as List<int>);
      } else {
        await Directory(filePath).create(recursive: true);
      }
    }
  }

  Future<File?> _findFileRecursive(Directory dir, String fileName) async {
    if (!await dir.exists()) return null;
    try {
      await for (final entity in dir.list(recursive: true)) {
        if (entity is File && entity.path.endsWith('\\$fileName')) {
          return entity;
        }
      }
    } catch (_) {}
    return null;
  }

  Future<void> _downloadOnnxRuntime() async {
    setState(() {
      _downloading = true;
      _downloadProgress = 0;
      _downloadSize = '';
      _errorMsg = '';
    });

    try {
      final dir = await _getPluginDir();
      final tempDir = await AppPaths.getTempDir();
      final zipPath = '$tempDir\\onnxruntime.zip';

      await _tryDownloadWithFallback(
        githubUrl: _ortGithubUrl,
        savePath: zipPath,
        label: '正在下载 ONNX Runtime v$_ortVersion',
      );

      setState(() {
        _downloadStatus = '正在解压 ONNX Runtime...';
        _downloadProgress = 0;
      });

      final extractDir = '$tempDir\\ort_extract';
      await _extractZip(zipPath, extractDir);

      final dllFile = await _findFileRecursive(Directory(extractDir), 'onnxruntime.dll');
      if (dllFile == null) {
        throw Exception('onnxruntime.dll 未找到，解压目录中无此文件');
      }

      await dllFile.copy('$dir\\onnxruntime.dll');
      _onnxExists = true;

      try { await File(zipPath).delete(); } catch (_) {}
      try { await Directory(extractDir).delete(recursive: true); } catch (_) {}

      _downloadStatus = 'ONNX Runtime 安装完成';
    } catch (e) {
      _errorMsg = e.toString().replaceFirst('Exception: ', '');
      _downloadStatus = '安装失败';
    }

    setState(() => _downloading = false);
  }

  Future<void> _downloadModel() async {
    setState(() {
      _downloading = true;
      _downloadProgress = 0;
      _downloadSize = '';
      _errorMsg = '';
    });

    try {
      final dir = await _getPluginDir();
      final modelsDir = Directory('$dir\\models');
      if (!await modelsDir.exists()) await modelsDir.create(recursive: true);

      await _tryDownloadWithFallback(
        githubUrl: _modelGithubUrl,
        savePath: '$dir\\models\\yolo11n.onnx',
        label: '正在下载 YOLO11n 模型',
      );
      _modelExists = true;
      _downloadStatus = 'YOLO11n 模型下载完成';
    } catch (e) {
      _errorMsg = e.toString().replaceFirst('Exception: ', '');
      _downloadStatus = '下载失败';
    }

    setState(() => _downloading = false);
  }

  Future<void> _downloadAll() async {
    if (!_onnxExists) await _downloadOnnxRuntime();
    if (!_modelExists && _errorMsg.isEmpty) await _downloadModel();
    setState(() {});
  }

  Future<void> _uninstallAll() async {
    setState(() {
      _downloading = true;
      _downloadStatus = '正在卸载...';
      _errorMsg = '';
    });

    try {
      final dir = Directory(_pluginDir);
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
      _onnxExists = false;
      _modelExists = false;
      _dllDeployed = false;
      _downloadStatus = '已卸载全部组件';
    } catch (e) {
      _errorMsg = e.toString().replaceFirst('Exception: ', '');
      _downloadStatus = '卸载失败';
    }

    setState(() => _downloading = false);
  }

  Future<void> _openPluginDir() async {
    final dir = Directory(_pluginDir);
    if (!await dir.exists()) await dir.create(recursive: true);
    await Process.run('explorer', [_pluginDir]);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final isDark = FluentTheme.of(context).brightness == Brightness.dark;
    final accent = state.accentColor;
    final allReady = _onnxExists && _modelExists;

    return ScaffoldPage.scrollable(
      padding: const EdgeInsets.all(20),
      children: [
        Row(children: [
          Icon(FluentIcons.machine_learning, size: 20, color: accent),
          const SizedBox(width: 10),
          const Text('AI图像跟踪', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          const Spacer(),
          if (allReady)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0x1F00E676),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text('就绪', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF00E676))),
            ),
        ]),
        const SizedBox(height: 20),

        if (_checking)
          const Center(child: ProgressRing())
        else ...[
          _buildSection('下载源', isDark, [
            Row(children: [
              Text('当前源: ', style: TextStyle(fontSize: 12, color: isDark ? const Color(0xFF9090B0) : const Color(0xFF8A8A9A))),
              ..._mirrors.keys.map((name) {
                final isSelected = _selectedMirror == name;
                final bgColor = isSelected
                  ? accent.withValues(alpha: 0.15)
                  : Colors.transparent;
                final textColor = isSelected
                  ? accent
                  : (isDark ? const Color(0xFF9090B0) : const Color(0xFF8A8A9A));
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Button(
                    onPressed: _downloading ? null : () => setState(() => _selectedMirror = name),
                    style: ButtonStyle(
                      backgroundColor: WidgetStatePropertyAll(bgColor),
                      padding: WidgetStatePropertyAll(const EdgeInsets.symmetric(horizontal: 10, vertical: 4)),
                    ),
                    child: Text(name, style: TextStyle(
                      fontSize: 11,
                      color: textColor,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                    )),
                  ),
                );
              }),
            ]),
            const SizedBox(height: 4),
            Text(
              _selectedMirror == 'GitHub'
                ? '直连 GitHub，海外网络推荐'
                : '通过国内镜像加速，国内网络推荐',
              style: TextStyle(fontSize: 10, color: isDark ? const Color(0xFF707090) : const Color(0xFFA0A0B0)),
            ),
          ]),

          _buildSection('依赖项', isDark, [
            _buildDepCard(
              icon: FluentIcons.processing,
              name: 'ONNX Runtime v$_ortVersion',
              desc: 'Microsoft 推理引擎 · ~200MB',
              installed: _onnxExists,
              isDark: isDark,
              accent: accent,
              onInstall: _downloading ? null : _downloadOnnxRuntime,
            ),
            _buildDepCard(
              icon: FluentIcons.machine_learning,
              name: 'YOLO11n 模型',
              desc: 'Ultralytics 目标检测模型 · ~6MB',
              installed: _modelExists,
              isDark: isDark,
              accent: accent,
              onInstall: _downloading ? null : _downloadModel,
            ),
          ]),

          const SizedBox(height: 16),

          Row(children: [
            if (!allReady)
              FilledButton(
                onPressed: _downloading ? null : _downloadAll,
                style: ButtonStyle(
                  backgroundColor: WidgetStatePropertyAll(accent.withValues(alpha: 0.15)),
                  padding: WidgetStatePropertyAll(const EdgeInsets.symmetric(horizontal: 20, vertical: 10)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(FluentIcons.download, size: 14, color: accent),
                  const SizedBox(width: 8),
                  Text('一键安装全部', style: TextStyle(color: accent, fontSize: 13, fontWeight: FontWeight.w600)),
                ]),
              ),
            if (allReady) ...[
              FilledButton(
                onPressed: _downloading ? null : _uninstallAll,
                style: ButtonStyle(
                  backgroundColor: WidgetStatePropertyAll(Color(0x1FFF0000)),
                  padding: WidgetStatePropertyAll(const EdgeInsets.symmetric(horizontal: 20, vertical: 10)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(FluentIcons.delete, size: 14, color: const Color(0xCCFF0000)),
                  const SizedBox(width: 8),
                  Text('卸载全部组件', style: const TextStyle(color: Color(0xCCFF0000), fontSize: 13, fontWeight: FontWeight.w600)),
                ]),
              ),
            ],
          ]),

          if (_downloading || _downloadStatus.isNotEmpty) ...[
            const SizedBox(height: 16),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_downloadStatus, style: TextStyle(fontSize: 12, color: isDark ? const Color(0xFF9090B0) : const Color(0xFF8A8A9A))),
              if (_downloading) ...[
                const SizedBox(height: 6),
                ProgressBar(value: _downloadProgress * 100),
                if (_downloadSize.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(_downloadSize, style: TextStyle(fontSize: 10, color: isDark ? const Color(0xFF707090) : const Color(0xFFA0A0B0))),
                  ),
              ],
              if (_errorMsg.isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0x14FF0000),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0x4DFF0000)),
                  ),
                  child: Text(_errorMsg, style: const TextStyle(fontSize: 11, color: Color(0xFFFF0000))),
                ),
              ],
            ]),
          ],

          const SizedBox(height: 20),

          _buildSection('插件目录', isDark, [
            Button(
              onPressed: _openPluginDir,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(FluentIcons.folder_open, size: 12, color: accent),
                const SizedBox(width: 6),
                Text('打开目录', style: TextStyle(fontSize: 12, color: accent)),
              ]),
            ),
            const SizedBox(height: 6),
            Text(_pluginDir, style: TextStyle(fontSize: 11, color: isDark ? const Color(0xFF707090) : const Color(0xFFA0A0B0))),
          ]),

          if (allReady) ...[
            const SizedBox(height: 20),
            _buildSection('使用说明', isDark, [
              _buildInfoRow('1. 在图像识别页面选择「AI检测」模式', isDark),
              _buildInfoRow('2. 设置目标类别（如 person、car、cell phone）', isDark),
              _buildInfoRow('3. 设置置信度阈值（默认 0.5）', isDark),
              _buildInfoRow('4. 点击开始，自动检测并点击目标', isDark),
            ]),
          ],
        ],
      ],
    );
  }

  Widget _buildSection(String title, bool isDark, List<Widget> children) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700,
        color: isDark ? const Color(0xFFC0C0E8) : const Color(0xFF5A5A80))),
      const SizedBox(height: 8),
      ...children,
      const SizedBox(height: 8),
    ]);
  }

  Widget _buildDepCard({
    required IconData icon,
    required String name,
    required String desc,
    required bool installed,
    required bool isDark,
    required Color accent,
    required VoidCallback? onInstall,
  }) {
    final cardBg = isDark ? const Color(0x80252540) : const Color(0x80F0F0FA);
    final activeColor = installed ? accent : (isDark ? const Color(0xFF606080) : const Color(0xFFB0B0C0));

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
            child: Icon(icon, size: 14, color: activeColor),
          ),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(name, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13,
                color: installed ? null : (isDark ? const Color(0xFF606080) : const Color(0xFFB0B0C0)))),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: installed
                    ? const Color(0x1F00E676)
                    : const Color(0x1FFF9800),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(installed ? '已安装' : '未安装',
                  style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600,
                    color: installed ? const Color(0xFF00E676) : const Color(0xFFFF9800))),
              ),
            ]),
            const SizedBox(height: 2),
            Text(desc, style: TextStyle(fontSize: 11, color: isDark ? const Color(0xFF9090B0) : const Color(0xFF8A8A9A))),
          ])),
          if (!installed)
            Button(
              onPressed: onInstall,
              style: ButtonStyle(
                padding: WidgetStatePropertyAll(const EdgeInsets.symmetric(horizontal: 10, vertical: 4)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(FluentIcons.download, size: 10, color: accent),
                const SizedBox(width: 4),
                Text('下载', style: TextStyle(fontSize: 11, color: accent)),
              ]),
            ),
        ]),
      ),
    );
  }

  Widget _buildInfoRow(String text, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Text(text, style: TextStyle(fontSize: 12, color: isDark ? const Color(0xFF9090B0) : const Color(0xFF8A8A9A))),
    );
  }
}
