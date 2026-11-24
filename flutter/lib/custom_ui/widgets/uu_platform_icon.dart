import 'package:flutter/material.dart';

import '../theme.dart';

class UuPlatformIcon extends StatelessWidget {
  const UuPlatformIcon(this.platform, {super.key, this.size = 44});

  final String platform;
  final double size;

  @override
  Widget build(BuildContext context) {
    final value = platform.toLowerCase();
    IconData icon = Icons.desktop_windows;
    if (value.contains('mac')) {
      icon = Icons.laptop_mac;
    } else if (value.contains('linux')) {
      icon = Icons.computer;
    } else if (value.contains('android')) {
      icon = Icons.phone_android;
    } else if (value.contains('ios') || value.contains('iphone')) {
      icon = Icons.phone_iphone;
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: UuTheme.accentSoft,
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      child: Icon(icon, color: UuTheme.accent, size: size * 0.5),
    );
  }
}
