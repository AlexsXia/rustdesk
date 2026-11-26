import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/utils/http_service.dart' as http;

const _profilesOption = 'uu-keymap-profiles';
const _selectedOption = 'uu-keymap-selected';
const _serverPath = '/api/keymap/profiles';

/// 方案或开关变化后自增，远控页据此重绘按键叠加层。
final ValueNotifier<int> uuKeymapRevision = ValueNotifier<int>(0);

/// “一键隐藏所有按键”生效期间，叠加层只保留隐藏按钮本身。
final ValueNotifier<bool> uuKeymapHidden = ValueNotifier<bool>(false);

enum UuKeyKind { keys, mouse, scroll, action }

class UuKeyButton {
  UuKeyButton({
    this.label = '',
    required this.kind,
    this.keys = const <String>[],
    this.mouse = '',
    this.scroll = 0,
    this.action = '',
    required this.x,
    required this.y,
    this.size = 54,
  });

  /// 自定义名称；为空时按绑定内容自动显示（如 W、Ctrl+1、左键）。
  String label;

  /// keys: 最多 4 个按键同时按下；mouse: 鼠标键；scroll: 滚轮；action: 功能键。
  UuKeyKind kind;
  List<String> keys;

  /// left / right / middle / back / forward
  String mouse;

  /// 1 上滚，-1 下滚
  int scroll;

  /// hide / keyboard
  String action;

  double x;
  double y;
  double size;

  bool get isValid {
    switch (kind) {
      case UuKeyKind.keys:
        return keys.isNotEmpty;
      case UuKeyKind.mouse:
        return mouse.isNotEmpty;
      case UuKeyKind.scroll:
        return scroll != 0;
      case UuKeyKind.action:
        return action.isNotEmpty;
    }
  }

  String get displayLabel {
    if (label.isNotEmpty) return label;
    switch (kind) {
      case UuKeyKind.keys:
        return keys.map(uuKeyLabel).join('+');
      case UuKeyKind.mouse:
        return uuMouseLabel(mouse);
      case UuKeyKind.scroll:
        return scroll >= 0 ? '上滚轮' : '下滚轮';
      case UuKeyKind.action:
        return action == 'hide' ? '隐藏按键' : '键盘输入';
    }
  }

  Map<String, dynamic> toJson() => {
        'label': label,
        'kind': kind.name,
        'keys': keys,
        'mouse': mouse,
        'scroll': scroll,
        'action': action,
        'x': x,
        'y': y,
        'size': size,
      };

  static UuKeyButton? fromJson(Object? value) {
    if (value is! Map) return null;
    final x = (value['x'] as num? ?? 0.5).toDouble();
    final y = (value['y'] as num? ?? 0.5).toDouble();
    final size = (value['size'] as num? ?? 54).toDouble();
    final label = value['label'] is String ? value['label'] as String : '';
    final kindName = value['kind'];
    if (kindName is String) {
      final kind = UuKeyKind.values.firstWhere(
        (item) => item.name == kindName,
        orElse: () => UuKeyKind.keys,
      );
      final keys = <String>[];
      if (value['keys'] is List) {
        for (final key in value['keys'] as List) {
          if (key is String && key.isNotEmpty) keys.add(key);
        }
      }
      final button = UuKeyButton(
        label: label,
        kind: kind,
        keys: keys,
        mouse: value['mouse'] is String ? value['mouse'] as String : '',
        scroll: value['scroll'] is num ? (value['scroll'] as num).toInt() : 0,
        action: value['action'] is String ? value['action'] as String : '',
        x: x,
        y: y,
        size: size,
      );
      return button.isValid ? button : null;
    }
    // 旧格式：单个 key 字段。
    final key = value['key'];
    if (key is! String || key.isEmpty) return null;
    return UuKeyButton(
      label: label,
      kind: UuKeyKind.keys,
      keys: [key],
      x: x,
      y: y,
      size: size,
    );
  }

  UuKeyButton copy() => UuKeyButton(
        label: label,
        kind: kind,
        keys: List.of(keys),
        mouse: mouse,
        scroll: scroll,
        action: action,
        x: x,
        y: y,
        size: size,
      );
}

class UuKeyProfile {
  UuKeyProfile({
    required this.id,
    required this.name,
    required this.keys,
    this.serverId,
    this.author = '',
  });

  String id;
  String name;
  List<UuKeyButton> keys;

