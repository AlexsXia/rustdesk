import 'package:flutter/material.dart';

import 'design/uu_tokens.dart';

/// Shared colors and dimensions for the custom UU-style UI.
class UuTheme {
  UuTheme._();

  static const Color accent = UuColors.primary;
  static Color get accentSoft => UuColors.primarySoft;
  static Color get background => UuColors.background;
  static Color get surface => UuColors.surface;
  static Color get textPrimary => UuColors.textPrimary;
  static Color get textSecondary => UuColors.textSecondary;
  static Color get divider => UuColors.divider;
  static const Color online = UuColors.success;
  static Color get offline => UuColors.offline;

  static const double cardRadius = UuRadius.lg;
  static const double pagePadding = UuSpace.xl;

  static const List<BoxShadow> cardShadow = [
    BoxShadow(
      color: Color(0x14161A22),
      blurRadius: 20,
      offset: Offset(0, 8),
    ),
  ];
}
