import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';

/// One platform-icon mapping shared by every UU screen.
class UuPeerPlatformIcon {
  UuPeerPlatformIcon._();

  static IconData iconFor(String platform) {
    final p = platform.toLowerCase();
    if (p.contains('mac')) {
      return Icons.apple;
    }
    if (p.contains('win')) {
      return Icons.desktop_windows;
    }
    if (p.contains('ios') || p.contains('iphone') || p.contains('ipad')) {
      return Icons.phone_iphone;
    }
    if (p.contains('android')) {
      return Icons.phone_android;
    }
    if (p.contains('linux')) {
      return Icons.computer;
    }
    return Icons.devices_other;
  }

  static IconData localIcon() {
    if (isWindows) {
      return Icons.desktop_windows;
    }
    if (isMacOS) {
      return Icons.apple;
    }
    if (isLinux) {
      return Icons.computer;
    }
    return Icons.devices_other;
  }
}
