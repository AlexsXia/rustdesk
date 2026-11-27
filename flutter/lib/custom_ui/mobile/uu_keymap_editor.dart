import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart' show translate;
import 'package:flutter_hbb/models/model.dart';

import '../uu_keymap.dart';
import '../widgets/uu_feedback.dart';
import 'uu_keymap_picker.dart';

/// 全屏编辑按键方案：拖动按键调整位置，可增删按键。
Future<bool> openUuKeymapEditor(
    BuildContext context, FFI ffi, UuKeyProfile profile) async {
  final changed = await Navigator.of(context).push<bool>(
    MaterialPageRoute(
      builder: (_) => UuKeymapEditorPage(ffi: ffi, profile: profile),
    ),
  );
  return changed ?? false;
}

class UuKeymapEditorPage extends StatefulWidget {
  const UuKeymapEditorPage({super.key, required this.ffi, required this.profile});

  final FFI ffi;
  final UuKeyProfile profile;

  @override
  State<UuKeymapEditorPage> createState() => _UuKeymapEditorPageState();
}

class _UuKeymapEditorPageState extends State<UuKeymapEditorPage> {
  late final UuKeyProfile _profile = widget.profile.copy();
  int? _selected;
  bool _saving = false;

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    await upsertUuKeyProfile(_profile);
    final serverId = await uploadUuKeyProfile(_profile);
    if (serverId != null && serverId != _profile.serverId) {
      _profile.serverId = serverId;
      await upsertUuKeyProfile(_profile);
    }
    if (!mounted) return;
    Navigator.of(context).pop(true);
    uuToast(serverId != null ? translate('Profile saved and synced to the server') : translate('Profile saved locally'));
  }

  Future<void> _addKey() async {
    final picked = await openUuKeyPicker(context);
    if (picked == null || !mounted) return;
    setState(() {
      picked.x = 0.5;
      picked.y = 0.35;
      _profile.keys.add(picked);
      _selected = _profile.keys.length - 1;
    });
  }

  Future<void> _editSelected() async {
    final index = _selected;
    if (index == null || index >= _profile.keys.length) return;
    final current = _profile.keys[index];
    final picked = await openUuKeyPicker(context, initial: current);
    if (picked == null || !mounted) return;
    setState(() {
      picked.x = current.x;
      picked.y = current.y;
      picked.size = current.size;
      _profile.keys[index] = picked;
    });
  }

  Future<void> _renameSelected() async {
    final index = _selected;
    if (index == null || index >= _profile.keys.length) return;
    final button = _profile.keys[index];
    final controller = TextEditingController(text: button.label);
    final name = await showUuDialog<String>(
      context,
      title: translate('Key name'),
      content: UuTextField(
        controller: controller,
        autofocus: true,
        hint: translate('Leave empty to show: {${button.displayLabel}}'),
      ),
      actions: [
        uuDialogTextButton(translate('Cancel'), () => Navigator.of(context).pop()),
        uuDialogFilledButton(
            translate('OK'), () => Navigator.of(context).pop(controller.text.trim())),
      ],
    );
    if (name == null || !mounted) return;
    setState(() => button.label = name);
  }

  void _deleteSelected() {
    final index = _selected;
    if (index == null || index >= _profile.keys.length) return;
    setState(() {
      _profile.keys.removeAt(index);
      _selected = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final height = constraints.maxHeight;
          return Stack(
            children: [
              Positioned.fill(child: _frameView()),
              for (var i = 0; i < _profile.keys.length; i++)
                _editorButton(i, width, height),
              Positioned(top: 0, left: 0, right: 0, child: _topBar()),
              Positioned(bottom: 0, left: 0, right: 0, child: _bottomBar()),
            ],
          );
        },
      ),
    );
  }

  Widget _frameView() {
    return ColoredBox(
      color: Colors.black,
      child: ListenableBuilder(
        listenable: widget.ffi.imageModel,
        builder: (_, __) {
          final image = widget.ffi.imageModel.image;
          if (image == null) {
            return Center(
              child: Text(translate('Loading screen...'), style: TextStyle(color: Colors.white54)),
            );
          }
          return Center(
            child: FittedBox(
              fit: BoxFit.contain,
              child: RawImage(image: image),
            ),
          );
        },
      ),
    );
  }

  Widget _editorButton(int index, double width, double height) {
    final button = _profile.keys[index];
    final isJoystick = button.kind == UuKeyKind.joystick;
    final size = button.size
        .clamp(isJoystick ? 96.0 : 36.0, isJoystick ? 160.0 : 80.0)
        .toDouble();
    final maxX = (width - size).clamp(0.0, double.infinity);
    final maxY = (height - size).clamp(0.0, double.infinity);
    final left = (button.x * width - size / 2).clamp(0.0, maxX);
    final top = (button.y * height - size / 2).clamp(0.0, maxY);
    final selected = _selected == index;
    return Positioned(
      left: left,
      top: top,
      width: size,
      height: size,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _selected = index),
        onPanStart: (_) => setState(() => _selected = index),
        onPanUpdate: (details) => setState(() {
          button.x = (button.x + details.delta.dx / width).clamp(0.03, 0.97);
          button.y = (button.y + details.delta.dy / height).clamp(0.03, 0.97);
        }),
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? const Color(0xCC3B6BF6) : const Color(0x73000000),
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? Colors.white : const Color(0xB3FFFFFF),
              width: selected ? 2 : 1.2,
            ),
          ),
          child: Text(
            button.displayLabel,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.1),
          ),
        ),
      ),
    );
  }

  Widget _topBar() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xCC000000), Color(0x00000000)],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(translate('Cancel'), style: TextStyle(color: Colors.white)),
              ),
              Expanded(
                child: Text(
                  _profile.name,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                ),
              ),
              TextButton(
                onPressed: _saving ? null : _save,
                child: Text(
                  _saving ? translate('Saving...') : translate('Save'),
                  style: const TextStyle(
                    color: Color(0xFF3B6BF6),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bottomBar() {
    final hasSelection =
        _selected != null && _selected! < _profile.keys.length;
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Color(0xCC000000), Color(0x00000000)],
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          child: Row(
            children: [
              _bottomAction(Icons.add, translate('Add key'), _addKey),
              const SizedBox(width: 10),
              if (hasSelection) ...[
                _bottomAction(Icons.tune, translate('Edit'), _editSelected),
                const SizedBox(width: 10),
                _bottomAction(Icons.badge_outlined, translate('Name'), _renameSelected),
                const SizedBox(width: 10),
                _bottomAction(
                  Icons.delete_outline,
                  translate('Delete'),
                  _deleteSelected,
                  color: const Color(0xFFFF453A),
                ),
              ],
              const Spacer(),
              if (!hasSelection)
                Text(
                  translate('Drag keys to adjust their positions'),
                  style: TextStyle(color: Color(0xCCFFFFFF), fontSize: 12),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bottomAction(IconData icon, String label, VoidCallback onTap,
      {Color color = Colors.white}) {
    return Material(
      color: const Color(0x99000000),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 6),
              Text(label, style: TextStyle(color: color, fontSize: 14)),
            ],
          ),
        ),
      ),
    );
  }
}
