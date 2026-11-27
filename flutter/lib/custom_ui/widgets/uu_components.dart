import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart' show translate;

import '../design/uu_tokens.dart';

/// White rounded surface used across the UU pages.
class UuCard extends StatelessWidget {
  const UuCard({
    super.key,
    required this.child,
    this.padding,
    this.color,
    this.radius = UuRadius.lg,
    this.bordered = false,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final Color? color;
  final double radius;
  final bool bordered;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: color ?? UuColors.surface,
        borderRadius: BorderRadius.circular(radius),
        border: bordered ? Border.all(color: UuColors.divider) : null,
      ),
      padding: padding,
      child: child,
    );
  }
}

class UuSectionTitle extends StatelessWidget {
  const UuSectionTitle(
    this.title, {
    super.key,
    this.trailing,
    this.padding = const EdgeInsets.only(left: 2, bottom: 10),
  });

  final String title;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    UuColors.apply(context);
    return Padding(
      padding: padding,
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: UuColors.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// Pill button matching the tokens' primary/ghost styles.
class UuPillButton extends StatelessWidget {
  const UuPillButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.filled = true,
    this.danger = false,
    this.height = 38,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool filled;
  final bool danger;
  final double height;

  @override
  Widget build(BuildContext context) {
    final color = danger ? UuColors.danger : UuColors.primary;
    final fg = filled ? Colors.white : (danger ? color : UuColors.textPrimary);
    return SizedBox(
      height: height,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: filled ? color : UuColors.surface,
          foregroundColor: fg,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(UuRadius.pill),
            side: filled
                ? BorderSide.none
                : BorderSide(color: danger ? color : UuColors.border),
          ),
        ).copyWith(
          backgroundColor: MaterialStateProperty.resolveWith((states) {
            if (!filled) return UuColors.surface;
            final hovered = states.contains(MaterialState.hovered) ||
                states.contains(MaterialState.pressed);
            if (!hovered) return color;
            return danger ? const Color(0xFFDC2626) : UuColors.primaryDeep;
          }),
          overlayColor: MaterialStateProperty.resolveWith((states) {
            if (filled) return Colors.transparent;
            final active = states.contains(MaterialState.hovered) ||
                states.contains(MaterialState.pressed);
            if (!active) return Colors.transparent;
            return danger
                ? UuColors.danger.withOpacity(0.08)
                : UuColors.hoverTint;
          }),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 17),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Rounded search input shared by the desktop sidebar and mobile device page.
class UuSearchField extends StatelessWidget {
  const UuSearchField({
    super.key,
    required this.controller,
    this.hint,
    this.onChanged,
    this.height = 36,
    this.focusNode,
  });

  final TextEditingController controller;
  final String? hint;
  final ValueChanged<String>? onChanged;
  final double height;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        onChanged: onChanged,
        style: TextStyle(color: UuColors.textPrimary, fontSize: 13),
        decoration: InputDecoration(
          hintText: hint ?? translate('Search devices'),
          hintStyle:
              TextStyle(color: UuColors.textTertiary, fontSize: 13),
          prefixIcon: Icon(Icons.search,
              size: 18, color: UuColors.textTertiary),
          prefixIconConstraints: const BoxConstraints(minWidth: 34),
          isDense: true,
          filled: true,
          fillColor: UuColors.background,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(UuRadius.md),
            borderSide: BorderSide.none,
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        ),
      ),
    );
  }
}
