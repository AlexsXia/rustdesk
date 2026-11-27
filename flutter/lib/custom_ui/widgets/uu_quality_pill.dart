import 'package:flutter/material.dart';
import 'package:flutter_hbb/models/model.dart';

import '../design/uu_tokens.dart';

/// Compact FPS / latency indicator fed by the session quality events.
class UuQualityPill extends StatelessWidget {
  const UuQualityPill({
    super.key,
    required this.ffi,
    this.height = 22,
    this.margin = const EdgeInsets.only(right: 8),
  });

  final FFI ffi;
  final double height;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: ffi.qualityMonitorModel,
      builder: (context, _) {
        final data = ffi.qualityMonitorModel.data;
        final fps = data.fps?.split(' ').first;
        final delay = data.delay;
        final parts = <String>[
          if (fps != null && fps.isNotEmpty && fps != '0') '${fps}fps',
          if (delay != null && delay.isNotEmpty) '${delay}ms',
        ];
        if (parts.isEmpty) {
          return const SizedBox.shrink();
        }
        final delayMs = int.tryParse(delay ?? '');
        final color = delayMs == null
            ? UuColors.sessionTextSecondary
            : delayMs <= 80
                ? UuColors.success
                : delayMs <= 160
                    ? UuColors.warning
                    : UuColors.danger;
        return Padding(
          padding: margin,
          child: Container(
            height: height,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: UuColors.sessionHover,
              borderRadius: BorderRadius.circular(height / 2),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration:
                      BoxDecoration(color: color, shape: BoxShape.circle),
                ),
                const SizedBox(width: 5),
                Text(
                  parts.join(' · '),
                  style: const TextStyle(
                    color: UuColors.sessionTextSecondary,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
