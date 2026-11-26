import 'package:flutter/material.dart';

import '../uu_keymap.dart';

const _kBg = Color(0xFF0E0E10);
const _kPanel = Color(0xFF1C1C1E);
const _kCap = Color(0xFF333336);
const _kCapHi = Color(0xFF3B6BF6);
const _kMuted = Color(0xFF9B9B9F);
const _kBlue = Color(0xFF3B6BF6);

/// 打开 UU 风格的按键选择页：选择键盘按键（可组合 2~4 个）、鼠标按键、
/// 滚轮或功能键。取消时返回 null。
Future<UuKeyButton?> openUuKeyPicker(
  BuildContext context, {
  UuKeyButton? initial,
}) {
  return Navigator.of(context).push<UuKeyButton>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => UuKeyPickerPage(initial: initial),
    ),
  );
}

enum _PickTab { keyboard, mouse, function }

class UuKeyPickerPage extends StatefulWidget {
  const UuKeyPickerPage({super.key, this.initial});

  final UuKeyButton? initial;

  @override
  State<UuKeyPickerPage> createState() => _UuKeyPickerPageState();
}

class _UuKeyPickerPageState extends State<UuKeyPickerPage> {
  late UuKeyKind _kind;
  late List<String> _keys;
  late String _mouse;
  late int _scroll;
  late String _action;
  late _PickTab _tab;
  bool _numeric = false;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _kind = initial?.kind ?? UuKeyKind.keys;
    _keys = List.of(initial?.keys ?? const <String>[]);
    _mouse = initial?.mouse ?? '';
    _scroll = initial?.scroll ?? 0;
    _action = initial?.action ?? '';
    _tab = switch (_kind) {
      UuKeyKind.keys => _PickTab.keyboard,
      UuKeyKind.mouse || UuKeyKind.scroll => _PickTab.mouse,
      UuKeyKind.action => _PickTab.function,
    };
  }

  bool get _canSave {
    switch (_kind) {
      case UuKeyKind.keys:
        return _keys.isNotEmpty;
      case UuKeyKind.mouse:
        return _mouse.isNotEmpty;
      case UuKeyKind.scroll:
        return _scroll != 0;
      case UuKeyKind.action:
        return _action.isNotEmpty;
    }
  }

  void _resetBinding() {
    _keys = [];
    _mouse = '';
    _scroll = 0;
    _action = '';
  }

  void _clear() {
    setState(() {
      _resetBinding();
      _kind = UuKeyKind.keys;
    });
  }

  void _tapKey(String key) {
    setState(() {
      if (_kind != UuKeyKind.keys) {
        _resetBinding();
        _kind = UuKeyKind.keys;
      }
      if (_keys.contains(key)) {
        _keys.remove(key);
      } else if (_keys.length >= 4) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('最多添加 4 个按键')),
        );
      } else {
        _keys.add(key);
      }
    });
  }

  void _selectMouse(String mouse) {
    setState(() {
      _resetBinding();
      _kind = UuKeyKind.mouse;
      _mouse = mouse;
    });
  }

  void _selectScroll(int scroll) {
    setState(() {
      _resetBinding();
      _kind = UuKeyKind.scroll;
      _scroll = scroll;
    });
  }

  void _selectAction(String action) {
    setState(() {
      _resetBinding();
      _kind = UuKeyKind.action;
      _action = action;
    });
  }

  void _save() {
    if (!_canSave) return;
    final initial = widget.initial;
    final button = UuKeyButton(
      label: initial?.label ?? '',
      kind: _kind,
      keys: _kind == UuKeyKind.keys ? List.of(_keys) : const [],
      mouse: _kind == UuKeyKind.mouse ? _mouse : '',
      scroll: _kind == UuKeyKind.scroll ? _scroll : 0,
      action: _kind == UuKeyKind.action ? _action : '',
      x: initial?.x ?? 0.5,
      y: initial?.y ?? 0.38,
      size: initial?.size ?? 54,
    );
    Navigator.of(context).pop(button);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      body: SafeArea(
        child: Column(
          children: [
            _topBar(),
            _slotStrip(),
            _tabBar(),
            Expanded(child: _tabContent()),
          ],
        ),
      ),
    );
  }

  Widget _topBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 2),
      child: Row(
        children: [
          InkWell(
            onTap: () => Navigator.of(context).pop(),
            customBorder: const CircleBorder(),
            child: Container(
              width: 38,
              height: 38,
              decoration:
                  const BoxDecoration(color: _kPanel, shape: BoxShape.circle),
              child: const Icon(Icons.chevron_left,
                  color: Colors.white, size: 24),
            ),
          ),
          const Expanded(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                '点击下方按键 添加2~4个对应按键',
                textAlign: TextAlign.center,
                maxLines: 2,
                style: TextStyle(color: _kMuted, fontSize: 12),
              ),
            ),
          ),
          InkWell(
            onTap: _clear,
            borderRadius: BorderRadius.circular(8),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Text('清空',
                  style: TextStyle(color: Colors.white, fontSize: 14)),
            ),
          ),
          const SizedBox(width: 6),
          InkWell(
            onTap: _canSave ? _save : null,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
              decoration: BoxDecoration(
                color: _canSave ? _kBlue : const Color(0xFF2A2A2C),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                '保存',
                style: TextStyle(
                  color: _canSave ? Colors.white : _kMuted,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _slotStrip() {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: _kPanel,
        borderRadius: BorderRadius.circular(14),
      ),
      child: SizedBox(
        height: 40,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: _slots(),
        ),
      ),
    );
  }

  List<Widget> _slots() {
    if (_kind == UuKeyKind.keys) {
      return [
        for (final key in _keys)
          _slotChip(uuKeyLabel(key), () => setState(() => _keys.remove(key))),
        if (_keys.length < 4) _slotPlaceholder(),
      ];
    }
    final String label;
    switch (_kind) {
      case UuKeyKind.mouse:
        label = uuMouseLabel(_mouse);
      case UuKeyKind.scroll:
        label = _scroll >= 0 ? '上滚轮' : '下滚轮';
      case UuKeyKind.action:
        label = _action == 'hide' ? '一键隐藏所有按键' : '键盘输入';
      case UuKeyKind.keys:
        label = '';
    }
    return [_slotChip(label, _clear)];
  }

  Widget _slotChip(String label, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          constraints: const BoxConstraints(minWidth: 64),
          height: 40,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: _kCap,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(label,
              style: const TextStyle(color: Colors.white, fontSize: 14)),
        ),
      ),
    );
  }

  Widget _slotPlaceholder() {
    return Container(
      width: 84,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0x66FFFFFF)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Text('请添加',
          style: TextStyle(color: _kMuted, fontSize: 13)),
    );
  }

  Widget _tabBar() {
    return Row(
      children: [
        for (final tab in _PickTab.values)
          Expanded(
            child: InkWell(
              onTap: () => setState(() => _tab = tab),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Text(
                      switch (tab) {
                        _PickTab.keyboard => '主键盘',
                        _PickTab.mouse => '鼠标按键与轮盘',
                        _PickTab.function => '功能键',
                      },
                      style: TextStyle(
                        color: _tab == tab ? Colors.white : _kMuted,
                        fontSize: 14,
                        fontWeight: _tab == tab
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                    ),
                  ),
                  Container(
                    height: 2,
                    color: _tab == tab ? _kBlue : Colors.transparent,
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _tabContent() {
    switch (_tab) {
      case _PickTab.keyboard:
        return SingleChildScrollView(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: _keyboardRows(),
              ),
            ),
          ),
        );
      case _PickTab.mouse:
        return _mouseTab();
      case _PickTab.function:
        return _functionTab();
    }
  }

  List<Widget> _keyboardRows() {
    final fKeys = <Widget>[const SizedBox(width: 2)];
    for (var i = 1; i <= 12; i++) {
      fKeys.add(_key('F$i', 'VK_F$i'));
    }
    return [
      _row(
        main: [const SizedBox(width: 4), _key('Esc', 'VK_ESCAPE', w: 56), ...fKeys],
        right: [_kbdModeToggle()],
      ),
      _row(main: [
        const SizedBox(width: 8),
        _key('`', '`'),
        for (final digit in ['1', '2', '3', '4', '5', '6', '7', '8', '9', '0'])
          _key(digit, 'VK_$digit'),
        _key('-', 'VK_MINUS'),
        _key('=', 'VK_PLUS'),
        _key('⌫', 'VK_BACK', w: 60),
      ], right: _rightKeys(0)),
      _row(main: [
        _key('Tab', 'VK_TAB', w: 58),
        for (final letter in 'QWERTYUIOP'.split('')) _key(letter, 'VK_$letter'),
        _key('[', 'VK_LBRACKET'),
        _key(']', 'VK_RBRACKET'),
        _key('\\', 'VK_BACKSLASH'),
      ], right: _rightKeys(1)),
      _row(main: [
        _key('Caps', 'VK_CAPITAL', w: 66),
        for (final letter in 'ASDFGHJKL'.split('')) _key(letter, 'VK_$letter'),
        _key(';', 'VK_SEMICOLON'),
        _key("'", 'VK_QUOTE'),
        _key('Enter', 'VK_ENTER', w: 66),
      ], right: _rightKeys(2)),
      _row(main: [
        _key('Shift', 'VK_SHIFT', w: 84),
        for (final letter in 'ZXCVBNM'.split('')) _key(letter, 'VK_$letter'),
        _key(',', 'VK_COMMA'),
        _key('.', '.'),
        _key('/', 'VK_SLASH'),
        _key('Shift', 'VK_SHIFT', w: 84),
      ], right: _rightKeys(3)),
      _row(main: [
        _key('Control', 'VK_CONTROL', w: 62),
        _key('Option', 'VK_MENU', w: 54),
        _key('Command', 'Meta', w: 70),
        _key('Space', 'VK_SPACE', w: 180),
        _key('Command', 'Meta', w: 70),
        _key('Option', 'VK_MENU', w: 54),
        _key('Control', 'VK_CONTROL', w: 62),
      ], right: _rightKeys(4)),
    ];
  }

  Widget _row({required List<Widget> main, required List<Widget> right}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 620,
          child: Row(children: main),
        ),
        const SizedBox(width: 10),
        SizedBox(width: 176, child: Row(children: right)),
      ],
    );
  }

  /// 右侧一列：控制键 / 数字键切换后占 3 行，第 4 行放滚轮旁的数字或 ↑，
  /// 第 5 行固定为方向键。
  List<Widget> _rightKeys(int row) {
    if (row == 3) {
      return _numeric
          ? [
              _key('0', 'VK_NUMPAD0', w: 54),
              _key('.', 'VK_DECIMAL', w: 54),
            ]
          : [_key('↑', 'VK_UP', w: 54)];
    }
    if (row == 4) {
      return [
        _key('←', 'VK_LEFT', w: 54),
        _key('↓', 'VK_DOWN', w: 54),
        _key('→', 'VK_RIGHT', w: 54),
      ];
    }
    if (_numeric) {
      final start = 7 - row * 3;
      return [
        for (var i = 0; i < 3; i++)
          _key('${start + i}', 'VK_NUMPAD${start + i}', w: 54),
      ];
    }
    final labels = [
      ['PrtScr', 'ScrLK', 'Pause'],
      ['Ins', 'Home', 'PgUp'],
      ['Del', 'End', 'PgDn'],
    ][row];
    final keys = [
      ['VK_SNAPSHOT', 'VK_SCROLL', 'VK_PAUSE'],
      ['VK_INSERT', 'VK_HOME', 'VK_PRIOR'],
      ['VK_DELETE', 'VK_END', 'VK_NEXT'],
    ][row];
    return [
      for (var i = 0; i < 3; i++) _key(labels[i], keys[i], w: 54),
    ];
  }

  Widget _kbdModeToggle() {
    return Padding(
      padding: const EdgeInsets.all(2),
      child: Container(
        width: 172,
        height: 44,
        decoration: BoxDecoration(
          color: _kCap,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Expanded(child: _modeHalf('控制键', !_numeric)),
            Expanded(child: _modeHalf('数字键', _numeric)),
          ],
        ),
      ),
    );
  }

  Widget _modeHalf(String label, bool active) {
    return GestureDetector(
      onTap: () => setState(() => _numeric = !_numeric),
      child: Container(
        margin: const EdgeInsets.all(3),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? const Color(0xFF545458) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? Colors.white : _kMuted,
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  Widget _key(String label, String key, {double w = 38, double h = 44}) {
    final selected = _kind == UuKeyKind.keys && _keys.contains(key);
    return Padding(
      padding: const EdgeInsets.all(2),
      child: InkWell(
        onTap: () => _tapKey(key),
        borderRadius: BorderRadius.circular(7),
        child: Container(
          width: w,
          height: h,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? _kCapHi : _kCap,
            borderRadius: BorderRadius.circular(7),
          ),
          child: Text(
            label,
            maxLines: 1,
            style: const TextStyle(color: Colors.white, fontSize: 13),
          ),
        ),
      ),
    );
  }

  Widget _mouseTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionTitle('轮盘'),
          Wrap(
            spacing: 24,
            runSpacing: 16,
            children: [
              _dPad('↑', 'VK_UP', '←', 'VK_LEFT', '↓', 'VK_DOWN', '→',
                  'VK_RIGHT'),
              _dPad('W', 'VK_W', 'A', 'VK_A', 'S', 'VK_S', 'D', 'VK_D'),
            ],
          ),
          const SizedBox(height: 22),
          const _SectionTitle('鼠标按键'),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _mouseTile('左键', 'left'),
              _mouseTile('右键', 'right'),
              _mouseTile('中键', 'middle'),
              _mouseTile('上侧键', 'back'),
              _mouseTile('下侧键', 'forward'),
            ],
          ),
          const SizedBox(height: 22),
          const _SectionTitle('滚轮'),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _scrollTile('上滚轮', 1),
              _scrollTile('下滚轮', -1),
            ],
          ),
        ],
      ),
    );
  }

  Widget _dPad(String upLabel, String upKey, String leftLabel, String leftKey,
      String downLabel, String downKey, String rightLabel, String rightKey) {
    return SizedBox(
      width: 190,
      height: 174,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 158,
            height: 158,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0x33FFFFFF)),
            ),
          ),
          Positioned(top: 0, child: _key(upLabel, upKey, w: 52, h: 52)),
          Positioned(left: 0, child: _key(leftLabel, leftKey, w: 52, h: 52)),
          Positioned(bottom: 0, child: _key(downLabel, downKey, w: 52, h: 52)),
          Positioned(right: 0, child: _key(rightLabel, rightKey, w: 52, h: 52)),
        ],
      ),
    );
  }

  Widget _mouseTile(String label, String mouse) {
    final selected = _kind == UuKeyKind.mouse && _mouse == mouse;
    return _choiceTile(label, selected, () => _selectMouse(mouse));
  }

  Widget _scrollTile(String label, int scroll) {
    final selected = _kind == UuKeyKind.scroll && _scroll == scroll;
    return _choiceTile(label, selected, () => _selectScroll(scroll));
  }

  Widget _choiceTile(String label, bool selected, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 106,
        height: 56,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? _kCapHi : _kCap,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(label,
            style: const TextStyle(color: Colors.white, fontSize: 14)),
      ),
    );
  }

  Widget _functionTab() {
    final items = <(String, String, String, IconData, bool)>[
      ('hide', '一键隐藏所有按键', '隐藏屏幕按键，只保留此按钮', Icons.visibility_off_outlined, true),
      ('keyboard', '键盘输入', '打开手机键盘输入文字', Icons.keyboard_outlined, true),
      ('', '界面快捷放大', '双指快捷缩放画面', Icons.zoom_in, false),
      ('', '鼠标右键模式', '长按画面触发右键', Icons.mouse_outlined, false),
      ('', '轮盘功能夹', '把常用按键收进轮盘', Icons.album_outlined, false),
      ('', '列表功能夹', '把常用按键收进列表', Icons.list_alt_outlined, false),
      ('', '宏按键', '按顺序执行一串按键', Icons.auto_awesome_outlined, false),
    ];
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
      child: Column(
        children: [
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _functionCard(item.$1, item.$2, item.$3, item.$4,
                  item.$5),
            ),
        ],
      ),
    );
  }

  Widget _functionCard(
      String action, String title, String subtitle, IconData icon, bool enabled) {
    final selected = enabled && _kind == UuKeyKind.action && _action == action;
    return InkWell(
      onTap: enabled
          ? () => _selectAction(action)
          : () => ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('该功能暂未支持')),
              ),
      borderRadius: BorderRadius.circular(12),
      child: Opacity(
        opacity: enabled ? 1 : 0.45,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: selected ? _kCapHi : _kPanel,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(icon, size: 22, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 15)),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style:
                            const TextStyle(color: _kMuted, fontSize: 12)),
                  ],
                ),
              ),
              if (!enabled)
                const Text('即将支持',
                    style: TextStyle(color: _kMuted, fontSize: 11))
              else if (selected)
                const Icon(Icons.check_circle, size: 20, color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(text,
          style: const TextStyle(color: _kMuted, fontSize: 13)),
    );
  }
}