  /// 已同步到账号服务器时的记录 id。
  int? serverId;
  String author;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'keys': [for (final key in keys) key.toJson()],
        if (serverId != null) 'serverId': serverId,
        if (author.isNotEmpty) 'author': author,
      };

  static UuKeyProfile? fromJson(Object? value) {
    if (value is! Map) return null;
    final id = value['id'];
    if (id is! String || id.isEmpty) return null;
    final keys = <UuKeyButton>[];
    final rawKeys = value['keys'];
    if (rawKeys is List) {
      for (final raw in rawKeys) {
        final key = UuKeyButton.fromJson(raw);
        if (key != null) keys.add(key);
      }
    }
    return UuKeyProfile(
      id: id,
      name: value['name'] is String && (value['name'] as String).isNotEmpty
          ? value['name'] as String
          : '未命名方案',
      keys: keys,
      serverId:
          value['serverId'] is num ? (value['serverId'] as num).toInt() : null,
      author: value['author'] is String ? value['author'] as String : '',
    );
  }

  UuKeyProfile copy() => UuKeyProfile(
        id: id,
        name: name,
        keys: [for (final key in keys) key.copy()],
        serverId: serverId,
        author: author,
      );
}

List<UuKeyProfile> loadUuKeyProfiles() {
  final raw = bind.mainGetLocalOption(key: _profilesOption);
  if (raw.isEmpty) return [];
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return [];
    final profiles = <UuKeyProfile>[];
    for (final item in decoded) {
      final profile = UuKeyProfile.fromJson(item);
      if (profile != null) profiles.add(profile);
    }
    return profiles;
  } catch (_) {
    return [];
  }
}

Future<void> saveUuKeyProfiles(List<UuKeyProfile> profiles) =>
    bind.mainSetLocalOption(
        key: _profilesOption,
        value: jsonEncode([for (final profile in profiles) profile.toJson()]));

Future<void> upsertUuKeyProfile(UuKeyProfile profile) async {
  final profiles = loadUuKeyProfiles();
  final index = profiles.indexWhere((item) => item.id == profile.id);
  if (index >= 0) {
    profiles[index] = profile;
  } else {
    profiles.add(profile);
  }
  await saveUuKeyProfiles(profiles);
  uuKeymapRevision.value++;
}

UuKeyProfile? uuActiveKeyProfile() {
  final id = bind.mainGetLocalOption(key: _selectedOption);
  if (id.isEmpty) return null;
  for (final profile in loadUuKeyProfiles()) {
    if (profile.id == id) return profile;
  }
  return null;
}

Future<void> selectUuKeyProfile(String id) async {
  uuKeymapHidden.value = false;
  await bind.mainSetLocalOption(key: _selectedOption, value: id);
  uuKeymapRevision.value++;
}

/// 新建方案时给一份可直接上手的默认布局。
UuKeyProfile uuNewKeyProfile(String name) => UuKeyProfile(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: name,
      keys: [
        UuKeyButton(kind: UuKeyKind.keys, keys: ['VK_W'], x: 0.18, y: 0.52),
        UuKeyButton(kind: UuKeyKind.keys, keys: ['VK_A'], x: 0.09, y: 0.63),
        UuKeyButton(kind: UuKeyKind.keys, keys: ['VK_S'], x: 0.18, y: 0.74),
        UuKeyButton(kind: UuKeyKind.keys, keys: ['VK_D'], x: 0.27, y: 0.63),
        UuKeyButton(
            label: '跳跃',
            kind: UuKeyKind.keys,
            keys: ['VK_SPACE'],
            x: 0.82,
            y: 0.78),
      ],
    );

UuKeyProfile? uuKeyProfileFromServer(Object? value) {
  if (value is! Map) return null;
  final serverId = value['id'];
  if (serverId is! num) return null;
  Object? payload = value['data'];
  if (payload is String) {
    try {
      payload = jsonDecode(payload);
    } catch (_) {
      return null;
    }
  }
  final keys = <UuKeyButton>[];
  if (payload is Map && payload['keys'] is List) {
    for (final raw in payload['keys'] as List) {
      final key = UuKeyButton.fromJson(raw);
      if (key != null) keys.add(key);
    }
  }
  if (keys.isEmpty) return null;
  final name = value['name'];
  return UuKeyProfile(
    id: 'srv$serverId',
    name: name is String && name.isNotEmpty ? name : '共享方案',
    keys: keys,
    serverId: serverId.toInt(),
    author: value['author'] is String ? value['author'] as String : '',
  );
}

Future<String> _apiServer() async => (await bind.mainGetApiServer()).trim();

String _authToken() => bind.mainGetLocalOption(key: 'access_token');

