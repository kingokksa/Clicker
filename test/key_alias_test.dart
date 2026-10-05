
import 'dart:convert';
import 'dart:io';

import 'package:clicker/models/key_alias.dart';
import 'package:clicker/services/key_alias_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('KeyAlias', () {
    test('round trips through json', () {
      const a = KeyAlias(name: '开火', key: 'mouse:left');
      final restored = KeyAlias.fromJson(jsonDecode(jsonEncode(a.toJson())) as Map<String, dynamic>);
      expect(restored.name, '开火');
      expect(restored.key, 'mouse:left');
    });

    test('tolerates missing fields', () {
      final a = KeyAlias.fromJson(const {});
      expect(a.name, '');
      expect(a.key, '');
    });

    test('copyWith keeps the untouched side', () {
      const a = KeyAlias(name: '开火', key: 'mouse:left');
      expect(a.copyWith(key: 'f1').name, '开火');
      expect(a.copyWith(name: '射击').key, 'mouse:left');
    });
  });

  group('KeyAliasProfile', () {
    test('round trips aliases', () {
      const p = KeyAliasProfile(name: '默认', aliases: [
        KeyAlias(name: '开火', key: 'mouse:left'),
        KeyAlias(name: '下蹲', key: 'ctrl'),
      ]);
      final restored = KeyAliasProfile.fromJson(
          jsonDecode(jsonEncode(p.toJson())) as Map<String, dynamic>);
      expect(restored.name, '默认');
      expect(restored.aliases.length, 2);
      expect(restored.aliases[1].key, 'ctrl');
    });

    test('drops malformed entries instead of throwing', () {
      final p = KeyAliasProfile.fromJson({
        'name': 'x',
        'aliases': ['nope', 42, {'name': 'a', 'key': 'b'}],
      });
      expect(p.aliases.length, 1);
      expect(p.aliases.first.name, 'a');
    });
  });

  group('key spec helpers', () {
    test('mouse specs are prefixed', () {
      expect(KeyAliasService.isMouseKey('mouse:left'), isTrue);
      expect(KeyAliasService.isMouseKey('ctrl'), isFalse);
    });

    test('mouseButtonOf strips only the prefix', () {
      expect(KeyAliasService.mouseButtonOf('mouse:x1'), 'x1');
      expect(KeyAliasService.mouseButtonOf('mouse:scrollUp'), 'scrollUp');
      expect(KeyAliasService.mouseButtonOf('ctrl'), 'ctrl');
    });

    test('every mouse category entry is a mouse spec', () {
      final mouse = keySpecCategories.first.$2;
      expect(mouse, isNotEmpty);
      for (final spec in mouse) {
        expect(KeyAliasService.isMouseKey(spec), isTrue, reason: '$spec 缺少 mouse: 前缀');
      }
    });

    test('labels fall back to upper case', () {
      expect(keySpecLabel('mouse:left'), '鼠标左键');
      expect(keySpecLabel('f1'), 'F1');
    });
  });

  group('KeyAliasService', () {
    test('resolve leaves plain keys and unknown aliases untouched', () {
      final svc = KeyAliasService.instance;
      expect(svc.resolve('f1'), 'f1');
      expect(svc.resolve('@不存在的别名'), '@不存在的别名');
      expect(svc.resolve(''), '');
      expect(svc.resolve('@'), '@');
    });

    test('import expands aliases and resolve is case insensitive', () async {
      final dir = await Directory.systemTemp.createTemp('clicker_alias');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}${Platform.pathSeparator}p.json');
      await file.writeAsString(jsonEncode({
        'version': 1,
        'active': 0,
        'profiles': [
          {
            'name': '测试方案',
            'aliases': [
              {'name': '开火', 'key': 'mouse:left'},
              {'name': 'Crouch', 'key': 'ctrl'},
            ],
          }
        ],
      }));

      final svc = KeyAliasService.instance;
      final count = await svc.importFrom(file.path);
      expect(count, 1);
      expect(svc.resolve('@开火'), 'mouse:left');
      expect(svc.resolve('@crouch'), 'ctrl');
      expect(svc.resolve('@CROUCH'), 'ctrl');
      expect(svc.resolve(' @开火 '), 'mouse:left');
      expect(svc.resolve('@未定义'), '@未定义');
      expect(KeyAliasService.isMouseKey(svc.resolve('@开火')), isTrue);
      expect(KeyAliasService.isMouseKey(svc.resolve('@crouch')), isFalse);
      expect(svc.mouseAliases.map((a) => a.name), ['开火']);
      expect(svc.keyboardAliases.map((a) => a.name), ['Crouch']);
      expect(svc.isAliasReference('@开火'), isTrue);
      expect(svc.isAliasReference('@未定义'), isFalse);
    });

    test('add, update and remove keep the lookup in sync', () async {
      final svc = KeyAliasService.instance;
      await svc.addAlias('测试别名', 'f5');
      expect(svc.resolve('@测试别名'), 'f5');

      final index = svc.aliases.indexWhere((a) => a.name == '测试别名');
      expect(index, greaterThanOrEqualTo(0));
      await svc.updateAlias(index, key: 'f6');
      expect(svc.resolve('@测试别名'), 'f6');

      await svc.addAlias('测试别名', 'f7');
      expect(svc.aliases.where((a) => a.name == '测试别名').length, 1);
      expect(svc.resolve('@测试别名'), 'f7');

      await svc.removeAlias(svc.aliases.indexWhere((a) => a.name == '测试别名'));
      expect(svc.resolve('@测试别名'), '@测试别名');
    });

    test('empty names and keys are rejected', () async {
      final svc = KeyAliasService.instance;
      final before = svc.aliases.length;
      await svc.addAlias('  ', 'f1');
      await svc.addAlias('空键', '');
      expect(svc.aliases.length, before);
    });
  });
}
