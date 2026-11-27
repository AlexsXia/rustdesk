import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart' show translate;
import 'package:flutter_hbb/main.dart';
import 'package:flutter_hbb/models/state_model.dart';
import 'package:get/get.dart';
import 'package:window_manager/window_manager.dart';

import 'uu_exit_confirm.dart';

const _kHoverBg = Color(0x14000000);
const _kCloseHoverBg = Color(0xFFE81123);

/// Windows 风格的右上角窗口按钮：最小化、最大化/还原、关闭。
class UuWindowControls extends StatelessWidget {
  const UuWindowControls({
    super.key,
    required this.isMainWindow,
    required this.iconColor,
  });

  final bool isMainWindow;
  final Color iconColor;

  Future<void> _minimize() async {
    if (isMainWindow) {
      await windowManager.minimize();
    } else {
      await WindowController.fromWindowId(kWindowId!).minimize();
    }
  }

  Future<void> _toggleMaximize() async {
    if (isMainWindow) {
      final maximized = await windowManager.isMaximized();
      if (maximized) {
        await windowManager.unmaximize();
      } else {
        await windowManager.maximize();
      }
      stateGlobal.setMaximized(!maximized);
    } else {
      final wc = WindowController.fromWindowId(kWindowId!);
      final maximized = await wc.isMaximized();
      if (maximized) {
        await wc.unmaximize();
      } else {
        await wc.maximize();
      }
      stateGlobal.setMaximized(!maximized);
    }
  }

  Future<void> _close(BuildContext context) async {
    if (isMainWindow) {
      await windowManager.close();
      return;
    }
    if (!await uuConfirmDisconnect(context)) {
      return;
    }
    uuWindowExitConfirmed = true;
    await WindowController.fromWindowId(kWindowId!).close();
  }

  Widget _button({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
    bool isClose = false,
  }) {
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 600),
      child: InkWell(
        onTap: onTap,
        hoverColor: isClose ? _kCloseHoverBg : _kHoverBg,
        child: SizedBox(
          width: 44,
          height: 32,
          child: Icon(icon, size: 15, color: iconColor),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _button(
              icon: Icons.remove,
              tooltip: translate('Minimize'),
              onTap: _minimize,
            ),
            _button(
              icon: stateGlobal.isMaximized.isTrue
                  ? Icons.filter_none
                  : Icons.crop_square,
              tooltip: stateGlobal.isMaximized.isTrue ? translate('Restore window') : translate('Maximize'),
              onTap: _toggleMaximize,
            ),
            _button(
              icon: Icons.close,
              tooltip: translate('Close'),
              onTap: () => _close(context),
              isClose: true,
            ),
          ],
        ));
  }
}
