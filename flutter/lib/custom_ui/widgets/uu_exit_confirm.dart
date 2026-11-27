import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart' show translate;

import 'uu_feedback.dart';

/// One-shot guard for window closes that follow an exit already confirmed by
/// the custom session UI, so the window-close path does not ask twice.
bool uuWindowExitConfirmed = false;

Future<bool> uuConfirmDisconnect(
  BuildContext context, {
  String? peerName,
  int tabCount = 1,
}) {
  final message = tabCount > 1
      ? translate('This window has {$tabCount} remote sessions; disconnecting will end all of them.')
      : (peerName == null || peerName.isEmpty
          ? translate('Disconnecting will end the current remote session.')
          : translate('Disconnect from {$peerName}?'));
  return showUuConfirm(
    context,
    title: translate('Disconnect remote control'),
    message: message,
    confirmText: translate('Disconnect'),
    danger: true,
  );
}
