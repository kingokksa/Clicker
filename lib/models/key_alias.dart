
class KeyAlias {
  final String name;
  final String key;

  const KeyAlias({required this.name, required this.key});

  KeyAlias copyWith({String? name, String? key}) =>
      KeyAlias(name: name ?? this.name, key: key ?? this.key);

  Map<String, dynamic> toJson() => {'name': name, 'key': key};

  factory KeyAlias.fromJson(Map<String, dynamic> json) =>
      KeyAlias(name: json['name'] as String? ?? '', key: json['key'] as String? ?? '');
}

class KeyAliasProfile {
  final String name;
  final List<KeyAlias> aliases;

  const KeyAliasProfile({required this.name, this.aliases = const []});

  KeyAliasProfile copyWith({String? name, List<KeyAlias>? aliases}) =>
      KeyAliasProfile(name: name ?? this.name, aliases: aliases ?? this.aliases);

  Map<String, dynamic> toJson() =>
      {'name': name, 'aliases': aliases.map((a) => a.toJson()).toList()};

  factory KeyAliasProfile.fromJson(Map<String, dynamic> json) => KeyAliasProfile(
        name: json['name'] as String? ?? '',
        aliases: ((json['aliases'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => KeyAlias.fromJson(e.cast<String, dynamic>()))
            .toList(),
      );
}

const String keyAliasPrefix = '@';
const String mouseKeyPrefix = 'mouse:';

const List<(String, List<String>)> keySpecCategories = [
  (
    '鼠标',
    [
      'mouse:left',
      'mouse:right',
      'mouse:middle',
      'mouse:x1',
      'mouse:x2',
      'mouse:scrollUp',
      'mouse:scrollDown',
    ]
  ),
  ('修饰键', ['ctrl', 'shift', 'alt', 'win']),
  ('功能键', [
    'f1', 'f2', 'f3', 'f4', 'f5', 'f6', 'f7', 'f8', 'f9', 'f10', 'f11', 'f12',
  ]),
  ('编辑键', ['space', 'enter', 'tab', 'escape', 'backspace', 'delete', 'insert']),
  ('方向键', ['up', 'down', 'left', 'right', 'home', 'end', 'pageup', 'pagedown']),
  ('数字', ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9']),
  ('字母', [
    'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm',
    'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z',
  ]),
];

const Map<String, String> keySpecLabels = {
  'mouse:left': '鼠标左键',
  'mouse:right': '鼠标右键',
  'mouse:middle': '鼠标中键',
  'mouse:x1': '鼠标侧键1',
  'mouse:x2': '鼠标侧键2',
  'mouse:scrollUp': '滚轮上',
  'mouse:scrollDown': '滚轮下',
};

String keySpecLabel(String key) => keySpecLabels[key] ?? key.toUpperCase();
