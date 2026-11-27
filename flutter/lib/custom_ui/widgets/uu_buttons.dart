import 'package:flutter/material.dart';

import '../design/uu_tokens.dart';

/// Icon button with the UU hover fill and a short press-in scale.
class UuHoverIconButton extends StatefulWidget {
  const UuHoverIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.iconSize = 20,
    this.size = 32,
    this.color,
    this.tooltip = '',
  });

  final IconData icon;
  final VoidCallback onTap;
  final double iconSize;
  final double size;
  final Color? color;
  final String tooltip;

  @override
  State<UuHoverIconButton> createState() => _UuHoverIconButtonState();
}

class _UuHoverIconButtonState extends State<UuHoverIconButton> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    Widget button = MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
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
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              color: _hovered
                  ? UuColors.hoverTint
                  : UuColors.hoverTint.withOpacity(0),
              borderRadius: BorderRadius.circular(UuRadius.pill),
            ),
            child: Center(
              child: Icon(
                widget.icon,
                size: widget.iconSize,
                color: _hovered
                    ? UuColors.primary
                    : widget.color ?? UuColors.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
    if (widget.tooltip.isNotEmpty) {
      button = Tooltip(
        message: widget.tooltip,
        waitDuration: const Duration(milliseconds: 600),
        child: button,
      );
    }
    return button;
  }
}

/// Quiet grey pill button (copy / secondary actions).
class UuSoftButton extends StatefulWidget {
  const UuSoftButton({
    super.key,
    required this.label,
    required this.onTap,
    this.height = 38,
    this.radius = UuRadius.sm,
    this.fontSize = 13,
    this.padding = const EdgeInsets.symmetric(horizontal: 16),
  });

  final String label;
  final VoidCallback onTap;
  final double height;
  final double radius;
  final double fontSize;
  final EdgeInsetsGeometry padding;

  @override
  State<UuSoftButton> createState() => _UuSoftButtonState();
}

class _UuSoftButtonState extends State<UuSoftButton> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _pressed ? 0.97 : 1,
          duration: const Duration(milliseconds: 90),
          curve: Curves.easeOut,
          child: Container(
            height: widget.height,
            padding: widget.padding,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _hovered ? UuColors.primarySoft : UuColors.hover,
              borderRadius: BorderRadius.circular(widget.radius),
            ),
            child: Text(
              widget.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: UuColors.textPrimary,
                fontSize: widget.fontSize,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Primary blue button with hover darkening and press feedback.
class UuPrimaryButton extends StatefulWidget {
  const UuPrimaryButton({
    super.key,
    required this.label,
    required this.onTap,
    this.height = 40,
    this.radius = UuRadius.sm,
    this.fontSize = 14,
    this.padding = const EdgeInsets.symmetric(horizontal: 20),
  });

  final String label;
  final VoidCallback onTap;
  final double height;
  final double radius;
  final double fontSize;
  final EdgeInsetsGeometry padding;

  @override
  State<UuPrimaryButton> createState() => _UuPrimaryButtonState();
}

class _UuPrimaryButtonState extends State<UuPrimaryButton> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final background =
        _hovered ? UuColors.primaryDeep : UuColors.primary;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _pressed ? 0.97 : 1,
          duration: const Duration(milliseconds: 90),
          curve: Curves.easeOut,
          child: Container(
            height: widget.height,
            padding: widget.padding,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(widget.radius),
              boxShadow: _hovered
                  ? [
                      BoxShadow(
                        color: UuColors.primary.withOpacity(0.28),
                        blurRadius: 14,
                        offset: const Offset(0, 5),
                      ),
                    ]
                  : null,
            ),
            child: Text(
              widget.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white,
                fontSize: widget.fontSize,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
