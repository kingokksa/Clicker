import 'package:clicker/services/script_engine.dart';
import 'package:flutter_test/flutter_test.dart';

const _fullScript = '''
click 100 200
click 300 400 right
key enter
delay 500
move 10 20
scroll 0 -3
type hello world 40
repeat 2
start_clicker
stop_clicker''';

const _commentedScript = '''
// 注释
# 注释

click 1 2
delay 100''';

void main() {
  group('ScriptEngine.parseScript', () {
    test('解析全部指令', () {
      final commands = ScriptEngine.parseScript(_fullScript);
      expect(commands.length, 10);
      expect(commands[0].action, 'click');
      expect(commands[0].params['x'], 100);
      expect(commands[0].params['y'], 200);
      expect(commands[0].params['button'], 'left');
      expect(commands[1].params['button'], 'right');
      expect(commands[2].params['key'], 'enter');
      expect(commands[3].params['ms'], 500);
      expect(commands[4].params['x'], 10);
      expect(commands[5].params['dy'], -3);
      expect(commands[6].params['text'], 'hello world');
      expect(commands[6].params['delayMs'], 40);
      expect(commands[7].params['count'], 2);
      expect(commands[8].action, 'start_clicker');
      expect(commands[9].action, 'stop_clicker');
    });

    test('跳过空行与注释', () {
      final commands = ScriptEngine.parseScript(_commentedScript);
      expect(commands.length, 2);
      expect(commands[0].action, 'click');
      expect(commands[1].action, 'delay');
      expect(commands[1].params['ms'], 100);
    });

    test('未知指令与参数不足的行被忽略', () {
      final commands = ScriptEngine.parseScript('unknown 1 2\nclick\nkey');
      expect(commands, isEmpty);
    });
  });

  group('ScriptEngine.formatScript', () {
    test('格式化后再解析保持指令一致', () {
      final commands = ScriptEngine.parseScript(_fullScript);
      final text = ScriptEngine.formatScript(commands);
      final again = ScriptEngine.parseScript(text);
      expect(again.length, commands.length);
      for (var i = 0; i < commands.length; i++) {
        expect(again[i].action, commands[i].action);
      }
      expect(again[6].params['text'], 'hello world');
      expect(again[6].params['delayMs'], 40);
    });

    test('空列表格式化为空字符串', () {
      expect(ScriptEngine.formatScript(const []), '');
    });
  });

  group('ScriptModel', () {
    test('JSON 往返保留指令与状态', () {
      final model = ScriptModel(
        id: 'abc',
        name: '测试脚本',
        commands: ScriptEngine.parseScript(_fullScript),
        enabled: false,
      );
      final restored = ScriptModel.fromJson(model.toJson());
      expect(restored.id, 'abc');
      expect(restored.name, '测试脚本');
      expect(restored.enabled, isFalse);
      expect(restored.commands.length, model.commands.length);
      expect(restored.commands[6].params['text'], 'hello world');
    });
  });
}
