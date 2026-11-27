import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/models/platform_model.dart';

import '../design/uu_tokens.dart';

/// Routes the shared loading dialog through the UU card for custom clients.
void initUuFeedback() {
  if (bind.mainGetLocalOption(key: 'custom-ui') == 'N') {
    return;
  }
  OverlayDialogManager.loadingBuilder = (text, cancel, showCancel) =>
      UuLoadingDialog(text: text, showCancel: showCancel, onCancel: cancel);
}

OverlayEntry? _activeToast;
Timer? _activeToastTimer;

/// UU-style toast: one dark pill at the bottom, replaced when a new one comes.
void uuToast(String message) {
  final overlay = globalKey.currentState?.overlay;
  if (overlay == null) {
    return;
  }
  _activeToastTimer?.cancel();
  _activeToast?.remove();
  final entry = OverlayEntry(
    builder: (_) => _UuToast(message: message),
  );
  _activeToast = entry;
  overlay.insert(entry);
  _activeToastTimer = Timer(const Duration(milliseconds: 1800), () {
    if (_activeToast == entry) {
      _activeToast = null;
      entry.remove();
    }
  });
}

class _UuToast extends StatefulWidget {
  const _UuToast({required this.message});

  final String message;

  @override
  State<_UuToast> createState() => _UuToastState();
}

class _UuToastState extends State<_UuToast>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 160),
  )..forward();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    UuColors.apply(context);
    return IgnorePointer(
      child: SafeArea(
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 72),
            child: FadeTransition(
              opacity: _controller,
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.96, end: 1).animate(
                    CurvedAnimation(parent: _controller, curve: Curves.easeOut)),
                child: Container(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.8,
                  ),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
                  decoration: BoxDecoration(
                    color: UuColors.toastBackground,
                    borderRadius: BorderRadius.circular(UuRadius.pill),
                  ),
                  child: Text(
                    widget.message,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      height: 1.35,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A styled dialog frame. Returns whatever the pushed route pops.
Future<T?> showUuDialog<T>(
  BuildContext context, {
  required String title,
  String? message,
  Widget? content,
  List<Widget>? actions,
  double maxWidth = 380,
}) {
  return showDialog<T>(
    context: context,
    barrierColor: const Color(0x52000000),
    builder: (dialogContext) {
      UuColors.apply(dialogContext);
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: maxWidth,
              padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
              decoration: BoxDecoration(
                color: UuColors.surface,
                borderRadius: BorderRadius.circular(UuRadius.lg),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x24161A22),
                    blurRadius: 40,
                    offset: Offset(0, 12),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: UuColors.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (message != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      message,
                      style: TextStyle(
                        color: UuColors.textSecondary,
                        fontSize: 13,
                        height: 1.5,
                      ),
                    ),
                  ],
                  if (content != null) ...[
                    const SizedBox(height: 16),
                    content,
                  ],
                  const SizedBox(height: 20),
                  if (actions != null)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        for (var i = 0; i < actions.length; i++) ...[
                          if (i > 0) const SizedBox(width: 10),
                          actions[i],
                        ],
                      ],
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

/// Confirmation dialog; resolves to true only when confirmed.
Future<bool> showUuConfirm(
  BuildContext context, {
  required String title,
  String? message,
  String? confirmText,
  String? cancelText,
  bool danger = false,
}) async {
  final result = await showUuDialog<bool>(
    context,
    title: title,
    message: message,
    actions: [
      uuDialogTextButton(cancelText ?? translate('Cancel'),
          () => Navigator.of(context).pop(false)),
      uuDialogFilledButton(
        confirmText ?? translate('OK'),
        () => Navigator.of(context).pop(true),
        danger: danger,
      ),
    ],
  );
  return result == true;
}

Widget uuDialogTextButton(String text, VoidCallback onPressed) {
  return TextButton(
    onPressed: onPressed,
    style: TextButton.styleFrom(
      foregroundColor: UuColors.textSecondary,
      minimumSize: const Size(64, 40),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(UuRadius.md),
      ),
    ),
    child: Text(text, style: const TextStyle(fontSize: 14)),
  );
}

Widget uuDialogFilledButton(
  String text,
  VoidCallback onPressed, {
  bool danger = false,
}) {
  return FilledButton(
    onPressed: onPressed,
    style: FilledButton.styleFrom(
      backgroundColor: danger ? UuColors.danger : UuColors.primary,
      minimumSize: const Size(76, 40),
      padding: const EdgeInsets.symmetric(horizontal: 18),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(UuRadius.md),
      ),
    ),
    child: Text(text, style: const TextStyle(fontSize: 14)),
  );
}

/// Filled input used inside UU dialogs.
class UuTextField extends StatelessWidget {
  const UuTextField({
    super.key,
    required this.controller,
    this.hint,
    this.obscure = false,
    this.autofocus = false,
    this.keyboardType,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String? hint;
  final bool obscure;
  final bool autofocus;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      autofocus: autofocus,
      keyboardType: keyboardType,
      onSubmitted: onSubmitted,
      style: TextStyle(color: UuColors.textPrimary, fontSize: 15),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: UuColors.textTertiary, fontSize: 15),
        filled: true,
        fillColor: UuColors.background,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(UuRadius.md),
          borderSide: BorderSide.none,
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      ),
    );
  }
}

/// Consistent empty state block.
class UuEmptyState extends StatelessWidget {
  const UuEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    UuColors.apply(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 52, color: UuColors.textTertiary),
          const SizedBox(height: 14),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: UuColors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (message != null) ...[
            const SizedBox(height: 8),
            Text(
              message!,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: UuColors.textSecondary,
                fontSize: 13,
                height: 1.5,
              ),
            ),
          ],
          if (action != null) ...[
            const SizedBox(height: 18),
            action!,
          ],
        ],
      ),
    );
  }
}

/// Loading card used by the dialog manager while connecting.
class UuLoadingDialog extends StatelessWidget {
  const UuLoadingDialog({
    super.key,
    required this.text,
    required this.showCancel,
    required this.onCancel,
  });

  final String text;
  final bool showCancel;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    UuColors.apply(context);
    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: 260,
          padding: const EdgeInsets.fromLTRB(24, 26, 24, 18),
          decoration: BoxDecoration(
            color: UuColors.surface,
            borderRadius: BorderRadius.circular(UuRadius.lg),
            boxShadow: const [
              BoxShadow(
                color: Color(0x33161A22),
                blurRadius: 40,
                offset: Offset(0, 14),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  color: UuColors.primary,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                text,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: UuColors.textPrimary,
                  fontSize: 14,
                ),
              ),
              if (showCancel) ...[
                const SizedBox(height: 8),
                TextButton(
                  onPressed: onCancel,
                  style: TextButton.styleFrom(
                    foregroundColor: UuColors.textSecondary,
                    minimumSize: const Size(80, 40),
                  ),
                  child: Text(translate('Cancel'), style: TextStyle(fontSize: 14)),
                ),
              ] else
                const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}
