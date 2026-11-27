import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart' show translate;
import 'package:flutter_hbb/models/input_model.dart';
import 'package:flutter_hbb/models/model.dart';

import '../uu_defaults.dart';
import '../uu_keymap.dart';
import '../widgets/uu_feedback.dart';

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
    final isJoystick = button.kind == UuKeyKind.joystick;
    final size = button.size
        .clamp(isJoystick ? 96.0 : 36.0, isJoystick ? 160.0 : 80.0)
        .toDouble();
    final maxX = (constraints.maxWidth - size).clamp(0.0, double.infinity);
    final maxY = (constraints.maxHeight - size).clamp(0.0, double.infinity);
    final left = (button.x * constraints.maxWidth - size / 2).clamp(0.0, maxX);
    final top = (button.y * constraints.maxHeight - size / 2).clamp(0.0, maxY);
    return Positioned(
      left: left,
      top: top,
      width: size,
      height: size,
      child: isJoystick
          ? _JoystickButton(ffi: ffi, button: button)
          : _KeyHoldButton(
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
      case UuKeyKind.joystick:
        break;
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
          widget.ffi.inputModel.inputKey(key, down: false, press: false);
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
      case UuKeyKind.joystick:
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

/// 摇杆：拖动时按下对应方向键，松手全部释放；支持斜向同时按两个键。
class _JoystickButton extends StatefulWidget {
  const _JoystickButton({required this.ffi, required this.button});

  final FFI ffi;
  final UuKeyButton button;

  @override
  State<_JoystickButton> createState() => _JoystickButtonState();
}

class _JoystickButtonState extends State<_JoystickButton> {
  static const _deadZone = 0.25;

  final Set<String> _pressed = {};
  Offset _knob = Offset.zero;
  bool _active = false;

  /// 方向键顺序：上、左、下、右。
  List<String> get _keys => widget.button.keys;

  void _update(Offset local, Size size) {
    final radius = size.shortestSide / 2;
    var offset = local - Offset(size.width / 2, size.height / 2);
    final distance = offset.distance;
    if (distance > radius) offset = offset * (radius / distance);
    final nx = offset.dx / radius;
    final ny = offset.dy / radius;
    final wanted = <String>{};
    if (ny < -_deadZone) wanted.add(_keys[0]);
    if (nx < -_deadZone) wanted.add(_keys[1]);
    if (ny > _deadZone) wanted.add(_keys[2]);
    if (nx > _deadZone) wanted.add(_keys[3]);
    for (final key in _pressed.difference(wanted).toList()) {
      widget.ffi.inputModel.inputKey(key, down: false, press: false);
      _pressed.remove(key);
    }
    for (final key in wanted.difference(_pressed)) {
      widget.ffi.inputModel.inputKey(key, down: true, press: false);
      _pressed.add(key);
    }
    setState(() => _knob = offset);
  }

  void _releaseKeys() {
    for (final key in _pressed.toList()) {
      widget.ffi.inputModel.inputKey(key, down: false, press: false);
    }
    _pressed.clear();
  }

  void _end() {
    _releaseKeys();
    if (!mounted) return;
    setState(() {
      _active = false;
      _knob = Offset.zero;
    });
  }

  @override
  void dispose() {
    _releaseKeys();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RawGestureDetector(
      // 优先于远控画面的触摸手势，拖动摇杆时不会触发远端点击/拖动。
      gestures: <Type, GestureRecognizerFactory>{
        EagerGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<EagerGestureRecognizer>(
          () => EagerGestureRecognizer(),
          (recognizer) {},
        ),
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.biggest;
          final radius = size.shortestSide / 2;
          return Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: (event) {
              _active = true;
              _update(event.localPosition, size);
            },
            onPointerMove: (event) {
              if (_active) _update(event.localPosition, size);
            },
            onPointerUp: (_) => _end(),
            onPointerCancel: (_) => _end(),
            child: Container(
              decoration: BoxDecoration(
                color: _active
                    ? const Color(0xCC3B6BF6)
                    : const Color(0x73000000),
                shape: BoxShape.circle,
                border: Border.all(
                    color: const Color(0xB3FFFFFF), width: 1.2),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Icon(Icons.open_with,
                      size: radius * 0.9, color: const Color(0x66FFFFFF)),
                  Transform.translate(
                    offset: _knob,
                    child: Container(
                      width: radius * 0.7,
                      height: radius * 0.7,
                      decoration: const BoxDecoration(
                        color: Color(0xCCFFFFFF),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
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
    final controller = TextEditingController(text: translate('My profile'));
    final name = await showUuDialog<String>(
      context,
      title: translate('New profile'),
      content: UuTextField(
        controller: controller,
        autofocus: true,
        hint: translate('Profile name'),
      ),
      actions: [
        uuDialogTextButton(translate('Cancel'), () => Navigator.of(context).pop()),
        uuDialogFilledButton(translate('Create'), () {
          final text = controller.text.trim();
          Navigator.of(context).pop(text.isEmpty ? translate('My profile') : text);
        }),
      ],
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
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  translate('Key mapping profile'),
                  style: TextStyle(color: Colors.white, fontSize: 17),
                ),
              ),
              const SizedBox(height: 12),
              for (final profile in _local) _row(
                icon: Icons.keyboard_alt_outlined,
                title: profile.name,
                subtitle: profile.serverId == null ? translate('Local only') : translate('Synced'),
                selected: profile.id == selectedId,
                onTap: () => _select(profile),
              ),
              _row(
                icon: Icons.add,
                title: translate('New profile'),
                subtitle: translate('Start with a blank layout'),
                onTap: _create,
              ),
              const SizedBox(height: 18),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  translate('Online shared profiles'),
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
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  child: Text(
                    translate('No online profiles yet. Saved profiles sync to the account server automatically.'),
                    style: TextStyle(color: _kMuted, fontSize: 13),
                  ),
                )
              else
                for (final profile in _online)
                  _row(
                    icon: Icons.cloud_outlined,
                    title: profile.name,
                    subtitle: profile.author.isEmpty
                        ? translate('From server')
                        : translate('From {${profile.author}}'),
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
