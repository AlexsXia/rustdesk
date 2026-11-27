import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/models/model.dart';
import 'package:flutter_hbb/models/platform_model.dart';

import '../design/uu_tokens.dart';
import '../widgets/uu_quality_pill.dart';

/// Auto-hiding status bar over the custom UI mobile session: back, device name,
/// link quality, display switch and the more menu.
class UuSessionTopBar extends StatefulWidget {
  const UuSessionTopBar({
    super.key,
    required this.id,
    required this.ffi,
    required this.onExit,
    required this.onMore,
  });

  final String id;
  final FFI ffi;
  final VoidCallback onExit;
  final VoidCallback onMore;

  @override
  State<UuSessionTopBar> createState() => _UuSessionTopBarState();
}

class _UuSessionTopBarState extends State<UuSessionTopBar> {
  static const _autoHideDelay = Duration(seconds: 3);

  bool _visible = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _show());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _show() {
    if (!mounted) return;
    setState(() => _visible = true);
    _timer?.cancel();
    _timer = Timer(_autoHideDelay, () {
      if (mounted) setState(() => _visible = false);
    });
  }

  void _hide() {
    _timer?.cancel();
    if (mounted) setState(() => _visible = false);
  }

  String get _name {
    final alias = bind.mainGetPeerOptionSync(id: widget.id, key: 'alias');
    return alias.isNotEmpty ? alias : widget.id;
  }

  void _switchDisplay() {
    final pi = widget.ffi.ffiModel.pi;
    if (pi.displays.length < 2 || pi.currentDisplay < 0) return;
    final next = (pi.currentDisplay + 1) % pi.displays.length;
    openMonitorInTheSameTab(next, widget.ffi, pi, updateCursorPos: false);
    _show();
  }

  Widget _iconButton(Widget icon, String tooltip, VoidCallback onPressed) {
    return IconButton(
      tooltip: tooltip,
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
      onPressed: onPressed,
      icon: icon,
    );
  }

  @override
  Widget build(BuildContext context) {
    final hidden = SafeArea(
      key: const ValueKey('uu-session-bar-hidden'),
      bottom: false,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _show,
        onVerticalDragDown: (_) => _show(),
        child: const SizedBox(height: 28, width: double.infinity),
      ),
    );
    final bar = SafeArea(
      key: const ValueKey('uu-session-bar'),
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _show,
          child: Container(
            height: 44,
            decoration: BoxDecoration(
              color: UuColors.sessionSheet.withOpacity(0.96),
              borderRadius: BorderRadius.circular(12),
            ),
            child: AnimatedBuilder(
              animation: widget.ffi.ffiModel,
              builder: (context, _) {
                final pi = widget.ffi.ffiModel.pi;
                final displayCount = pi.displays.length;
                final displayIndex = pi.currentDisplay;
                return Row(
                  children: [
                    _iconButton(
                      const Icon(Icons.arrow_back_rounded,
                          size: 20, color: UuColors.sessionText),
                      translate('Exit session'),
                      widget.onExit,
                    ),
                    Expanded(
                      child: Row(
                        children: [
                          Flexible(
                            child: Text(
                              _name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: UuColors.sessionText,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          UuQualityPill(
                            ffi: widget.ffi,
                            margin: EdgeInsets.zero,
                          ),
                        ],
                      ),
                    ),
                    if (displayCount > 1)
                      _iconButton(
                        Text(
                          displayIndex >= 0
                              ? '${displayIndex + 1}/$displayCount'
                              : translate('All'),
                          style: const TextStyle(
                            color: UuColors.sessionTextSecondary,
                            fontSize: 12,
                          ),
                        ),
                        translate('Switch display'),
                        _switchDisplay,
                      ),
                    _iconButton(
                      const Icon(Icons.grid_view_rounded,
                          size: 18, color: UuColors.sessionText),
                      translate('More'),
                      () {
                        _hide();
                        widget.onMore();
                      },
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      child: _visible ? bar : hidden,
    );
  }
}