/// 拉取可用的在线方案（含自己的和他人公开的），未登录或离线时返回空列表。
Future<List<UuKeyProfile>> fetchUuKeymapProfiles() async {
  final token = _authToken();
  final server = await _apiServer();
  if (token.isEmpty || server.isEmpty) return [];
  try {
    final resp = await http.get(
      Uri.parse('$server$_serverPath'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (resp.statusCode != 200) return [];
    final decoded =
        jsonDecode(utf8.decode(resp.bodyBytes, allowMalformed: true));
    if (decoded is! Map || decoded['profiles'] is! List) return [];
    final profiles = <UuKeyProfile>[];
    for (final item in decoded['profiles'] as List) {
      final profile = uuKeyProfileFromServer(item);
      if (profile != null) profiles.add(profile);
    }
    return profiles;
  } catch (_) {
    return [];
  }
}

/// 上传或更新方案，成功返回服务器记录 id。
Future<int?> uploadUuKeyProfile(UuKeyProfile profile) async {
  final token = _authToken();
  final server = await _apiServer();
  if (token.isEmpty || server.isEmpty) return null;
  try {
    final resp = await http.post(
      Uri.parse('$server$_serverPath'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        if (profile.serverId != null) 'id': profile.serverId,
        'name': profile.name,
        'data': jsonEncode({
          'keys': [for (final key in profile.keys) key.toJson()],
        }),
      }),
    );
    if (resp.statusCode != 200) return null;
    final decoded =
        jsonDecode(utf8.decode(resp.bodyBytes, allowMalformed: true));
    if (decoded is Map && decoded['id'] is num) {
      return (decoded['id'] as num).toInt();
    }
    return null;
  } catch (_) {
    return null;
  }
}

const _keyLabels = <String, String>{
  'VK_ESCAPE': 'Esc',
  'VK_TAB': 'Tab',
  'VK_CAPITAL': 'Caps',
  'VK_BACK': '⌫',
  'VK_ENTER': 'Enter',
  'VK_RETURN': 'Enter',
  'VK_SPACE': 'Space',
  'VK_SHIFT': 'Shift',
  'VK_CONTROL': 'Control',
  'VK_MENU': 'Option',
  'Meta': 'Command',
  'RWin': 'Command',
  'VK_MINUS': '-',
  'VK_PLUS': '=',
  'VK_LBRACKET': '[',
  'VK_RBRACKET': ']',
  'VK_BACKSLASH': '\\',
  'VK_SEMICOLON': ';',
  'VK_QUOTE': "'",
  'VK_COMMA': ',',
  'VK_DOT': '.',
  'VK_SLASH': '/',
  'VK_UP': '↑',
  'VK_DOWN': '↓',
  'VK_LEFT': '←',
  'VK_RIGHT': '→',
  'VK_SNAPSHOT': 'PrtScr',
  'VK_SCROLL': 'ScrLK',
  'VK_PAUSE': 'Pause',
  'VK_INSERT': 'Ins',
  'VK_HOME': 'Home',
  'VK_PRIOR': 'PgUp',
  'VK_DELETE': 'Del',
  'VK_END': 'End',
  'VK_NEXT': 'PgDn',
  'VK_DECIMAL': '.',
  'VK_0': '0',
  'VK_1': '1',
  'VK_2': '2',
  'VK_3': '3',
  'VK_4': '4',
  'VK_5': '5',
  'VK_6': '6',
  'VK_7': '7',
  'VK_8': '8',
  'VK_9': '9',
  'VK_NUMPAD0': '0',
  'VK_NUMPAD1': '1',
  'VK_NUMPAD2': '2',
  'VK_NUMPAD3': '3',
  'VK_NUMPAD4': '4',
  'VK_NUMPAD5': '5',
  'VK_NUMPAD6': '6',
  'VK_NUMPAD7': '7',
  'VK_NUMPAD8': '8',
  'VK_NUMPAD9': '9',
};

String uuKeyLabel(String key) {
  final label = _keyLabels[key];
  if (label != null) return label;
  if (key.length == 1) return key.toUpperCase();
  return key.startsWith('VK_') ? key.substring(3) : key;
}

String uuMouseLabel(String mouse) {
  switch (mouse) {
    case 'left':
      return '左键';
    case 'right':
      return '右键';
    case 'middle':
      return '中键';
    case 'back':
      return '上侧键';
    case 'forward':
      return '下侧键';
    default:
      return '鼠标';
  }
}

const _modifierOrder = [
  'VK_CONTROL',
  'VK_MENU',
  'VK_SHIFT',
  'Meta',
  'RControl',
  'RAlt',
  'RShift',
  'RWin',
];

/// 组合键按“修饰键先按下、后抬起”的顺序发送。
List<String> uuChordDownOrder(List<String> keys) {
  final modifiers = keys.where(_modifierOrder.contains).toList()
    ..sort((a, b) =>
        _modifierOrder.indexOf(a).compareTo(_modifierOrder.indexOf(b)));
  return [
    ...modifiers,
    ...keys.where((key) => !_modifierOrder.contains(key)),
  ];
}
