import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart' show translate;
import 'package:flutter_hbb/models/model.dart';

const _kKbBg = Color(0xFF1C1C1E);
const _kHeaderBg = Color(0xFF171719);
const _kKeyBg = Color(0xFF5A5A5E);
const _kBlue = Color(0xFF3B6BF6);
const _kText = Color(0xFFF2F2F7);
const _kInactiveTab = Color(0xFFD0D0D5);

/// UU 风格的键盘切换条：输入法 / 电脑键盘。
class UuKeyboardHeader extends StatelessWidget {
  const UuKeyboardHeader({
    Key? key,
    required this.pcSelected,
    required this.onImeKeyboard,
    required this.onPcKeyboard,
    required this.onClose,
  }) : super(key: key);

  final bool pcSelected;
  final VoidCallback onImeKeyboard;
  final VoidCallback onPcKeyboard;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 46,
      color: _kHeaderBg,
      child: Row(
        children: [
          const SizedBox(width: 16),
          _tab(translate('IME'), !pcSelected, onImeKeyboard),
          const SizedBox(width: 22),
          _tab(translate('Computer keyboard'), pcSelected, onPcKeyboard),
          const Spacer(),
          IconButton(
            onPressed: onClose,
            icon: const Icon(Icons.close, size: 20, color: _kText),
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }

  Widget _tab(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? _kBlue : _kInactiveTab,
            fontSize: 16,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

/// UU 风格的“电脑键盘”：直接向远端发送按键事件，中文交给远端输入法。
class UuPcKeyboard extends StatefulWidget {
  const UuPcKeyboard({
    Key? key,
    required this.ffi,
    required this.onImeKeyboard,
    required this.onClose,
  }) : super(key: key);

  final FFI ffi;
  final VoidCallback onImeKeyboard;
  final VoidCallback onClose;

  @override
  State<UuPcKeyboard> createState() => _UuPcKeyboardState();
}

class _UuPcKeyboardState extends State<UuPcKeyboard> {
  void _tap(String name) => widget.ffi.inputModel.inputKey(name);

  void _toggleModifier(String which) {
    setState(() {
      final input = widget.ffi.inputModel;
      switch (which) {
        case 'ctrl':
          input.ctrl = !input.ctrl;
          break;
        case 'alt':
          input.alt = !input.alt;
          break;
        case 'shift':
          input.shift = !input.shift;
          break;
        case 'cmd':
          input.command = !input.command;
          break;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final input = widget.ffi.inputModel;
    final rows = <List<Widget>>[
      [
        _key('esc', () => _tap('VK_ESCAPE'), flex: 1.2, fontSize: 12),
        for (var i = 1; i <= 9; i++)
          _key('$i', () => _tap('VK_$i')),
        _key('0', () => _tap('VK_0')),
        _key('', () => _tap('VK_BACK'), flex: 1.6, icon: Icons.backspace_outlined),
      ],
      [
        _key('tab', () => _tap('VK_TAB'), flex: 1.4, fontSize: 12),
        for (final c in 'qwertyuiop'.split(''))
          _key(c, () => _tap('VK_${c.toUpperCase()}')),
        _key('-', () => _tap('VK_MINUS')),
        _key('=', () => _tap('VK_PLUS')),
      ],
      [
        for (final c in 'asdfghjkl'.split(''))
          _key(c, () => _tap('VK_${c.toUpperCase()}')),
        _key(';', () => _tap('VK_SEMICOLON')),
        _key("'", () => _tap('VK_QUOTE')),
        _key('return', () => _tap('VK_ENTER'), flex: 1.7, fontSize: 12),
      ],
      [
        _key('shift', () => _toggleModifier('shift'),
            flex: 1.5, active: input.shift, fontSize: 12),
        for (final c in 'zxcvbnm'.split(''))
          _key(c, () => _tap('VK_${c.toUpperCase()}')),
        _key(',', () => _tap('VK_COMMA')),
        _key('.', () => _tap('.')),
        _key('/', () => _tap('VK_SLASH')),
        _key('shift', () => _toggleModifier('shift'),
            flex: 1.5, active: input.shift, fontSize: 12),
      ],
      [
        _key('ctrl', () => _toggleModifier('ctrl'),
            flex: 1.4, active: input.ctrl, fontSize: 12),
        _key('alt', () => _toggleModifier('alt'),
            flex: 1.2, active: input.alt, fontSize: 12),
        _key('cmd', () => _toggleModifier('cmd'),
            flex: 1.4, active: input.command, fontSize: 12),
        _key('', () => _tap('VK_SPACE'), flex: 4.5, icon: Icons.space_bar),
        _key('', () => _tap('VK_LEFT'), icon: Icons.keyboard_arrow_left),
        _key('', () => _tap('VK_UP'), icon: Icons.keyboard_arrow_up),
        _key('', () => _tap('VK_DOWN'), icon: Icons.keyboard_arrow_down),
        _key('', () => _tap('VK_RIGHT'), icon: Icons.keyboard_arrow_right),
      ],
    ];
    return Container(
      decoration: const BoxDecoration(
        color: _kKbBg,
        border: Border(top: BorderSide(color: Color(0xFF2C2C2E), width: 0.5)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            UuKeyboardHeader(
              pcSelected: true,
              onImeKeyboard: widget.onImeKeyboard,
              onPcKeyboard: () {},
              onClose: widget.onClose,
            ),
            for (final row in rows)
              SizedBox(height: 42, child: Row(children: row)),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }

  Widget _key(String label, VoidCallback onTap,
      {double flex = 1,
      bool active = false,
      double fontSize = 15,
      IconData? icon}) {
    return Expanded(
      flex: (flex * 100).round(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2.5, vertical: 3),
        child: Material(
          color: active ? _kBlue : _kKeyBg,
          borderRadius: BorderRadius.circular(6),
          child: InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: onTap,
            child: Center(
              child: icon != null
                  ? Icon(icon, size: 18, color: _kText)
                  : Text(
                      label,
                      maxLines: 1,
                      style: TextStyle(color: _kText, fontSize: fontSize),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
