/// 视觉模板存储 — 移动端图片识别的模板库。
/// 模板 = 屏幕截图区域的原始 BGRA 像素 + 尺寸 + 匹配阈值，
/// 持久化为 data/templates/{id}.json（像素 base64 压缩）。
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'app_paths.dart';

class VisionTemplate {
  final String id;
  String name;
  final int width;
  final int height;
  final Uint8List pixels; // BGRA
  double threshold;
  final int createdAt;

  VisionTemplate({
    required this.id,
    required this.name,
    required this.width,
    required this.height,
    required this.pixels,
    this.threshold = 0.85,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'width': width,
        'height': height,
        'threshold': threshold,
        'createdAt': createdAt,
        'pixels': base64Encode(pixels),
      };

  factory VisionTemplate.fromJson(Map<String, dynamic> json) =>
      VisionTemplate(
        id: json['id'] as String,
        name: json['name'] as String? ?? '未命名',
        width: json['width'] as int,
        height: json['height'] as int,
        pixels: base64Decode(json['pixels'] as String),
        threshold: (json['threshold'] as num?)?.toDouble() ?? 0.85,
        createdAt: json['createdAt'] as int? ?? 0,
      );

  /// BGRA → BMP 编码（用于缩略图显示，Flutter 原生支持 BMP 解码）
  Uint8List toBmp() {
    final rowSize = (width * 3 + 3) & ~3; // BGR 行按 4 字节对齐
    final dataSize = rowSize * height;
    final fileSize = 54 + dataSize;
    final b = ByteData(fileSize);
    // BITMAPFILEHEADER
    b.setUint8(0, 0x42); b.setUint8(1, 0x4D);
    b.setUint32(2, fileSize, Endian.little);
    b.setUint32(10, 54, Endian.little);
    // BITMAPINFOHEADER
    b.setUint32(14, 40, Endian.little);
    b.setUint32(18, width, Endian.little);
    b.setUint32(22, height, Endian.little);
    b.setUint16(26, 1, Endian.little);
    b.setUint16(28, 24, Endian.little);
    b.setUint32(34, dataSize, Endian.little);
    // 像素（BMP 自底向上，BGR 顺序）
    final out = b.buffer.asUint8List();
    for (var y = 0; y < height; y++) {
      final srcRow = (height - 1 - y) * width * 4;
      final dstRow = 54 + y * rowSize;
      for (var x = 0; x < width; x++) {
        final s = srcRow + x * 4;
        final d = dstRow + x * 3;
        out[d] = pixels[s];     // B
        out[d + 1] = pixels[s + 1]; // G
        out[d + 2] = pixels[s + 2]; // R
      }
    }
    return out;
  }
}

class VisionTemplateStore {
  VisionTemplateStore._();
  static final VisionTemplateStore instance = VisionTemplateStore._();

  String? _dir;
  final Map<String, VisionTemplate> _cache = {};

  Future<String> _ensureDir() async {
    if (_dir != null) return _dir!;
    final dataDir = await AppPaths.getDataDir();
    final dir = Directory('$dataDir${AppPaths.sep}templates');
    if (!await dir.exists()) await dir.create(recursive: true);
    _dir = dir.path;
    return _dir!;
  }

  /// 加载全部模板（按创建时间倒序）
  Future<List<VisionTemplate>> loadAll() async {
    final dir = await _ensureDir();
    final list = <VisionTemplate>[];
    for (final f in Directory(dir).listSync().whereType<File>()) {
      if (!f.path.endsWith('.json')) continue;
      try {
        final t = VisionTemplate.fromJson(
            jsonDecode(await f.readAsString()) as Map<String, dynamic>);
        _cache[t.id] = t;
        list.add(t);
      } catch (_) {}
    }
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  Future<void> save(VisionTemplate t) async {
    final dir = await _ensureDir();
    _cache[t.id] = t;
    await File('$dir${AppPaths.sep}${t.id}.json')
        .writeAsString(jsonEncode(t.toJson()));
  }

  Future<void> delete(String id) async {
    final dir = await _ensureDir();
    _cache.remove(id);
    final f = File('$dir${AppPaths.sep}$id.json');
    if (await f.exists()) await f.delete();
  }
}
