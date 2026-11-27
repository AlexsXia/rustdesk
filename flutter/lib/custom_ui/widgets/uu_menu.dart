import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show KeyDownEvent, LogicalKeyboardKey;

import '../design/uu_tokens.dart';

/// Palette for a [UuMenu]. The light style follows the app theme; [session]
/// matches the dark chrome shown above a remote desktop.
class UuMenuStyle {
  const UuMenuStyle({
    required this.background,
    required this.text,
    required this.muted,
    required this.hover,
    required this.divider,
    required this.border,
    required this.selected,
    required this.danger,
    this.dark = false,
  });

  final Color background;
  final Color text;
  final Color muted;
  final Color hover;
  final Color divider;
  final Color border;
  final Color selected;
  final Color danger;
  final bool dark;

  static UuMenuStyle get light => UuMenuStyle(
        background: UuColors.surface,
        text: UuColors.textPrimary,
        muted: UuColors.textSecondary,
        hover: UuColors.hoverTint,
        divider: UuColors.divider,
        border: UuColors.border,
        selected: UuColors.primary,
        danger: UuColors.danger,
        dark: UuColors.isDark,
      );

  static const session = UuMenuStyle(
    background: UuColors.sessionMenu,
    text: UuColors.sessionText,
    muted: UuColors.sessionMuted,
    hover: UuColors.sessionHoverTint,
    divider: UuColors.sessionDivider,
    border: UuColors.sessionLine,
    selected: UuColors.success,
    danger: UuColors.dangerOnDark,
    dark: true,
  );
}

abstract class UuMenuEntry<T> {
  const UuMenuEntry();
}

class UuMenuItem<T> extends UuMenuEntry<T> {
  const UuMenuItem({
    required this.value,
    required this.label,
    this.icon,
    this.selected = false,
    this.danger = false,
    this.enabled = true,
    this.trailing,
    this.height = 42,
  });

  final T value;
  final String label;
  final IconData? icon;
  final bool selected;
  final bool danger;
  final bool enabled;
  final Widget? trailing;
  final double height;
}

class UuMenuCaption<T> extends UuMenuEntry<T> {
  const UuMenuCaption({required this.label, this.icon});

  final String label;
  final IconData? icon;
}

class UuMenuDivider<T> extends UuMenuEntry<T> {
  const UuMenuDivider();
}

/// Shows a UU-styled menu below [anchorRect] and resolves to the tapped value.
Future<T?> showUuMenu<T>(
  BuildContext context, {
  required Rect anchorRect,
  required List<UuMenuEntry<T>> entries,
  double width = 216,
  double? maxHeight,
  UuMenuStyle? style,
  Offset offset = Offset.zero,
}) {
  return Navigator.of(context).push(_UuMenuRoute<T>(
    anchorRect: anchorRect.shift(offset),
    entries: entries,
    width: width,
    maxHeight: maxHeight,
    style: style,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
  ));
}

/// Drop-in replacement for [PopupMenuButton] that opens a [showUuMenu].
class UuMenuButton<T> extends StatelessWidget {
  const UuMenuButton({
    super.key,
    required this.entriesBuilder,
    required this.onSelected,
    this.child,
    this.icon,
    this.tooltip = '',
    this.width = 216,
    this.maxHeight,
    this.style,
    this.offset = Offset.zero,
    this.iconSize = 18,
    this.iconButtonSize = 32,
  }) : assert(child != null || icon != null, 'Provide a child or an icon');

  final List<UuMenuEntry<T>> Function(BuildContext context) entriesBuilder;
  final ValueChanged<T> onSelected;
  final Widget? child;
  final IconData? icon;
  final String tooltip;
  final double width;
  final double? maxHeight;
  final UuMenuStyle? style;
  final Offset offset;
  final double iconSize;
  final double iconButtonSize;

  @override
  Widget build(BuildContext context) {
    Widget target = child ??
        _UuIconTarget(
          icon: icon!,
          iconSize: iconSize,
          size: iconButtonSize,
        );
    if (tooltip.isNotEmpty) {
      target = Tooltip(
        message: tooltip,
        waitDuration: const Duration(milliseconds: 600),
        child: target,
      );
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () async {
        final box = context.findRenderObject() as RenderBox?;
        if (box == null || !box.attached || !box.hasSize) {
          return;
        }
        final value = await showUuMenu<T>(
          context,
          anchorRect: box.localToGlobal(Offset.zero) & box.size,
          entries: entriesBuilder(context),
          width: width,
          maxHeight: maxHeight,
          style: style,
          offset: offset,
        );
        if (value != null) {
          onSelected(value);
        }
      },
      child: target,
    );
  }
}

class _UuIconTarget extends StatefulWidget {
  const _UuIconTarget({
    required this.icon,
    required this.iconSize,
    required this.size,
  });

  final IconData icon;
  final double iconSize;
  final double size;

  @override
  State<_UuIconTarget> createState() => _UuIconTargetState();
}

