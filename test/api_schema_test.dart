import 'package:clicker/services/api/api_schema.dart';
import 'package:flutter_test/flutter_test.dart';

ApiError _capture(void Function() body) {
  try {
    body();
  } on ApiError catch (e) {
    return e;
  }
  fail('期望抛出 ApiError，但没有抛出');
}

void main() {
  group('asInt', () {
    test('整数原样返回', () => expect(asInt(42), 42));
    test('浮点四舍五入', () => expect(asInt(4.6), 5));
    test('数字字符串可解析', () => expect(asInt('42'), 42));
    test('字符串两端空白被忽略', () => expect(asInt('  42  '), 42));
    test('非数字字符串返回 null', () => expect(asInt('abc'), isNull));
    test('布尔返回 null', () => expect(asInt(true), isNull));
    test('null 返回 null', () => expect(asInt(null), isNull));
  });

  group('asDouble', () {
    test('double 原样返回', () => expect(asDouble(2.5), 2.5));
    test('int 转 double', () => expect(asDouble(3), 3.0));
    test('数字字符串可解析', () => expect(asDouble('2.5'), 2.5));
    test('非数字字符串返回 null', () => expect(asDouble('x'), isNull));
  });

  group('asBool', () {
    test('bool 原样返回', () {
      expect(asBool(true), isTrue);
      expect(asBool(false), isFalse);
    });
    test('数字 1/0 转布尔', () {
      expect(asBool(1), isTrue);
      expect(asBool(0), isFalse);
    });
    test('true 系列字符串', () {
      expect(asBool('true'), isTrue);
      expect(asBool('YES'), isTrue);
      expect(asBool('on'), isTrue);
      expect(asBool('1'), isTrue);
    });
    test('false 系列字符串', () {
      expect(asBool('false'), isFalse);
      expect(asBool('NO'), isFalse);
      expect(asBool('off'), isFalse);
      expect(asBool('0'), isFalse);
    });
    test('无法识别返回 null', () {
      expect(asBool('maybe'), isNull);
      expect(asBool(null), isNull);
    });
  });

  group('asString / asMap / asList', () {
    test('asString 保持字符串', () => expect(asString('a'), 'a'));
    test('asString 把其它类型转字符串', () => expect(asString(1), '1'));
    test('asString(null) 为 null', () => expect(asString(null), isNull));
    test('asMap 接受 Map<String,dynamic>', () {
      expect(asMap({'a': 1}), {'a': 1});
    });
    test('asMap 对非 Map 返回 null', () {
      expect(asMap('x'), isNull);
      expect(asMap([1]), isNull);
    });
    test('asList 接受 List', () => expect(asList([1, 2]), [1, 2]));
    test('asList 对非 List 返回 null', () => expect(asList('x'), isNull));
  });

  group('require*', () {
    test('requireInt 读取成功', () => expect(requireInt({'x': 5}, 'x'), 5));
    test('requireInt 缺失时抛 invalid_argument', () {
      final e = _capture(() => requireInt({}, 'x'));
      expect(e.code, 'invalid_argument');
      expect(e.hint, contains('x'));
    });
    test('requireString 读取成功', () {
      expect(requireString({'k': 'v'}, 'k'), 'v');
    });
    test('requireString 拒绝空串', () {
      expect(_capture(() => requireString({'k': ''}, 'k')).code,
          'invalid_argument');
    });
    test('requireMap 读取成功', () {
      expect(requireMap({'m': {'a': 1}}, 'm'), {'a': 1});
    });
    test('requireList 读取成功', () {
      expect(requireList({'l': [1]}, 'l'), [1]);
    });
  });

  group('optional*', () {
    test('缺失时返回默认值', () {
      expect(optionalInt({}, 'x', 7), 7);
      expect(optionalDouble({}, 'x', 1.5), 1.5);
      expect(optionalBool({}, 'x', true), isTrue);
      expect(optionalString({}, 'x', 'd'), 'd');
    });
    test('提供时使用提供的值', () {
      expect(optionalInt({'x': '9'}, 'x', 7), 9);
      expect(optionalBool({'x': 'off'}, 'x', true), isFalse);
    });
  });

  group('optionalEnum', () {
    test('按名字匹配', () {
      expect(optionalEnum({'m': 'double'}, 'm', _Mode.values, _Mode.single),
          _Mode.double);
    });
    test('缺失时返回默认值', () {
      expect(optionalEnum({}, 'm', _Mode.values, _Mode.single), _Mode.single);
    });
    test('非法值抛 invalid_argument 且 hint 列出合法值', () {
      final e = _capture(
          () => optionalEnum({'m': 'nope'}, 'm', _Mode.values, _Mode.single));
      expect(e.code, 'invalid_argument');
      expect(e.hint, contains('single'));
      expect(e.hint, contains('double'));
    });
  });

  group('describeValue', () {
    test('null 输出 null 字面量', () => expect(describeValue(null), 'null'));
    test('字符串加引号', () => expect(describeValue('a'), '"a"'));
    test('数字直接输出', () => expect(describeValue(5), '5'));
    test('超长结构被截断', () {
      final s = describeValue({'k': List.filled(300, 'a').join()});
      expect(s.length, 203);
      expect(s.endsWith('...'), isTrue);
    });
  });

  group('validateAgainstSchema', () {
    test('合法实例返回空列表', () {
      final errors = validateAgainstSchema(
        objSchemaForTest,
        {'x': 5, 'name': 'n'},
      );
      expect(errors, isEmpty);
    });
    test('缺少必填参数', () {
      final errors = validateAgainstSchema(objSchemaForTest, {'name': 'n'});
      expect(errors.any((e) => e.contains('缺少必填参数')), isTrue);
    });
    test('拒绝未知参数', () {
      final errors = validateAgainstSchema(
          objSchemaForTest, {'x': 1, 'name': 'n', 'zzz': 1});
      expect(errors.any((e) => e.contains('未知参数')), isTrue);
    });
    test('类型不匹配：整数', () {
      final errors =
          validateAgainstSchema(objSchemaForTest, {'x': 'abc', 'name': 'n'});
      expect(errors.any((e) => e.contains('需要整数')), isTrue);
    });
    test('类型不匹配：字符串', () {
      final errors = validateAgainstSchema(objSchemaForTest, {'x': 1, 'name': 5});
      expect(errors.any((e) => e.contains('需要字符串')), isTrue);
    });
    test('类型不匹配：布尔', () {
      final errors = validateAgainstSchema(
          {'properties': {'b': {'type': 'boolean'}}}, {'b': 'maybe'});
      expect(errors.any((e) => e.contains('需要布尔值')), isTrue);
    });
    test('类型不匹配：数组', () {
      final errors = validateAgainstSchema(
          {'properties': {'a': {'type': 'array'}}}, {'a': 'x'});
      expect(errors.any((e) => e.contains('需要数组')), isTrue);
    });
    test('类型不匹配：对象', () {
      final errors = validateAgainstSchema(
          {'properties': {'o': {'type': 'object'}}}, {'o': 'x'});
      expect(errors.any((e) => e.contains('需要对象')), isTrue);
    });
    test('枚举越界', () {
      final errors = validateAgainstSchema(
          {'properties': {'m': {'type': 'string', 'enum': ['a', 'b']}}},
          {'m': 'c'});
      expect(errors.any((e) => e.contains('不在允许范围内')), isTrue);
    });
    test('低于最小值', () {
      final errors = validateAgainstSchema(
          {'properties': {'n': {'type': 'integer', 'minimum': 10}}}, {'n': 5});
      expect(errors.any((e) => e.contains('不能小于')), isTrue);
    });
    test('高于最大值', () {
      final errors = validateAgainstSchema(
          {'properties': {'n': {'type': 'integer', 'maximum': 10}}}, {'n': 50});
      expect(errors.any((e) => e.contains('不能大于')), isTrue);
    });
    test('未提供的可选参数不校验', () {
      expect(validateAgainstSchema(objSchemaForTest, {'x': 1}), isEmpty);
    });
  });

  group('ApiError', () {
    test('工厂设置对应 code', () {
      expect(ApiError.invalidArgument('m').code, 'invalid_argument');
      expect(ApiError.notFound('m').code, 'not_found');
      expect(ApiError.unsupported('m').code, 'unsupported');
      expect(ApiError.conflict('m').code, 'conflict');
    });
    test('toJson 含 code/message，hint 可选', () {
      expect(ApiError.notFound('m').toJson(), {'code': 'not_found', 'message': 'm'});
      expect(ApiError.notFound('m', hint: 'h').toJson()['hint'], 'h');
    });
    test('toString 含 code 与 message', () {
      expect(ApiError('c', 'm').toString(), contains('c'));
      expect(ApiError('c', 'm').toString(), contains('m'));
    });
  });
}

enum _Mode { single, double }

final Map<String, dynamic> objSchemaForTest = {
  'type': 'object',
  'properties': {
    'x': {'type': 'integer'},
    'name': {'type': 'string'},
  },
  'required': ['x'],
  'additionalProperties': false,
};
