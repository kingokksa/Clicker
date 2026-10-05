import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';

import 'system_tray_service.dart';
import 'vision_service.dart';

class ImageImportService {
  ImageImportService._();
  static final ImageImportService instance = ImageImportService._();

  static const _channel = MethodChannel('com.clicker.pro/platform');
  static const int defaultMaxSide = 1920;

  static const List<String> extensions = ['png', 'jpg', 'jpeg', 'bmp', 'webp', 'gif'];

  final StreamController<TemplateData> _dropController = StreamController<TemplateData>.broadcast();
  VoidCallback? _unregister;

  Stream<TemplateData> get onDropped => _dropController.stream;

  void ensureDropHandler() {
    if (_unregister != null) return;
    _unregister = SystemTrayService().registerExternalHandler((call) async {
      if (call.method != 'onFilesDropped') return false;
      if (!_dropController.hasListener) return false;
      final args = call.arguments;
      if (args is! Map) return false;
      final raw = args['paths'];
      if (raw is! List) return false;
      final paths = raw.whereType<String>().toList();
      final template = await fromPaths(paths);
      if (template == null) return false;
      _dropController.add(template);
      return true;
    });
  }

  Future<TemplateData?> fromFile({int maxSide = defaultMaxSide}) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: extensions,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return null;
    final picked = result.files.first;
    Uint8List? bytes = picked.bytes;
    if (bytes == null && picked.path != null) {
      try {
        bytes = await File(picked.path!).readAsBytes();
      } catch (_) {
        return null;
      }
    }
    if (bytes == null) return null;
    return decode(bytes, maxSide: maxSide);
  }

  Future<TemplateData?> fromPaths(List<String> paths, {int maxSide = defaultMaxSide}) async {
    for (final path in paths) {
      if (!_looksLikeImage(path)) continue;
      final template = await fromPath(path, maxSide: maxSide);
      if (template != null) return template;
    }
    return null;
  }

  Future<TemplateData?> fromPath(String path, {int maxSide = defaultMaxSide}) async {
    try {
      final bytes = await File(path).readAsBytes();
      return decode(bytes, maxSide: maxSide);
    } catch (_) {
      return null;
    }
  }

  Future<TemplateData?> fromClipboard({int maxSide = defaultMaxSide}) async {
    Map? result;
    try {
      result = await _channel.invokeMethod<Map>('getClipboardImage');
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
    if (result == null) return null;
    final paths = result['paths'];
    if (paths is List && paths.isNotEmpty) {
      return fromPaths(paths.whereType<String>().toList(), maxSide: maxSide);
    }
    final path = result['path'];
    if (path is String && path.isNotEmpty) {
      return fromPath(path, maxSide: maxSide);
    }
    final pixels = result['pixels'];
    final width = result['width'];
    final height = result['height'];
    if (pixels is! Uint8List || width is! int || height is! int) return null;
    if (width <= 0 || height <= 0 || pixels.length < width * height * 4) return null;
    return fromRawBgra(pixels, width, height, maxSide: maxSide);
  }

  static bool _looksLikeImage(String path) {
    final dot = path.lastIndexOf('.');
    if (dot < 0) return false;
    final ext = path.substring(dot + 1).toLowerCase();
    return extensions.contains(ext);
  }

  static Future<TemplateData?> decode(Uint8List bytes, {int maxSide = defaultMaxSide}) async {
    if (bytes.isEmpty) return null;
    ui.Image? source;
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      source = frame.image;
      return await _finish(source, maxSide);
    } catch (_) {
      source?.dispose();
      return null;
    }
  }

  static Future<TemplateData?> fromRawBgra(Uint8List bgra, int width, int height, {int maxSide = defaultMaxSide}) async {
    if (width <= 0 || height <= 0) return null;
    if (bgra.length < width * height * 4) return null;
    final rgba = Uint8List(bgra.length);
    for (var i = 0; i + 3 < bgra.length; i += 4) {
      rgba[i] = bgra[i + 2];
      rgba[i + 1] = bgra[i + 1];
      rgba[i + 2] = bgra[i];
      rgba[i + 3] = bgra[i + 3];
    }
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(rgba, width, height, ui.PixelFormat.rgba8888, completer.complete);
    ui.Image? source;
    try {
      source = await completer.future;
      return await _finish(source, maxSide);
    } catch (_) {
      source?.dispose();
      return null;
    }
  }

  static Future<TemplateData?> _finish(ui.Image source, int maxSide) async {
    var image = source;
    final longest = image.width > image.height ? image.width : image.height;
    if (maxSide > 0 && longest > maxSide) {
      final scale = maxSide / longest;
      final targetW = (image.width * scale).round().clamp(1, maxSide);
      final targetH = (image.height * scale).round().clamp(1, maxSide);
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      canvas.drawImageRect(
        image,
        ui.Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        ui.Rect.fromLTWH(0, 0, targetW.toDouble(), targetH.toDouble()),
        ui.Paint()..filterQuality = ui.FilterQuality.medium,
      );
      final picture = recorder.endRecording();
      final scaled = await picture.toImage(targetW, targetH);
      picture.dispose();
      image.dispose();
      image = scaled;
    }

    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (data == null) {
      image.dispose();
      return null;
    }
    final rgba = data.buffer.asUint8List();
    final bgra = Uint8List(rgba.length);
    for (var i = 0; i + 3 < rgba.length; i += 4) {
      bgra[i] = rgba[i + 2];
      bgra[i + 1] = rgba[i + 1];
      bgra[i + 2] = rgba[i];
      bgra[i + 3] = rgba[i + 3];
    }
    final result = TemplateData(pixels: bgra, width: image.width, height: image.height);
    image.dispose();
    return result;
  }
}
