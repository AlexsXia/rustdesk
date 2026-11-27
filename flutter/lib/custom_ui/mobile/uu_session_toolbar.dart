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
            style: const TextStyle(color: _kBarLabel, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
