import 'package:flutter/material.dart';

/// Shared design tokens for the UU-style UI.
///
/// Accent and session colors are fixed; surface and text colors resolve from
/// the active Material theme. Call [apply] at the start of a page build so the
/// palette follows the app's light/dark setting and the page rebuilds when the
/// theme changes.
class UuColors {
  UuColors._();

  static bool _dark = false;

  static bool get isDark => _dark;

  static void apply(BuildContext context) {
    _dark = Theme.of(context).brightness == Brightness.dark;
  }

  static const primary = Color(0xFF2563EB);
  static const primaryDeep = Color(0xFF1D4FD8);
  static const success = Color(0xFF22C55E);
  static const warning = Color(0xFFF59E0B);
  static const danger = Color(0xFFEF4444);

  /// Readable amber for warning icons and accents on [warningSoft].
  static const warningInk = Color(0xFFD97706);

  static Color get primarySoft =>
      _dark ? const Color(0xFF20345C) : const Color(0xFFD7E3FF);

  /// Brand-blue wash for interactive hover states; one hue everywhere so a
  /// hovered row never reads as a different grey from its neighbours.
  static Color get hoverTint => primarySoft;

  static Color get textPrimary =>
      _dark ? const Color(0xFFF2F4F8) : const Color(0xFF161A22);
  static Color get textSecondary =>
      _dark ? const Color(0xFFA3AAB8) : const Color(0xFF7B8291);
  static Color get textTertiary =>
      _dark ? const Color(0xFF717A8A) : const Color(0xFF9CA3AF);

  static Color get background =>
      _dark ? const Color(0xFF131418) : const Color(0xFFF3F5FA);
  static Color get surface =>
      _dark ? const Color(0xFF1C1E24) : Colors.white;
  static Color get surfaceAlt =>
      _dark ? const Color(0xFF17191E) : const Color(0xFFF8F9FB);
  static Color get divider =>
      _dark ? const Color(0xFF2A2D35) : const Color(0xFFEDF0F5);
  static Color get border =>
      _dark ? const Color(0xFF343842) : const Color(0xFFE5E7EB);
  static Color get hover =>
      _dark ? const Color(0xFF262A32) : const Color(0xFFF3F4F6);
  static Color get hoverStrong =>
      _dark ? const Color(0xFF2D323C) : const Color(0xFFE9ECF2);
  static Color get offline =>
      _dark ? const Color(0xFF596273) : const Color(0xFFBFC5D0);
  static Color get warningSoft =>
      _dark ? const Color(0xFF2E2413) : const Color(0xFFFFF7E6);
  static Color get warningBorder =>
      _dark ? const Color(0xFF4A3A18) : const Color(0xFFFFE0A3);

  // Dark session chrome.
  static const sessionBar = Color(0xFF141416);
  static const sessionSheet = Color(0xFF2C2C2E);
  static const sessionCard = Color(0xFF3A3A3C);
  static const sessionTile = Color(0xFF48484A);
  static const sessionInner = Color(0xFF232325);
  static const sessionLine = Color(0xFF2C2C2E);
  static const sessionDivider = Color(0xFF48484A);
  static const sessionText = Color(0xFFF2F2F7);
  static const sessionTextSecondary = Color(0xFFB4B4BA);
  static const sessionMuted = Color(0xFF9A9AA2);
  static const sessionPrimary = Color(0xFF3B6BF6);
  static const sessionHover = Color(0xFF232327);
  static const sessionHoverTint = Color(0xFF223052);
  static const sessionMenu = Color(0xFF1C1C1E);
  static const dangerOnDark = Color(0xFFFF5A5F);
  static const toastBackground = Color(0xF21F1F24);
}

class UuTextSize {
  UuTextSize._();

  static const display = 28.0;
  static const title = 22.0;
  static const headline = 18.0;
  static const body = 16.0;
  static const label = 14.0;
  static const caption = 12.0;
}

class UuSpace {
  UuSpace._();

  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;
}

class UuRadius {
  UuRadius._();

  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 20.0;
  static const pill = 999.0;
}

