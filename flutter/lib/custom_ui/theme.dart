import 'package:flutter/material.dart';

/// Shared colors and dimensions for the custom UU-style UI.
class UuTheme {
  UuTheme._();

  static const Color accent = Color(0xFF2563EB);
  static const Color accentSoft = Color(0xFFEAF0FF);
  static const Color background = Color(0xFFF3F5FA);
  static const Color surface = Colors.white;
  static const Color textPrimary = Color(0xFF161A22);
  static const Color textSecondary = Color(0xFF7B8291);
  static const Color divider = Color(0xFFEDF0F5);
  static const Color online = Color(0xFF22C55E);
  static const Color offline = Color(0xFFBFC5D0);

  static const double cardRadius = 18;
  static const double pagePadding = 28;

  static const List<BoxShadow> cardShadow = [
    BoxShadow(
      color: Color(0x14161A22),
      blurRadius: 20,
      offset: Offset(0, 8),
    ),
  ];
}
