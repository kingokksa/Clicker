import 'dart:io';

import 'package:clicker/services/app_logger.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;
  late AppLogger logger;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('clicker_log');
    logger = AppLogger.forTesting();
    await logger.init(directory: dir.path);
  });

  tearDown(() async {
    try {
      await dir.delete(recursive: true);
    } catch (_) {}
  });

  test('日志写入文件并能按顺序读回', () async {
    logger.log('Test', '第一条');
    logger.log('Test', '第二条');
    await logger.flush();
    final lines = await logger.readTail();
    expect(lines.length, 2);
    expect(lines[0].contains('[Test] 第一条'), isTrue);
    expect(lines[1].contains('[Test] 第二条'), isTrue);
  });

  test('readTail 只返回最后 N 行', () async {
    for (var i = 0; i < 20; i++) {
      logger.log('Test', 'line $i');
    }
    await logger.flush();
    final lines = await logger.readTail(maxLines: 5);
    expect(lines.length, 5);
    expect(lines.last.contains('line 19'), isTrue);
  });

  test('内存缓冲最多保留 400 行', () async {
    for (var i = 0; i < 450; i++) {
      logger.log('Test', 'line $i');
    }
    expect(logger.recent.length, 400);
    expect(logger.recent.last.contains('line 449'), isTrue);
  });

  test('clear 清空文件与缓冲后可继续写入', () async {
    logger.log('Test', 'before');
    await logger.flush();
    await logger.clear();
    expect(logger.recent, isEmpty);
    expect(await logger.readTail(), isEmpty);
    logger.log('Test', 'after');
    await logger.flush();
    final lines = await logger.readTail();
    expect(lines.length, 1);
    expect(lines.single.contains('after'), isTrue);
  });

  test('未初始化时记录不抛异常', () {
    final fresh = AppLogger.forTesting();
    expect(() => fresh.log('Test', 'no init'), returnsNormally);
    expect(fresh.recent.length, 1);
    expect(fresh.currentLogPath(), isEmpty);
  });
}
