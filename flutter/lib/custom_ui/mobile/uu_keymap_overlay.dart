import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hbb/models/input_model.dart';
import 'package:flutter_hbb/models/model.dart';

import '../uu_defaults.dart';
import '../uu_keymap.dart';

const _kSheetBg = Color(0xFF2C2C2E);
const _kRowBg = Color(0xFF3A3A3C);
const _kMuted = Color(0xFFAEAEB2);
const _kBlue = Color(0xFF3B6BF6);

/// 叠加在远控画面上的按键方案：按住按钮即向电脑发送对应按键。
class UuKeymapOverlay extends StatelessWidget {
  const UuKeymapOverlay({super.key, required this.ffi, this.onKeyboardInput});

  final FFI ffi;
  final VoidCallback? onKeyboardInput;

  @override
  Widget build(BuildContext context) {
    if (!uuKeyMappingEnabled()) return const SizedBox.shrink();
    final profile = uuActiveKeyProfile();
    if (profile == null) return const SizedBox.shrink();
    final hidden = uuKeymapHidden.value;
    final buttons = hidden
        ? profile.keys
            .where((button) =>
                button.kind == UuKeyKind.action && button.action == 'hide')
            .toList()
        : profile.keys;
    return LayoutBuilder(
      builder: (context, constraints) => Stack(
        children: [
          for (final button in buttons)
            _positionedButton(constraints, button),
        ],
      ),
    );
  }

  Widget _positionedButton(BoxConstraints constraints, UuKeyButton button) {
    final size = button.size.clamp(36.0, 80.0).toDouble();
    final maxX = (constraints.maxWidth - size).clamp(0.0, double.infinity);
    final maxY = (constraints.maxHeight - size).clamp(0.0, double.infinity);
    final left = (button.x * constraints.maxWidth - size / 2).clamp(0.0, maxX);
    final top = (button.y * constraints.maxHeight - size / 2).clamp(0.0, maxY);
    return Positioned(
      left: left,
      top: top,
      width: size,
      height: size,
      child: _KeyHoldButton(
        ffi: ffi,
        button: button,
        onKeyboardInput: onKeyboardInput,
      ),
    );
  }
}

class _KeyHoldButton extends StatefulWidget {
  const _KeyHoldButton({
    required this.ffi,
    required this.button,
    this.onKeyboardInput,
  });

  final FFI ffi;
  final UuKeyButton button;
  final VoidCallback? onKeyboardInput;

  @override
  State<_KeyHoldButton> createState() => _KeyHoldButtonState();
}

class _KeyHoldButtonState extends State<_KeyHoldButton> {
  bool _pressed = false;
  Timer? _scrollTimer;

  static MouseButtons _mouseButton(String name) {
    switch (name) {
      case 'right':
        return MouseButtons.right;
      case 'middle':
        return MouseButtons.wheel;
      case 'back':
        return MouseButtons.back;
      case 'forward':
        return MouseButtons.forward;
      default:
        return MouseButtons.left;
    }
  }

  void _runAction(String action) {
    if (action == 'hide') {
      uuKeymapHidden.value = !uuKeymapHidden.value;
    } else if (action == 'keyboard') {
      widget.onKeyboardInput?.call();
    }
    setState(() => _pressed = true);
    Timer(const Duration(milliseconds: 120), () {
      if (mounted) setState(() => _pressed = false);
    });
  }

  void _down() {
    final button = widget.button;
    switch (button.kind) {
      case UuKeyKind.keys:
        setState(() => _pressed = true);
        for (final key in uuChordDownOrder(button.keys)) {
          widget.ffi.inputModel.inputKey(key, down: true, press: false);
        }
      case UuKeyKind.mouse:
        setState(() => _pressed = true);
        widget.ffi.inputModel.tapDown(_mouseButton(button.mouse));
      case UuKeyKind.scroll:
        setState(() => _pressed = true);
        widget.ffi.inputModel.scroll(button.scroll);
        _scrollTimer?.cancel();
        _scrollTimer =
            Timer.periodic(const Duration(milliseconds: 90), (_) {
          widget.ffi.inputModel.scroll(button.scroll);
        });
      case UuKeyKind.action:
        _runAction(button.action);
    }
  }

  void _up() {
    final button = widget.button;
    _scrollTimer?.cancel();
    _scrollTimer = null;
    switch (button.kind) {
      case UuKeyKind.keys:
        if (!_pressed) return;
        setState(() => _pressed = false);
        for (final key in uuChordDownOrder(button.keys).reversed) {
          widget.ffi.inputModel.inputKey(key);
        }
      case UuKeyKind.mouse:
        if (!_pressed) return;
        setState(() => _pressed = false);
        widget.ffi.inputModel.tapUp(_mouseButton(button.mouse));
      case UuKeyKind.scroll:
        if (!_pressed) return;
        setState(() => _pressed = false);
      case UuKeyKind.action:
        break;
    }
  }

