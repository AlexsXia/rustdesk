import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart' show translate;
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/models/model.dart';
import 'package:flutter_hbb/models/platform_model.dart';

import '../uu_defaults.dart';

const _kBarBg = Color(0xFF141416);
const _kBarIcon = Color(0xFFF2F2F7);
const _kBarLabel = Color(0xFFB4B4BA);
const _kBarLine = Color(0xFF2C2C2E);

/// UU 远程风格的远控底栏：展开所有窗口 / 显示桌面 / 键盘 / 静音 / 操作。
class UuSessionToolbar extends StatefulWidget {
  const UuSessionToolbar({
    Key? key,
    required this.ffi,
    required this.onKeyboard,
    required this.onPanel,
  }) : super(key: key);

  final FFI ffi;
  final VoidCallback onKeyboard;
  final VoidCallback onPanel;

  @override
  State<UuSessionToolbar> createState() => _UuSessionToolbarState();
}

class _UuSessionToolbarState extends State<UuSessionToolbar> {
  FFI get ffi => widget.ffi;

  bool get _isMac => ffi.ffiModel.pi.platform == kPeerPlatformMacOS;
  bool get _isWin => ffi.ffiModel.pi.platform == kPeerPlatformWindows;

  bool get _muted => bind.sessionGetToggleOptionSync(
      sessionId: ffi.sessionId, arg: 'disable-audio');

  bool get _audioAllowed =>
      ffi.connType == ConnType.defaultConn &&
      ffi.ffiModel.permissions['audio'] != false;

  void _sendKey(String name,
      {bool ctrl = false, bool alt = false, bool command = false}) {
    bind.sessionInputKey(
      sessionId: ffi.sessionId,
      name: name,
      down: false,
      press: true,
      alt: alt,
      ctrl: ctrl,
      shift: false,
      command: command,
    );
  }

  // Windows 任务视图是 Win+Tab。macOS 的 Mission Control（Ctrl+↑）在不少机器上被关闭，
  // 而“应用窗口”（Ctrl+↓）是默认开启的，用它展示当前应用的所有窗口。
  void _showAllWindows() {
    if (_isMac) {
      _sendKey('VK_DOWN', ctrl: true);
    } else {
      _sendKey('VK_TAB', command: true);
    }
  }

  // Windows 显示桌面是 Win+D。macOS 的 F11 显示桌面可被系统设置关闭，
  // 改为隐藏当前应用和其它应用，效果同样露出桌面。
  void _showDesktop() {
    if (_isMac) {
      _sendKey('VK_H', command: true);
      _sendKey('VK_H', command: true, alt: true);
    } else {
      _sendKey('VK_D', command: true);
    }
  }

  Future<void> _toggleMute() async {
    await bind.sessionToggleOption(
        sessionId: ffi.sessionId, value: 'disable-audio');
    if (mounted) setState(() {});
  }

  Future<void> _togglePointerMode() async {
    final next = uuInputModeNotifier.value == UuInputMode.trackpad
        ? UuInputMode.touch
        : UuInputMode.trackpad;
    final touch = next == UuInputMode.touch;
    if (ffi.ffiModel.touchMode != touch) {
      ffi.ffiModel.toggleTouchMode();
    }
    await bind.mainSetLocalOption(
        key: kOptionTouchMode, value: touch ? 'Y' : 'N');
    await setUuInputMode(next);
  }

  @override
  Widget build(BuildContext context) {
    final landscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    return Container(
      decoration: const BoxDecoration(
        color: _kBarBg,
        border: Border(top: BorderSide(color: _kBarLine, width: 0.5)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: landscape ? 52 : 60,
          child: ValueListenableBuilder<UuInputMode>(
            valueListenable: uuInputModeNotifier,
            builder: (context, mode, _) {
              final muted = _muted;
              final items = <Widget>[
                if (_isMac || _isWin) ...[
                  _item(Icons.grid_view_rounded, translate('All windows'), _showAllWindows),
                  _item(Icons.desktop_windows_outlined, translate('Show desktop'), _showDesktop),
                ],
                _item(
                  mode == UuInputMode.trackpad
                      ? Icons.touch_app_outlined
                      : Icons.mouse_outlined,
                  mode == UuInputMode.trackpad
                      ? translate('Trackpad')
                      : (mode == UuInputMode.touch ? translate('Touch') : translate('Mouse')),
                  _togglePointerMode,
                ),
                _item(Icons.keyboard_outlined, translate('Keyboard'), widget.onKeyboard),
                if (_audioAllowed)
                  _item(
                    muted ? Icons.volume_off_outlined : Icons.volume_up_outlined,
                    muted ? translate('Muted') : translate('Mute'),
                    _toggleMute,
                  ),
                _item(Icons.tune_rounded, translate('Actions'), widget.onPanel),
              ];
              return Row(
                children: [
                  for (final item in items) Expanded(child: item),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _item(IconData icon, String label, VoidCallback onTap) {
    return _UuToolbarItem(icon: icon, label: label, onTap: onTap);
  }
}

class _UuToolbarItem extends StatefulWidget {
  const _UuToolbarItem({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  State<_UuToolbarItem> createState() => _UuToolbarItemState();
}

class _UuToolbarItemState extends State<_UuToolbarItem> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? 0.92 : 1,
        duration: const Duration(milliseconds: 90),
        curve: Curves.easeOut,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: _pressed ? const Color(0x1FFFFFFF) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(widget.icon, size: 23, color: _kBarIcon),
              const SizedBox(height: 4),
              Text(
                widget.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: _kBarLabel, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
