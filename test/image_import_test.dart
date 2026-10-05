import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:clicker/services/image_import_service.dart';
import 'package:clicker/services/system_tray_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<Uint8List> pngBytes(int width, int height,
    {int r = 200, int g = 40, int b = 90}) async {
  final pixels = Uint8List(width * height * 4);
  for (var i = 0; i < width * height; i++) {
    pixels[i * 4] = r;
    pixels[i * 4 + 1] = g;
    pixels[i * 4 + 2] = b;
    pixels[i * 4 + 3] = 255;
  }
  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
      pixels, width, height, ui.PixelFormat.rgba8888, completer.complete);
  final image = await completer.future;
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('clicker_img_import');
  });

  tearDown(() async {
    if (dir.existsSync()) await dir.delete(recursive: true);
  });

  Future<File> writePng(String name, int w, int h) async {
    final file = File('${dir.path}${Platform.pathSeparator}$name');
    await file.writeAsBytes(await pngBytes(w, h));
    return file;
  }

  group('图片导入支持的格式', () {
    test('覆盖常见位图后缀', () {
      expect(ImageImportService.extensions, contains('png'));
      expect(ImageImportService.extensions, contains('jpg'));
      expect(ImageImportService.extensions, contains('jpeg'));
      expect(ImageImportService.extensions, contains('bmp'));
      expect(ImageImportService.extensions, contains('webp'));
      expect(ImageImportService.extensions, contains('gif'));
    });
  });

  group('从内存字节解码图片', () {
    test('PNG 解码后尺寸正确且像素是 BGRA', () async {
      final bytes = await pngBytes(6, 4, r: 200, g: 40, b: 90);
      final tpl = await ImageImportService.decode(bytes);
      expect(tpl, isNotNull);
      expect(tpl!.width, 6);
      expect(tpl.height, 4);
      expect(tpl.pixels.length, 6 * 4 * 4);
      expect(tpl.pixels[0], 90);
      expect(tpl.pixels[1], 40);
      expect(tpl.pixels[2], 200);
      expect(tpl.pixels[3], 255);
    });

    test('超过 maxSide 时按最长边缩放', () async {
      final bytes = await pngBytes(120, 60);
      final tpl = await ImageImportService.decode(bytes, maxSide: 30);
      expect(tpl, isNotNull);
      expect(tpl!.width, 30);
      expect(tpl.height, 15);
    });

    test('不缩放时保持原始尺寸', () async {
      final bytes = await pngBytes(20, 10);
      final tpl = await ImageImportService.decode(bytes, maxSide: 100);
      expect(tpl!.width, 20);
      expect(tpl.height, 10);
    });

    test('非图片字节返回 null', () async {
      final tpl = await ImageImportService.decode(
          Uint8List.fromList(List<int>.filled(32, 7)));
      expect(tpl, isNull);
    });
  });

  group('从 BGRA 原始像素构造模板', () {
    test('保留原始字节顺序', () async {
      final bgra = Uint8List.fromList([
        1, 2, 3, 4, //
        5, 6, 7, 8, //
        9, 10, 11, 12, //
        13, 14, 15, 16,
      ]);
      final tpl = await ImageImportService.fromRawBgra(bgra, 2, 2);
      expect(tpl, isNotNull);
      expect(tpl!.width, 2);
      expect(tpl.height, 2);
      expect(tpl.pixels, bgra);
    });

    test('尺寸非法时返回 null', () async {
      final tpl = await ImageImportService.fromRawBgra(
          Uint8List.fromList(List<int>.filled(4, 1)), 0, 0);
      expect(tpl, isNull);
    });
  });

  group('从文件路径读取', () {
    test('读取单个图片文件', () async {
      final file = await writePng('a.png', 8, 5);
      final tpl = await ImageImportService.instance.fromPath(file.path);
      expect(tpl, isNotNull);
      expect(tpl!.width, 8);
      expect(tpl.height, 5);
    });

    test('不存在的路径返回 null', () async {
      final tpl = await ImageImportService.instance
          .fromPath('${dir.path}${Platform.pathSeparator}missing.png');
      expect(tpl, isNull);
    });

    test('多路径时跳过非图片取第一张有效图片', () async {
      final txt = File('${dir.path}${Platform.pathSeparator}b.txt');
      await txt.writeAsString('not an image');
      final png = await writePng('c.png', 7, 3);
      final tpl = await ImageImportService.instance
          .fromPaths([txt.path, png.path]);
      expect(tpl, isNotNull);
      expect(tpl!.width, 7);
      expect(tpl.height, 3);
    });

    test('全部不是图片时返回 null', () async {
      final txt = File('${dir.path}${Platform.pathSeparator}d.txt');
      await txt.writeAsString('not an image');
      final tpl = await ImageImportService.instance.fromPaths([txt.path]);
      expect(tpl, isNull);
    });
  });

  group('拖拽投递回调', () {
    setUp(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('com.clicker.pro/platform'),
        (call) async => null,
      );
    });

    test('onFilesDropped 平台消息会推送模板到 onDropped 流', () async {
      final file = await writePng('drop.png', 12, 9);
      await SystemTrayService().init();
      ImageImportService.instance.ensureDropHandler();

      final received = ImageImportService.instance.onDropped.first;
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
        'com.clicker.pro/platform',
        const StandardMethodCodec().encodeMethodCall(
          MethodCall('onFilesDropped', <String, dynamic>{
            'paths': <String>[file.path],
          }),
        ),
        (_) {},
      );

      final tpl = await received;
      expect(tpl.width, 12);
      expect(tpl.height, 9);
    });

    test('路径列表为空时不推送', () async {
      await SystemTrayService().init();
      ImageImportService.instance.ensureDropHandler();

      var fired = false;
      final sub =
          ImageImportService.instance.onDropped.listen((_) => fired = true);
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
        'com.clicker.pro/platform',
        const StandardMethodCodec().encodeMethodCall(
          const MethodCall('onFilesDropped', <String, dynamic>{
            'paths': <String>[],
          }),
        ),
        (_) {},
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(fired, isFalse);
      await sub.cancel();
    });
  });
}
