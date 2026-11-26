import 'package:flutter/material.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/models/model.dart';
import 'package:flutter_hbb/models/platform_model.dart';

const _kBarBg = Color(0xFF141416);
const _kBarIcon = Color(0xFFF2F2F7);
const _kBarLabel = Color(0xFFB4B4BA);
const _kBarLine = Color(0xFF2C2C2E);

/// UU 远程风格的远控底栏：展开所有窗口 / 显示桌面 / 键盘 / 操作。
class UuSessionToolbar extends StatelessWidget {
  const UuSessionToolbar({
    Key? key,
    required this.ffi,
    required this.onKeyboard,
    required this.onPanel,
  }) : super(key: key);

  final FFI ffi;
  final VoidCallback onKeyboard;
  final VoidCallback onPanel;

  bool get _isMac => ffi.ffiModel.pi.platform == kPeerPlatformMacOS;
  bool get _isWin => ffi.ffiModel.pi.platform == kPeerPlatformWindows;

  void _sendKey(String name, {bool ctrl = false, bool command = false}) {
    bind.sessionInputKey(
      sessionId: ffi.sessionId,
      name: name,
      down: false,
      press: true,
      alt: false,
      ctrl: ctrl,
      shift: false,
      command: command,
    );
  }

  // macOS 调度中心是 Control+↑，Windows 任务视图是 Win+Tab。
  void _showAllWindows() {
    if (_isMac) {
      _sendKey('VK_UP', ctrl: true);
    } else {
      _sendKey('VK_TAB', command: true);
    }
  }

  // macOS 显示桌面是 F11，Windows 是 Win+D。
  void _showDesktop() {
    if (_isMac) {
      _sendKey('VK_F11');
    } else {
      _sendKey('VK_D', command: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = <Widget>[
      if (_isMac || _isWin) ...[
        _item(Icons.grid_view_rounded, '展开所有窗口', _showAllWindows),
        _item(Icons.desktop_windows_outlined, '显示桌面', _showDesktop),
      ],
      _item(Icons.keyboard_outlined, '键盘', onKeyboard),
      _item(Icons.tune_rounded, '操作', onPanel),
    ];
    return Container(
      decoration: const BoxDecoration(
        color: _kBarBg,
        border: Border(top: BorderSide(color: _kBarLine, width: 0.5)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 60,
          child: Row(
            children: [for (final item in items) Expanded(child: item)],
          ),
        ),
      ),
    );
  }

  Widget _item(IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 23, color: _kBarIcon),
          const SizedBox(height: 4),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: _kBarLabel, fontSize: 11),
          ),
        ],
      ),
    );
  }
}
