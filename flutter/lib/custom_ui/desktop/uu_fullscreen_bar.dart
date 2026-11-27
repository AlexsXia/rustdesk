import 'dart:async';

import 'package:flutter/material.dart';

import '../../desktop/pages/remote_page.dart';
import '../design/uu_tokens.dart';
import '../widgets/uu_quality_pill.dart';
import 'uu_remote_tab_bar.dart';

/// Floating tab-bar replacement while a remote window is fullscreen: reveals
/// when the mouse reaches the top edge and hides itself again after idle.
class UuFullscreenTopBar extends StatefulWidget {
  const UuFullscreenTopBar({
    super.key,
    required this.page,
    required this.onExit,
  });

  final RemotePage page;
  final VoidCallback onExit;

  @override
  State<UuFullscreenTopBar> createState() => _UuFullscreenTopBarState();
}

class _UuFullscreenTopBarState extends State<UuFullscreenTopBar> {
  static const _visibleDuration = Duration(seconds: 3);
  static const _hideDelay = Duration(milliseconds: 600);

  bool _visible = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _reveal();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _reveal() {
    if (!mounted) return;
    if (!_visible) setState(() => _visible = true);
    _restartTimer(_visibleDuration);
  }

  void _restartTimer(Duration duration) {
    _timer?.cancel();
    _timer = Timer(duration, () {
      if (mounted && _visible) setState(() => _visible = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final bar = Center(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {},
        child: Container(
          margin: const EdgeInsets.only(top: 6),
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: UuColors.sessionBar.withOpacity(0.92),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: UuColors.sessionLine),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              UuQualityPill(
                ffi: widget.page.ffi,
                margin: const EdgeInsets.only(left: 6, right: 4),
              ),
              UuControlMenu(page: widget.page, onExit: widget.onExit),
            ],
          ),
        ),
      ),
    );
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: MouseRegion(
        onHover: (_) {
          if (!_visible) {
            setState(() => _visible = true);
          }
          _restartTimer(_visibleDuration);
        },
        onExit: (_) => _restartTimer(_hideDelay),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: _visible
              ? bar
              : const SizedBox(height: 6, width: double.infinity),
        ),
      ),
    );
  }
}
