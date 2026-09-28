/// PluginManifest / contributions 解析测试 — 守护插件清单的兼容性。
library;

import 'package:clicker/services/plugin/plugin_manifest.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PluginManifest.fromJson', () {
    test('parses a minimal manifest with defaults applied', () {
      final m = PluginManifest.fromJson({'id': 'p1', 'name': 'P1', 'version': '1.0.0'});
      expect(m.id, 'p1');
      expect(m.name, 'P1');
      expect(m.version, '1.0.0');
      expect(m.apiVersion, '1.0');
      expect(m.author, '');
      expect(m.description, '');
      expect(m.category, 'extension');
      expect(m.platforms, isEmpty);
      expect(m.runtime, PluginRuntime.dart);
      expect(m.entry, isEmpty);
      expect(m.dartPluginId, isNull);
      expect(m.permissions, isEmpty);
      expect(m.activationEvents, ['manual']);
      expect(m.icon, isNull);
      expect(m.minAppVersion, 1);
      expect(m.core, isFalse);
      expect(m.contributions.pages, isEmpty);
      expect(m.contributions.commands, isEmpty);
      expect(m.contributions.settings, isEmpty);
    });

    test('parses all fields of a native plugin', () {
      final m = PluginManifest.fromJson({
        'id': 'native-x',
        'name': 'Native X',
        'version': '2.1.0',
        'apiVersion': '2.0',
        'author': 'acme',
        'description': 'A native plugin',
        'category': 'core',
        'platforms': ['windows', 'linux'],
        'runtime': 'native',
        'entry': {'windows': 'lib/native_x.dll', 'linux': 'lib/libnative_x.so'},
        'permissions': ['input', 'screen', 'storage'],
        'activationEvents': ['onStartup'],
        'icon': 'assets/icon.png',
        'minAppVersion': 5,
        'core': true,
      });
      expect(m.runtime, PluginRuntime.native);
      expect(m.entry['windows'], 'lib/native_x.dll');
      expect(m.entry['linux'], 'lib/libnative_x.so');
      expect(m.permissions, ['input', 'screen', 'storage']);
      expect(m.activationEvents, ['onStartup']);
      expect(m.icon, 'assets/icon.png');
      expect(m.minAppVersion, 5);
      expect(m.core, isTrue);
    });

    test('unknown runtime falls back to dart', () {
      final m = PluginManifest.fromJson({'id': 'p', 'name': 'P', 'runtime': 'wasm'});
      expect(m.runtime, PluginRuntime.dart);
    });

    test('missing version defaults to 1.0.0', () {
      final m = PluginManifest.fromJson({'id': 'p', 'name': 'P'});
      expect(m.version, '1.0.0');
    });

    test('from string', () {
      const raw = '''
      {
        "id": "p", "name": "P", "version": "1.0.0", "runtime": "native",
        "entry": {"windows": "p.dll"}
      }
      ''';
      final m = PluginManifest.fromJsonString(raw);
      expect(m.runtime, PluginRuntime.native);
      expect(m.entry['windows'], 'p.dll');
    });

    test('non-string entry values are coerced to strings', () {
      final m = PluginManifest.fromJson({
        'id': 'p',
        'name': 'P',
        'entry': {'windows': 123, 'linux': {'a': 'b'}},
      });
      expect(m.entry['windows'], '123');
      expect(m.entry['linux']!.isNotEmpty, isTrue);
    });

    test('missing activationEvents defaults to manual', () {
      final m = PluginManifest.fromJson({'id': 'p', 'name': 'P'});
      expect(m.activationEvents, ['manual']);
    });

    test('missing contributes defaults to empty contributions', () {
      final m = PluginManifest.fromJson({'id': 'p', 'name': 'P'});
      expect(m.contributions, isA<PluginContributions>());
      expect(m.contributions.pages, isEmpty);
    });

    test('supportsCurrentPlatform is true when platforms is empty', () {
      final m = PluginManifest.fromJson({'id': 'p', 'name': 'P'});
      expect(m.supportsCurrentPlatform, isTrue);
    });

    test('supportsCurrentPlatform matches the current platform when listed', () {
      final m = PluginManifest.fromJson({
        'id': 'p',
        'name': 'P',
        'platforms': [currentPluginPlatform],
      });
      expect(m.supportsCurrentPlatform, isTrue);
    });

    test('supportsCurrentPlatform is false when the current platform is not listed', () {
      final other = currentPluginPlatform == 'windows' ? 'linux' : 'windows';
      final m = PluginManifest.fromJson({'id': 'p', 'name': 'P', 'platforms': [other]});
      expect(m.supportsCurrentPlatform, isFalse);
    });

    test('activatesOnDemand is false when onStartup is present', () {
      final m = PluginManifest.fromJson({
        'id': 'p',
        'name': 'P',
        'activationEvents': ['onStartup', 'manual'],
      });
      expect(m.activatesOnDemand, isFalse);
    });

    test('activatesOnDemand is true for manual activation', () {
      final m = PluginManifest.fromJson({'id': 'p', 'name': 'P', 'activationEvents': ['manual']});
      expect(m.activatesOnDemand, isTrue);
    });

    test('activatesOnDemand is false when activationEvents is empty', () {
      final m = PluginManifest.fromJson({
        'id': 'p',
        'name': 'P',
        'activationEvents': <String>[],
      });
      expect(m.activatesOnDemand, isFalse);
    });

    test('round-trips through toJson/fromJson', () {
      final original = PluginManifest(
        id: 'p1',
        name: 'P1',
        version: '1.2.3',
        apiVersion: '2.0',
        author: 'acme',
        description: 'desc',
        category: 'core',
        platforms: ['windows'],
        runtime: PluginRuntime.native,
        entry: const {'windows': 'p.dll'},
        dartPluginId: 'p1_builtin',
        permissions: ['input'],
        activationEvents: ['onStartup'],
        icon: 'icon.png',
        minAppVersion: 3,
        core: true,
      );
      final restored = PluginManifest.fromJson(original.toJson());
      expect(restored.id, original.id);
      expect(restored.name, original.name);
      expect(restored.version, original.version);
      expect(restored.apiVersion, original.apiVersion);
      expect(restored.author, original.author);
      expect(restored.description, original.description);
      expect(restored.category, original.category);
      expect(restored.platforms, original.platforms);
      expect(restored.runtime, original.runtime);
      expect(restored.entry, original.entry);
      expect(restored.dartPluginId, original.dartPluginId);
      expect(restored.permissions, original.permissions);
      expect(restored.activationEvents, original.activationEvents);
      expect(restored.icon, original.icon);
      expect(restored.minAppVersion, original.minAppVersion);
      expect(restored.core, original.core);
    });

    test('toJson omits null dartPluginId and icon', () {
      final json = const PluginManifest(id: 'p', name: 'P', version: '1').toJson();
      expect(json.containsKey('dartPluginId'), isFalse);
      expect(json.containsKey('icon'), isFalse);
    });
  });

  group('contribution submodels', () {
    test('PageContribution parses and applies defaults', () {
      final p = PageContribution.fromJson({'id': 'page1', 'title': 'Page 1'});
      expect(p.id, 'page1');
      expect(p.title, 'Page 1');
      expect(p.icon, isNull);
      expect(p.order, 100);
      expect(p.showInNav, isTrue);
      expect(p.description, isNull);
    });

    test('PageContribution falls back to id for missing title', () {
      final p = PageContribution.fromJson({'id': 'page1'});
      expect(p.title, 'page1');
    });

    test('CommandContribution falls back to id for missing title', () {
      final c = CommandContribution.fromJson({'id': 'cmd1'});
      expect(c.id, 'cmd1');
      expect(c.title, 'cmd1');
      expect(c.category, isNull);
    });

    test('SettingDefinition parses a slider with min/max/precision/unit', () {
      final s = SettingDefinition.fromJson({
        'key': 'speed',
        'type': 'slider',
        'title': 'Speed',
        'default': 5,
        'min': 1,
        'max': 10,
        'precision': 1,
        'unit': 'x',
      });
      expect(s.key, 'speed');
      expect(s.type, SettingType.slider);
      expect(s.title, 'Speed');
      expect(s.defaultValue, 5);
      expect(s.min, 1.0);
      expect(s.max, 10.0);
      expect(s.precision, 1);
      expect(s.unit, 'x');
      expect(s.options, isEmpty);
    });

    test('SettingDefinition falls back to text for unknown type', () {
      final s = SettingDefinition.fromJson({'key': 'x', 'type': 'unknown'});
      expect(s.type, SettingType.text);
    });

    test('SettingDefinition falls back to key for missing title', () {
      final s = SettingDefinition.fromJson({'key': 'x', 'type': 'text'});
      expect(s.title, 'x');
    });

    test('SettingDefinition parses dropdown options', () {
      final s = SettingDefinition.fromJson({
        'key': 'lang',
        'type': 'dropdown',
        'title': 'Language',
        'options': [
          {'value': 'zh', 'label': '中文'},
          {'value': 'en', 'label': 'English'},
        ],
      });
      expect(s.type, SettingType.dropdown);
      expect(s.options, hasLength(2));
      expect(s.options[0]['value'], 'zh');
      expect(s.options[0]['label'], '中文');
    });

    test('InputBackendContribution falls back to id for missing name', () {
      final b = InputBackendContribution.fromJson({'id': 'hw1'});
      expect(b.id, 'hw1');
      expect(b.name, 'hw1');
      expect(b.description, isNull);
    });

    test('VisionProviderContribution falls back to templateMatch kind', () {
      final v = VisionProviderContribution.fromJson({'id': 'vp1', 'name': 'VP1'});
      expect(v.id, 'vp1');
      expect(v.kind, 'templateMatch');
      expect(v.name, 'VP1');
    });

    test('VisionProviderContribution falls back to id for missing name', () {
      final v = VisionProviderContribution.fromJson({'id': 'vp1', 'kind': 'ocr'});
      expect(v.kind, 'ocr');
      expect(v.name, 'vp1');
    });

    test('PluginContributions parses every section', () {
      final c = PluginContributions.fromJson({
        'pages': [
          {'id': 'p1', 'title': 'P1'},
        ],
        'commands': [
          {'id': 'c1', 'title': 'C1'},
        ],
        'settings': [
          {'key': 's1', 'type': 'toggle', 'title': 'S1'},
        ],
        'inputBackends': [
          {'id': 'b1', 'name': 'B1'},
        ],
        'visionProviders': [
          {'id': 'v1', 'kind': 'ocr', 'name': 'V1'},
        ],
      });
      expect(c.pages, hasLength(1));
      expect(c.commands, hasLength(1));
      expect(c.settings, hasLength(1));
      expect(c.inputBackends, hasLength(1));
      expect(c.visionProviders, hasLength(1));
    });

    test('PluginContributions defaults to empty lists for missing sections', () {
      final c = PluginContributions.fromJson({});
      expect(c.pages, isEmpty);
      expect(c.commands, isEmpty);
      expect(c.settings, isEmpty);
      expect(c.inputBackends, isEmpty);
      expect(c.visionProviders, isEmpty);
    });

    test('PluginManifest pulls contributions through', () {
      final m = PluginManifest.fromJson({
        'id': 'p',
        'name': 'P',
        'contributes': {
          'pages': [
            {'id': 'p1', 'title': 'P1'},
            {'id': 'p2', 'title': 'P2'},
          ],
          'commands': [
            {'id': 'c1', 'title': 'C1'},
          ],
        },
      });
      expect(m.contributions.pages, hasLength(2));
      expect(m.contributions.commands, hasLength(1));
      expect(m.contributions.settings, isEmpty);
    });
  });

  group('PluginRuntime.fromString', () {
    test('parses known values', () {
      expect(PluginRuntime.fromString('dart'), PluginRuntime.dart);
      expect(PluginRuntime.fromString('native'), PluginRuntime.native);
    });

    test('falls back to dart for unknown values', () {
      expect(PluginRuntime.fromString('wasm'), PluginRuntime.dart);
      expect(PluginRuntime.fromString(null), PluginRuntime.dart);
      expect(PluginRuntime.fromString(''), PluginRuntime.dart);
    });
  });

  group('resolveFullPageId', () {
    test('declared id containing ":" is used as-is (explicit full id)', () {
      expect(resolveFullPageId('plugin', 'plugin:page'), 'plugin:page');
      expect(resolveFullPageId('plugin', 'other:page'), 'other:page');
    });

    test('declared id equal to plugin id is used as-is (builtin Dart convention)', () {
      expect(resolveFullPageId('plugin', 'plugin'), 'plugin');
    });

    test('otherwise prefixed with pluginId:', () {
      expect(resolveFullPageId('plugin', 'page'), 'plugin:page');
      expect(resolveFullPageId('plugin', 'sub.page'), 'plugin:sub.page');
    });
  });

  group('PluginPermission constants', () {
    test('all permissions are distinct and non-empty', () {
      expect(PluginPermission.all, hasLength(6));
      expect(PluginPermission.all.toSet().length, 6);
      for (final e in PluginPermission.all) {
        expect(e.length, greaterThan(0), reason: 'permission entry must not be empty');
      }
    });

    test('named constants are all in the all list', () {
      expect(PluginPermission.all, contains(PluginPermission.input));
      expect(PluginPermission.all, contains(PluginPermission.screen));
      expect(PluginPermission.all, contains(PluginPermission.storage));
      expect(PluginPermission.all, contains(PluginPermission.notifications));
      expect(PluginPermission.all, contains(PluginPermission.clipboard));
      expect(PluginPermission.all, contains(PluginPermission.processes));
    });
  });
}