  @override
  void dispose() {
    _scrollTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RawGestureDetector(
      // 优先于远控画面的触摸手势，避免按方案按键时同时触发远端点击/拖动。
      gestures: <Type, GestureRecognizerFactory>{
        EagerGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<EagerGestureRecognizer>(
          () => EagerGestureRecognizer(),
          (recognizer) {},
        ),
      },
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (_) => _down(),
        onPointerUp: (_) => _up(),
        onPointerCancel: (_) => _up(),
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _pressed ? const Color(0xCC3B6BF6) : const Color(0x73000000),
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xB3FFFFFF), width: 1.2),
          ),
          child: Text(
            widget.button.displayLabel,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              height: 1.1,
            ),
          ),
        ),
      ),
    );
  }
}

/// 选择（或新建）按键方案。返回选中的方案，取消时返回 null。
Future<UuKeyProfile?> showUuKeymapChooser(BuildContext context) {
  return showModalBottomSheet<UuKeyProfile>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withOpacity(0.35),
    builder: (_) => const _UuKeymapChooserSheet(),
  );
}

class _UuKeymapChooserSheet extends StatefulWidget {
  const _UuKeymapChooserSheet();

  @override
  State<_UuKeymapChooserSheet> createState() => _UuKeymapChooserSheetState();
}

class _UuKeymapChooserSheetState extends State<_UuKeymapChooserSheet> {
  List<UuKeyProfile> _local = [];
  List<UuKeyProfile> _online = [];
  bool _loadingOnline = true;

  @override
  void initState() {
    super.initState();
    _local = loadUuKeyProfiles();
    _loadOnline();
  }

  Future<void> _loadOnline() async {
    final profiles = await fetchUuKeymapProfiles();
    if (!mounted) return;
    setState(() {
      _online = profiles;
      _loadingOnline = false;
    });
  }

  Future<void> _select(UuKeyProfile profile) async {
    await selectUuKeyProfile(profile.id);
    if (mounted) Navigator.of(context).pop(profile);
  }

  Future<void> _create() async {
    final controller = TextEditingController(text: '我的方案');
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('新建方案'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: '方案名称'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              final text = controller.text.trim();
              Navigator.pop(dialogContext, text.isEmpty ? '我的方案' : text);
            },
            child: const Text('创建'),
          ),
        ],
      ),
    );
    if (name == null) return;
    final profile = uuNewKeyProfile(name);
    await upsertUuKeyProfile(profile);
    await _select(profile);
  }

  Future<void> _useOnline(UuKeyProfile online) async {
    // 下载成一份本地方案，避免编辑他人方案时改动服务器上的原记录。
    final profile = UuKeyProfile(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: online.name,
      keys: [for (final key in online.keys) key.copy()],
    );
    await upsertUuKeyProfile(profile);
    await _select(profile);
  }

  @override
  Widget build(BuildContext context) {
    final selectedId = uuActiveKeyProfile()?.id;
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      child: Container(
        color: _kSheetBg,
        height: MediaQuery.of(context).size.height * 0.66,
        child: SafeArea(
          top: false,
          child: ListView(
            padding: const EdgeInsets.only(top: 18, bottom: 24),
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  '按键映射方案',
                  style: TextStyle(color: Colors.white, fontSize: 17),
                ),
              ),
              const SizedBox(height: 12),
              for (final profile in _local) _row(
                icon: Icons.keyboard_alt_outlined,
                title: profile.name,
                subtitle: profile.serverId == null ? '仅本机' : '已同步',
                selected: profile.id == selectedId,
                onTap: () => _select(profile),
              ),
              _row(
                icon: Icons.add,
                title: '新建方案',
                subtitle: '从空白布局开始',
                onTap: _create,
              ),
              const SizedBox(height: 18),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  '在线共享方案',
                  style: TextStyle(color: _kMuted, fontSize: 15),
                ),
              ),
              const SizedBox(height: 8),
              if (_loadingOnline)
                const Padding(
                  padding: EdgeInsets.all(20),
                  child: Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                )
              else if (_online.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  child: Text(
                    '暂无在线方案，保存方案后会自动同步到账号服务器',
                    style: TextStyle(color: _kMuted, fontSize: 13),
                  ),
                )
              else
                for (final profile in _online)
                  _row(
                    icon: Icons.cloud_outlined,
                    title: profile.name,
                    subtitle: profile.author.isEmpty
                        ? '来自服务器'
                        : '来自 ${profile.author}',
                    onTap: () => _useOnline(profile),
                  ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    bool selected = false,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 5, 16, 5),
      child: Material(
        color: _kRowBg,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Icon(icon, size: 22, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style:
                            const TextStyle(color: Colors.white, fontSize: 15),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: const TextStyle(color: _kMuted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                if (selected)
                  const Icon(Icons.check_circle, size: 20, color: _kBlue),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
