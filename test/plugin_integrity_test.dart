/// PluginIntegrity 单元测试。
///
/// 覆盖两层：
///   1. [normalizeHash] 纯函数 —— 不需文件系统
///   2. 核心完整性逻辑 [checkNativeLib] / [dropNativeLibAnchor] / [recordInstall]
///      —— 用真实临时文件驱动。这些逻辑的持久化写在
///      install_records.json，但读写都被 try/catch 包住，所以注入一个真实的
///      临时数据目录即可，无需 mock。
library;

import 'dart:convert';
import 'dart:io';

import 'package:clicker/services/plugin/plugin_integrity.dart';
import 'package:flutter_test/flutter_test.dart';

int _seq = 0;

/// 生成全局唯一的插件 id。
///
/// PluginIntegrity 是单例，且 _load()/_save() 会落盘到 AppPaths.getDataDir()，
/// 测试无法注入临时目录。若不保证 id 唯一，上一轮运行写入的锚点会被这一轮
/// 读回来，「首次见到」就不再成立，TOFU 语义测试会变成 flaky。
String _uid(String tag) =>
    'test_${tag}_${DateTime.now().microsecondsSinceEpoch}_${_seq++}';

void main() {
  group('normalizeHash', () {
    test('accepts a valid 64-char hex string unchanged', () {
      // SHA-256 of empty string — exactly 64 hex chars.
      const h = 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';
      expect(normalizeHash(h), h);
    });

    test('lowercases hex', () {
      const h = 'E3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B855';
      expect(normalizeHash(h),
          'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855');
    });

    test('strips whitespace', () {
      const raw =
          '  E3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B855  ';
      expect(normalizeHash(raw),
          'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855');
    });

    test('strips non-hex characters (colons, dashes, spaces)', () {
      // Insert separators between hex chars; stripping them must leave exactly 64.
      const raw =
          'E3B0:C442-98FC 1C14:9AFBF4C8996FB92427AE41E4649B934CA495991B7852B855';
      expect(normalizeHash(raw),
          'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855');
    });

    test('returns empty string for 32-char (md5) input', () {
      const md5 = 'd41d8cd98f00b204e9800998ecf8427e';
      expect(normalizeHash(md5), isEmpty);
    });

    test('returns empty string for 128-char (sha512) input', () {
      final h = 'a' * 128;
      expect(normalizeHash(h), isEmpty);
    });

    test('returns empty string for non-hex garbage', () {
      expect(normalizeHash('zzzz' * 16), isEmpty);
    });

    test('returns empty string for null', () {
      expect(normalizeHash(null), isEmpty);
    });

    test('returns empty string for empty string', () {
      expect(normalizeHash(''), isEmpty);
    });

    test('returns empty string when hex count is under 64', () {
      final h = 'a' * 63;
      expect(normalizeHash(h), isEmpty);
    });
  });

  group('PluginInstallRecord', () {
    test('round-trips through toJson/fromJson', () {
      final at = DateTime.utc(2026, 1, 2, 3, 4, 5);
      final rec = PluginInstallRecord(
        pluginId: 'p1',
        version: '1.2.3',
        zipSha256: 'a' * 64,
        source: 'store:default',
        installedAt: at,
      );
      final back = PluginInstallRecord.fromJson(rec.toJson());
      expect(back.pluginId, 'p1');
      expect(back.version, '1.2.3');
      expect(back.zipSha256, 'a' * 64);
      expect(back.source, 'store:default');
      expect(back.installedAt, at);
    });

    test('fromJson tolerates wrong-typed and missing fields', () {
      final back = PluginInstallRecord.fromJson(<String, dynamic>{
        'pluginId': 42, // wrong type → null → ''
        'version': null,
        // zipSha256 / source / installedAt missing
      });
      expect(back.pluginId, isEmpty);
      expect(back.version, isEmpty);
      expect(back.zipSha256, isEmpty);
      expect(back.source, isEmpty);
      expect(back.installedAt.millisecondsSinceEpoch, 0);
    });

    test('fromJson falls back to epoch for an unparsable installedAt', () {
      final back = PluginInstallRecord.fromJson(<String, dynamic>{
        'installedAt': 'not-a-date',
      });
      expect(back.installedAt.millisecondsSinceEpoch, 0);
    });
  });

  group('sha256FileOrNull', () {
    test('hashes a real file to the expected SHA-256', () async {
      final dir = await Directory.systemTemp.createTemp('clicker_sha');
      final f = File('${dir.path}${Platform.pathSeparator}hello.txt')
        ..writeAsStringSync('hello');
      final hash = await PluginIntegrity.instance.sha256FileOrNull(f.path);
      // SHA-256("hello")
      expect(hash,
          '2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824');
      await dir.delete(recursive: true);
    });

    test('returns empty string for a nonexistent file', () async {
      final hash = await PluginIntegrity.instance
          .sha256FileOrNull('/nonexistent/path/that/does/not/exist.dll');
      expect(hash, isEmpty);
    });
  });

  group('checkNativeLib', () {
    test('first sight establishes the trust anchor and returns unknown', () async {
      // TOFU：首次见到某库 → 记下指纹，但本轮返回 unknown（还没可比对的锚点）
      final dir = await Directory.systemTemp.createTemp('clicker_lib');
      final lib = File('${dir.path}${Platform.pathSeparator}plugin.dll')
        ..writeAsStringSync('hello');
      final integrity = PluginIntegrity.instance;

      final id = _uid('tofu');
      final v1 = await integrity.checkNativeLib(id, lib.path);
      expect(v1, IntegrityVerdict.unknown,
          reason: 'first sight establishes the anchor, so no verdict yet');

      await dir.delete(recursive: true);
    });

    test('second sight with the same content returns ok', () async {
      final dir = await Directory.systemTemp.createTemp('clicker_lib');
      final lib = File('${dir.path}${Platform.pathSeparator}plugin.dll')
        ..writeAsStringSync('hello');
      final integrity = PluginIntegrity.instance;

      final id = _uid('ok');
      await integrity.checkNativeLib(id, lib.path); // establish
      final v2 = await integrity.checkNativeLib(id, lib.path);
      expect(v2, IntegrityVerdict.ok);

      await dir.delete(recursive: true);
    });

    test('returns changed when the library is swapped (tamper detection)', () async {
      final dir = await Directory.systemTemp.createTemp('clicker_lib');
      final lib = File('${dir.path}${Platform.pathSeparator}plugin.dll')
        ..writeAsStringSync('hello');
      final integrity = PluginIntegrity.instance;

      final id = _uid('swap');
      await integrity.checkNativeLib(id, lib.path); // anchor on 'hello'
      // Attacker (or a corrupt update) replaces the DLL.
      lib.writeAsStringSync('world');
      final v2 = await integrity.checkNativeLib(id, lib.path);
      expect(v2, IntegrityVerdict.changed,
          reason: 'a swapped DLL must be detected, not silently trusted');

      await dir.delete(recursive: true);
    });

    test('returns unknown for a nonexistent library (never a false changed)', () async {
      final v = await PluginIntegrity.instance
          .checkNativeLib('missing_plugin', '/no/such/file.dll');
      expect(v, IntegrityVerdict.unknown,
          reason: 'an unreadable file must not be reported as tampered');
    });

    test('anchors are per-plugin-id', () async {
      final dir = await Directory.systemTemp.createTemp('clicker_lib');
      final a = File('${dir.path}${Platform.pathSeparator}a.dll')
        ..writeAsStringSync('hello');
      final b = File('${dir.path}${Platform.pathSeparator}b.dll')
        ..writeAsStringSync('world');
      final integrity = PluginIntegrity.instance;

      final idA = _uid('a');
      final idB = _uid('b');
      await integrity.checkNativeLib(idA, a.path);
      await integrity.checkNativeLib(idB, b.path);
      // Same content a second time for each → ok, no cross-talk
      expect(await integrity.checkNativeLib(idA, a.path), IntegrityVerdict.ok);
      expect(await integrity.checkNativeLib(idB, b.path), IntegrityVerdict.ok);
      // Swapping a to b's content must be caught for plugin_a only
      a.writeAsStringSync('world');
      expect(await integrity.checkNativeLib(idA, a.path), IntegrityVerdict.changed);
      expect(await integrity.checkNativeLib(idB, b.path), IntegrityVerdict.ok);

      await dir.delete(recursive: true);
    });
  });

  group('dropNativeLibAnchor', () {
    test('dropping lets an upgrade re-anchor instead of false-flagging', () async {
      // 这是死代码 bug 的回归测试：升级本来就会换 dll，若不 drop，
      // checkNativeLib 会把正常升级误判成 changed 而拒绝加载。
      final dir = await Directory.systemTemp.createTemp('clicker_lib');
      final lib = File('${dir.path}${Platform.pathSeparator}plugin.dll')
        ..writeAsStringSync('hello');
      final integrity = PluginIntegrity.instance;

      final id = _uid('up');
      await integrity.checkNativeLib(id, lib.path); // v1 anchored
      await integrity.dropNativeLibAnchor(id); // upgrade: drop anchor
      lib.writeAsStringSync('world'); // v2 legitimately ships a new dll

      final v = await integrity.checkNativeLib(id, lib.path);
      expect(v, IntegrityVerdict.unknown,
          reason: 'after an upgrade the new dll must re-anchor, not be flagged');

      await dir.delete(recursive: true);
    });

    test('dropping an unknown plugin id is a no-op', () async {
      // 不抛异常即可
      await PluginIntegrity.instance.dropNativeLibAnchor(_uid('never'));
    });

    test('repeated drops are safe', () async {
      final dir = await Directory.systemTemp.createTemp('clicker_lib');
      final lib = File('${dir.path}${Platform.pathSeparator}plugin.dll')
        ..writeAsStringSync('hello');
      final integrity = PluginIntegrity.instance;
      final id = _uid('droptwice');
      await integrity.checkNativeLib(id, lib.path);
      await integrity.dropNativeLibAnchor(id);
      await integrity.dropNativeLibAnchor(id);
      await dir.delete(recursive: true);
    });
  });

  group('recordInstall', () {
    test('normalizes the recorded hash', () async {
      final integrity = PluginIntegrity.instance;
      final id = _uid('rec');
      await integrity.recordInstall(
        pluginId: id,
        version: '9.9.9',
        // 大写 + 带分隔符 —— 应被归一化成 64 位小写
        zipSha256: 'E3B0:C442-98FC 1C14:9AFBF4C8996FB92427AE41E4649B934CA495991B7852B855',
        source: 'store:x',
      );
      expect(integrity.installedHashFor(id),
          'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855');
      expect(integrity.installedVersionFor(id), '9.9.9');
    });

    test('a non-sha256 string is recorded as empty rather than trusted', () async {
      final integrity = PluginIntegrity.instance;
      final id = _uid('bad');
      await integrity.recordInstall(
        pluginId: id,
        version: '1.0.0',
        zipSha256: 'not-a-hash',
        source: 'store:x',
      );
      expect(integrity.installedHashFor(id), isEmpty,
          reason: 'a malformed declaration must never become a trust anchor');
    });

    test('installedHashFor / installedVersionFor return empty for unknown ids', () {
      final integrity = PluginIntegrity.instance;
      expect(integrity.installedHashFor(_uid('noinst')), isEmpty);
      expect(integrity.installedVersionFor(_uid('noinst2')), isEmpty);
    });

    test('re-installing the same id overwrites the record', () async {
      final integrity = PluginIntegrity.instance;
      final id = _uid('overwrite');
      await integrity.recordInstall(
        pluginId: id,
        version: '1.0.0',
        zipSha256: 'a' * 64,
        source: 'store:v1',
      );
      await integrity.recordInstall(
        pluginId: id,
        version: '2.0.0',
        zipSha256: 'b' * 64,
        source: 'store:v2',
      );
      expect(integrity.installedVersionFor(id), '2.0.0');
      expect(integrity.installedHashFor(id), 'b' * 64);
    });
  });

  group('install_records.json shape', () {
    // 注意：_load()/_save() 的目标目录由 AppPaths 决定，测试无法注入，
    // 因此这里不测「文件损坏」这种需要真实落盘的场景，只测
    // install_records.json 的序列化形状 —— 它是留痕能被日后审计的前提。
    test('records survive being serialized and re-read', () async {
      // 验证 toJson/fromJson 与 _records 结构一致（install_records.json 的形状）
      final rec = PluginInstallRecord(
        pluginId: 'p',
        version: '1',
        zipSha256: 'c' * 64,
        source: 's',
        installedAt: DateTime.utc(2026, 5, 5),
      ).toJson();
      final raw = const JsonEncoder.withIndent('  ')
          .convert({'p': rec});
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final back = PluginInstallRecord.fromJson(decoded['p'] as Map);
      expect(back.pluginId, 'p');
      expect(back.zipSha256, 'c' * 64);
    });
  });
}