class _UuIconTargetState extends State<_UuIconTarget> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
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
            color: _hovered ? UuColors.primary : UuColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _UuMenuRoute<T> extends PopupRoute<T> {
  _UuMenuRoute({
    required this.anchorRect,
    required this.entries,
    required this.width,
    required this.maxHeight,
    required this.style,
    required this.barrierLabel,
  });

  final Rect anchorRect;
  final List<UuMenuEntry<T>> entries;
  final double width;
  final double? maxHeight;
  final UuMenuStyle? style;

  @override
  final String? barrierLabel;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 130);

  @override
  Color? get barrierColor => null;

  @override
  bool get barrierDismissible => true;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return CustomSingleChildLayout(
      delegate: _UuMenuLayout(anchorRect: anchorRect),
      child: _UuMenuPanel<T>(
        entries: entries,
        width: width,
        maxHeight: maxHeight,
        style: style,
      ),
    );
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
    final screenWidth = MediaQuery.of(context).size.width;
    return FadeTransition(
      opacity: curved,
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.96, end: 1).animate(curved),
        alignment: anchorRect.center.dx > screenWidth / 2
            ? Alignment.topRight
            : Alignment.topLeft,
        child: child,
      ),
    );
  }
}

class _UuMenuLayout extends SingleChildLayoutDelegate {
  _UuMenuLayout({required this.anchorRect});

  final Rect anchorRect;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints.loose(constraints.biggest);

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    const margin = 8.0;
    const gap = 6.0;
    var left = anchorRect.left;
    if (left + childSize.width > size.width - margin) {
      left = size.width - childSize.width - margin;
    }
    if (left < margin) {
      left = margin;
    }
    var top = anchorRect.bottom + gap;
    if (top + childSize.height > size.height - margin) {
      final above = anchorRect.top - gap - childSize.height;
      top = above >= margin
          ? above
          : math.max(margin, size.height - childSize.height - margin);
    }
    return Offset(left, top);
  }

  @override
  bool shouldRelayout(covariant _UuMenuLayout oldDelegate) =>
      oldDelegate.anchorRect != anchorRect;
}

class _UuMenuPanel<T> extends StatelessWidget {
  const _UuMenuPanel({
    required this.entries,
    required this.width,
    required this.maxHeight,
    required this.style,
  });

  final List<UuMenuEntry<T>> entries;
  final double width;
  final double? maxHeight;
  final UuMenuStyle? style;

  @override
  Widget build(BuildContext context) {
    UuColors.apply(context);
    final resolved = style ?? UuMenuStyle.light;
    final limit =
        math.max(80.0, maxHeight ?? MediaQuery.of(context).size.height - 16);
    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          Navigator.of(context).maybePop();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Material(
        type: MaterialType.transparency,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: limit),
          child: Container(
            width: width,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
            decoration: BoxDecoration(
              color: resolved.background,
              borderRadius: BorderRadius.circular(UuRadius.md),
              border: Border.all(color: resolved.border),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(resolved.dark ? 0.45 : 0.16),
                  blurRadius: 28,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: SingleChildScrollView(
              padding: EdgeInsets.zero,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final entry in entries)
                    _buildEntry(context, entry, resolved),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEntry(
    BuildContext context,
    UuMenuEntry<T> entry,
    UuMenuStyle style,
  ) {
    if (entry is UuMenuDivider<T>) {
      return Container(
        height: 1,
        margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        color: style.divider,
      );
    }
    if (entry is UuMenuCaption<T>) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Row(
          children: [
            if (entry.icon != null) ...[
              Icon(entry.icon, size: 16, color: style.muted),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Text(
                entry.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: style.muted, fontSize: 12),
              ),
            ),
          ],
        ),
      );
    }
    return _UuMenuRow<T>(item: entry as UuMenuItem<T>, style: style);
  }
}

class _UuMenuRow<T> extends StatefulWidget {
  const _UuMenuRow({required this.item, required this.style});

  final UuMenuItem<T> item;
  final UuMenuStyle style;

  @override
  State<_UuMenuRow<T>> createState() => _UuMenuRowState<T>();
}

class _UuMenuRowState<T> extends State<_UuMenuRow<T>> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final style = widget.style;
    final labelColor =
        item.danger ? style.danger : style.text;
    final iconColor = item.danger ? style.danger : style.muted;
    return Semantics(
      button: true,
      enabled: item.enabled,
      child: MouseRegion(
        cursor:
            item.enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: item.enabled
              ? () => Navigator.of(context).pop(item.value)
              : null,
          child: Container(
            height: item.height,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: _hovered && item.enabled
                  ? style.hover
                  : style.hover.withOpacity(0),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                if (item.icon != null) ...[
                  Icon(item.icon, size: 18, color: iconColor),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Text(
                    item.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: item.enabled ? labelColor : style.muted,
                      fontSize: 14,
                    ),
                  ),
                ),
                if (item.selected) ...[
                  const SizedBox(width: 8),
                  Icon(Icons.check, size: 15, color: style.selected),
                ],
                if (item.trailing != null) ...[
                  const SizedBox(width: 8),
                  item.trailing!,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
