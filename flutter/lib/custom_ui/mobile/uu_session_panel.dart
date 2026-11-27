import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/common/shared_state.dart';
import 'package:flutter_hbb/common/widgets/dialog.dart';
import 'package:flutter_hbb/common/widgets/toolbar.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/models/model.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:get/get.dart';

import '../design/uu_tokens.dart';
import '../uu_defaults.dart';
import '../uu_keymap.dart';
import '../widgets/uu_exit_confirm.dart';
import '../widgets/uu_feedback.dart';
import 'uu_keymap_overlay.dart';

const _kSheetBg = Color(0xFF2C2C2E);
const _kCardBg = Color(0xFF3A3A3C);
const _kTileBg = Color(0xFF48484A);
const _kInnerBg = Color(0xFF232325);
const _kDivider = Color(0xFF48484A);
const _kMutedText = Color(0xFFAEAEB2);
const _kBlue = Color(0xFF3B6BF6);
const _kOrange = Color(0xFFFF9F0A);

/// UU 远程风格的远控“操作”面板：底部弹出的深色面板。
void showUuSessionPanel(
  BuildContext context,
  String id,
  FFI ffi, {
  VoidCallback? onChat,
  VoidCallback? onSmallWindow,
  VoidCallback? onKeymapChanged,
  VoidCallback? onEditKeymap,
}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withOpacity(0.35),
    builder: (sheetContext) {
      final media = MediaQuery.of(sheetContext);
      final landscape = media.orientation == Orientation.landscape;
      return SizedBox(
        height: math.min(
          media.size.height * (landscape ? 0.82 : 0.52),
          landscape ? 420 : 520,
        ),
        child: _UuSessionPanel(
          id: id,
          ffi: ffi,
          onChat: onChat,
          onSmallWindow: onSmallWindow,
          onKeymapChanged: onKeymapChanged,
          onEditKeymap: onEditKeymap,
        ),
      );
    },
  );
}

class _UuSessionPanel extends StatefulWidget {
  const _UuSessionPanel({
    required this.id,
    required this.ffi,
    this.onChat,
    this.onSmallWindow,
    this.onKeymapChanged,
    this.onEditKeymap,
  });

  final String id;
  final FFI ffi;
  final VoidCallback? onChat;
  final VoidCallback? onSmallWindow;
  final VoidCallback? onKeymapChanged;
  final VoidCallback? onEditKeymap;

  @override
  State<_UuSessionPanel> createState() => _UuSessionPanelState();
}

class _UuSessionPanelState extends State<_UuSessionPanel> {
  FFI get _ffi => widget.ffi;
  String get _id => widget.id;
  SessionID get _sessionId => _ffi.sessionId;

  bool get _muted => bind.sessionGetToggleOptionSync(
      sessionId: _sessionId, arg: 'disable-audio');

  bool get _viewOnly => bind.sessionGetToggleOptionSync(
      sessionId: _sessionId, arg: kOptionToggleViewOnly);

  bool get _showRemoteCursor => bind.sessionGetToggleOptionSync(
      sessionId: _sessionId, arg: 'show-remote-cursor');

  bool get _needsSecurityAttention =>
      PrivacyModeState.find(_id).value.isEmpty;

  // 关闭本面板弹出的所有 sheet，回到远控画面。
  void _closePanelRoutes() {
    if (!mounted) return;
    Navigator.of(context)
        .popUntil((route) => route is! ModalBottomSheetRoute<dynamic>);
  }

  Future<void> _toggleMute() async {
    await bind.sessionToggleOption(
        sessionId: _sessionId, value: 'disable-audio');
    if (mounted) setState(() {});
  }

  Future<void> _toggleViewOnly() async {
    final next = !_viewOnly;
    await bind.sessionToggleOption(
        sessionId: _sessionId, value: kOptionToggleViewOnly);
    _ffi.ffiModel.setViewOnly(_id, next);
    if (mounted) setState(() {});
  }

  Future<void> _setInputMode(UuInputMode mode) async {
    if (mode == uuInputModeNotifier.value) return;
    final touch = mode == UuInputMode.touch;
    if (_ffi.ffiModel.touchMode != touch) {
      _ffi.ffiModel.toggleTouchMode();
    }
    await bind.mainSetLocalOption(
        key: kOptionTouchMode, value: touch ? 'Y' : 'N');
    await setUuInputMode(mode);
    if (mounted) setState(() {});
  }

  Future<void> _toggleShowRemoteCursor(bool value) async {
    await bind.sessionToggleOption(
        sessionId: _sessionId, value: 'show-remote-cursor');
    final on = bind.sessionGetToggleOptionSync(
        sessionId: _sessionId, arg: 'show-remote-cursor');
    try {
      ShowRemoteCursorState.find(_id).value = on;
    } catch (e) {
      debugPrint('update show remote cursor state failed: $e');
    }
    if (mounted) setState(() {});
  }

  Future<void> _exitSession() async {
    final hostname = _ffi.ffiModel.pi.hostname;
    final ok = await uuConfirmDisconnect(
      context,
      peerName: hostname.isNotEmpty ? hostname : _id,
    );
    if (!ok || !mounted) return;
    _closePanelRoutes();
    clientClose(_sessionId, _ffi);
  }

  Future<void> _restartDevice() async {
    final pi = _ffi.ffiModel.pi;
    final ok = await showUuConfirm(
      context,
      title: translate('Restart remote device'),
      message: translate('Restart {${pi.hostname}($_id)}?'),
      confirmText: translate('Restart'),
      danger: true,
    );
    if (!ok || !mounted) return;
    _closePanelRoutes();
    bind.sessionRestartRemoteDevice(sessionId: _sessionId);
  }

  Future<void> _shutdownDevice() async {
    final ok = await showUuConfirm(
      context,
      title: translate('Shut down remote device'),
      message:
          translate('Shut down {${_ffi.ffiModel.pi.hostname}($_id)}? The device cannot be woken after shutdown.'),
      confirmText: translate('Shut down'),
      danger: true,
    );
    if (!mounted) return;
    if (ok) {
      _closePanelRoutes();
      bind.sessionShutdownRemoteDevice(sessionId: _sessionId);
    }
  }

  Future<void> _toggleOrientation() async {
    final landscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    _closePanelRoutes();
    await SystemChrome.setPreferredOrientations(landscape
        ? const [DeviceOrientation.portraitUp]
        : const [
            DeviceOrientation.landscapeLeft,
            DeviceOrientation.landscapeRight,
          ]);
  }

  void _lockDevice() {
    _closePanelRoutes();
    bind.sessionLockScreen(sessionId: _sessionId);
  }

  void _notSupported(String feature) {
    uuToast(translate('{$feature} is not supported yet. Stay tuned.'));
  }

  void _smallWindow() {
    _closePanelRoutes();
    final callback = widget.onSmallWindow;
    if (callback == null) {
      _notSupported(translate('Mini window'));
      return;
    }
    callback();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(11)),
      child: Container(
        color: _kSheetBg,
        child: SafeArea(
          top: false,
          child: ListView(
            padding: const EdgeInsets.only(top: 12, bottom: 18),
            children: [
              Obx(() => _needsSecurityAttention
                  ? Padding(
                      padding: const EdgeInsets.only(bottom: 9),
                      child: _securityWarning(),
                    )
                  : const SizedBox.shrink()),
              _groupTitle(translate('Quick actions')),
              _quickTiles(),
              _groupTitle(translate('Image Quality')),
              _menuCard([
                _menuRow(Icons.high_quality_outlined, translate('Image Quality'), _showQuality),
              ]),
              _groupTitle(translate('Screen')),
              _menuCard([
                _menuRow(Icons.monitor_outlined, translate('Screen'), _showScreen),
              ]),
              _groupTitle(translate('Input')),
              _keyMappingCard(),
              const SizedBox(height: 9),
              _pointerCard(),
              _groupTitle(translate('Security')),
              _menuCard([
                _menuRow(Icons.gpp_maybe_outlined, translate('Security'), _showSecurity,
                    color: _kOrange),
              ]),
              _groupTitle(translate('Tools')),
              _menuCard([
                _menuRow(Icons.usb, translate('Peripherals'), _showPeripherals),
                _menuRow(Icons.inventory_2_outlined, translate('Tools'), _showTools),
              ]),
              _groupTitle(translate('More')),
              _menuCard([
                _menuRow(Icons.grid_view, translate('More'), _showMore),
              ]),
              _groupTitle(translate('System shortcuts')),
              _menuCard([
                _menuRow(Icons.apple, translate('System shortcuts'), _showSystemShortcuts),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  Widget _securityWarning() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 13),
      child: InkWell(
        borderRadius: BorderRadius.circular(5),
        onTap: _showSecurity,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            children: [
              Icon(Icons.bolt, size: 15, color: _kOrange),
              SizedBox(width: 5),
              Text(
                translate('Privacy and security need attention'),
                style: TextStyle(
                  color: _kOrange,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _groupTitle(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
      child: Text(
        title,
        style: const TextStyle(
          color: _kMutedText,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _quickTiles() {
    final tiles = <Widget>[
      _tile(Icons.logout_rounded, translate('Exit session'), _exitSession),
      _tile(Icons.screen_rotation_outlined, translate('Rotate screen'), _toggleOrientation),
      _tile(_muted ? Icons.volume_off_outlined : Icons.volume_up_outlined,
          translate('Sound'), _toggleMute),
      _tile(Icons.visibility_outlined, translate('View only'), _toggleViewOnly,
          active: _viewOnly),
      _tile(Icons.picture_in_picture_alt_outlined, translate('Mini window'), _smallWindow),
    ];
    return SizedBox(
      height: 57,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 11),
        itemCount: tiles.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, index) => tiles[index],
      ),
    );
  }

  Widget _tile(IconData icon, String label, VoidCallback onTap,
      {bool active = false}) {
    return Material(
      color: active ? _kBlue : _kTileBg,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: SizedBox(
          width: 59,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 17, color: Colors.white),
              const SizedBox(height: 6),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _keyMappingCard() {
    final profile = uuActiveKeyProfile();
    final mappingOn = uuKeyMappingEnabled() && profile != null;
    final subtitle = profile != null
        ? translate('Current profile: {${profile.name}}')
        : translate('Pin frequently used keys on the screen and send them to the computer');
    return _card(
      Column(
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => _toggleKeyMapping(!mappingOn),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
                child: Row(
                  children: [
                    Container(
                      width: 20,
                      height: 20,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.white, width: 1.1),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: const Text(
                        'A',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            translate('Key mapping'),
                            style: TextStyle(color: Colors.white, fontSize: 12),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: _kMutedText, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    Transform.scale(
                      scale: 0.7,
                      child: Switch(
                        value: mappingOn,
                        onChanged: _toggleKeyMapping,
                        activeColor: _kBlue,
                        inactiveThumbColor: Colors.white,
                        inactiveTrackColor: const Color(0xFF5C5C60),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (mappingOn) ...[
            const Divider(height: 1, thickness: 1, color: _kDivider),
            Row(
              children: [
                Expanded(
                  child: _keymapAction(
                      Icons.checklist_rounded, translate('Choose profile'), _chooseKeymap),
                ),
                Container(width: 1, height: 29, color: _kDivider),
                Expanded(
                  child: _keymapAction(
                      Icons.edit_outlined, translate('Edit profile'), _editKeymap),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _keymapAction(IconData icon, String label, VoidCallback onTap) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 12, color: Colors.white),
              const SizedBox(width: 5),
              Text(
                label,
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _toggleKeyMapping(bool value) async {
    if (value) {
      final profile = await showUuKeymapChooser(context);
      if (profile == null) return;
      await setUuKeyMapping(true);
    } else {
      await setUuKeyMapping(false);
    }
    if (mounted) setState(() {});
    widget.onKeymapChanged?.call();
  }

  Future<void> _chooseKeymap() async {
    final profile = await showUuKeymapChooser(context);
    if (profile == null) return;
    if (mounted) setState(() {});
    widget.onKeymapChanged?.call();
  }

  void _editKeymap() {
    _closePanelRoutes();
    widget.onEditKeymap?.call();
  }

  Widget _pointerCard() {
    final mode = uuInputModeNotifier.value;
    return _card(
      Column(
        children: [
          Container(
            height: 33,
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: _kInnerBg,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              children: [
                _segment(translate('Touch'), mode == UuInputMode.touch,
                    () => _setInputMode(UuInputMode.touch)),
                _segment(translate('Mouse'), mode == UuInputMode.mouse,
                    () => _setInputMode(UuInputMode.mouse)),
                _segment(translate('Trackpad'), mode == UuInputMode.trackpad,
                    () => _setInputMode(UuInputMode.trackpad)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(7, 1, 1, 1),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    translate('Show mouse buttons'),
                    style: TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
                Transform.scale(
                  scale: 0.7,
                  child: Switch(
                    value: _showRemoteCursor,
                    onChanged: _toggleShowRemoteCursor,
                    activeColor: _kBlue,
                    inactiveThumbColor: Colors.white,
                    inactiveTrackColor: const Color(0xFF5C5C60),
                  ),
                ),
              ],
            ),
          ),
          if (mode == UuInputMode.trackpad)
            Padding(
              padding: const EdgeInsets.fromLTRB(7, 0, 7, 5),
              child: Row(
                children: [
                  Text(
                    translate('Pointer speed'),
                    style: TextStyle(color: _kMutedText, fontSize: 12),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _speedChip(
                      translate('Slow'),
                      uuPointerSpeedNotifier.value == UuPointerSpeed.slow,
                      () => _setPointerSpeed(UuPointerSpeed.slow),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: _speedChip(
                      translate('Standard'),
                      uuPointerSpeedNotifier.value == UuPointerSpeed.normal,
                      () => _setPointerSpeed(UuPointerSpeed.normal),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: _speedChip(
                      translate('Fast'),
                      uuPointerSpeedNotifier.value == UuPointerSpeed.fast,
                      () => _setPointerSpeed(UuPointerSpeed.fast),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _setPointerSpeed(UuPointerSpeed speed) async {
    if (speed == uuPointerSpeedNotifier.value) return;
    await setUuPointerSpeed(speed);
    if (mounted) setState(() {});
  }

  Widget _speedChip(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 24,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? _kBlue : _kInnerBg,
          borderRadius: BorderRadius.circular(5),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : _kMutedText,
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  Widget _segment(String label, bool selected, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? _kBlue : _kBlue.withOpacity(0),
            borderRadius: BorderRadius.circular(5),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }

  Widget _card(Widget child) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 11),
      padding: const EdgeInsets.all(3),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: _kCardBg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: child,
    );
  }

  Widget _menuCard(List<Widget> rows) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 11),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: _kCardBg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0)
              const Divider(
                height: 1,
                thickness: 1,
                indent: 11,
                color: _kDivider,
              ),
            rows[i],
          ],
        ],
      ),
    );
  }

  Widget _menuRow(IconData icon, String label, VoidCallback onTap,
      {Color color = Colors.white}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(color: color, fontSize: 13),
                ),
              ),
              const Icon(Icons.chevron_right, size: 13, color: _kMutedText),
            ],
          ),
        ),
      ),
    );
  }

  // ------------------------------- 子菜单 -------------------------------

  Future<void> _showQuality() => _openMenuSheet(translate('Image Quality'), (refresh) async {
        final quality = await toolbarImageQuality(context, _id, _ffi);
        final codec = await toolbarCodec(context, _id, _ffi);
        return [
          _SheetSection(translate('Image Quality')),
          for (final menu in quality) _radioTile(menu),
          _SheetSection(translate('Codec')),
          for (final menu in codec) _radioTile(menu),
        ];
      });

  Future<void> _showScreen() => _openMenuSheet(translate('Screen'), (refresh) async {
        final pi = _ffi.ffiModel.pi;
        final style = await toolbarViewStyle(context, _id, _ffi);
        return [
          _SheetSection(translate('Displays')),
          for (var i = 0; i < pi.displays.length; i++)
            RadioListTile<int>(
              value: i,
              groupValue: pi.currentDisplay,
              onChanged: (value) {
                if (value == null) return;
                Navigator.of(context).pop();
                openMonitorInTheSameTab(value, _ffi, pi,
                    updateCursorPos: false);
              },
              title: Text(translate('Monitor {${i + 1}}')),
            ),
          if (pi.isSupportMultiDisplay && pi.displays.length > 1)
            RadioListTile<int>(
              value: kAllDisplayValue,
              groupValue: pi.currentDisplay,
              onChanged: (value) {
                if (value == null) return;
                Navigator.of(context).pop();
                openMonitorInTheSameTab(value, _ffi, pi,
                    updateCursorPos: false);
              },
              title: Text(translate('All displays')),
            ),
          _SheetSection(translate('Display mode')),
          for (final menu in style) _radioTile(menu),
        ];
      });

  Future<void> _showPeripherals() =>
      _openMenuSheet(translate('Peripherals'), (refresh) async {
        final ffiModel = _ffi.ffiModel;
        final perms = ffiModel.permissions;
        final isDefaultConn = _ffi.connType == ConnType.defaultConn;
        final rows = <Widget>[];
        if (isDefaultConn && perms['audio'] != false) {
          rows.add(SwitchListTile(
            title: Text(translate('Sound output')),
            value: !_muted,
            onChanged: (value) {
              bind.sessionToggleOption(
                  sessionId: _sessionId, value: 'disable-audio');
              scheduleMicrotask(refresh);
            },
          ));
        }
        if (isDefaultConn && ffiModel.keyboard && perms['clipboard'] != false) {
          final disabled = bind.sessionGetToggleOptionSync(
              sessionId: _sessionId, arg: 'disable-clipboard');
          rows.add(SwitchListTile(
            title: Text(translate('Clipboard sync')),
            value: !disabled,
            onChanged: (value) {
              bind.sessionToggleOption(
                  sessionId: _sessionId, value: 'disable-clipboard');
              scheduleMicrotask(refresh);
            },
          ));
        }
        if (rows.isEmpty) {
          rows.add(ListTile(title: Text(translate('The remote device has not granted peripheral access'))));
        }
        return rows;
      });

  Future<void> _showSecurity() =>
      _openMenuSheet(translate('Security'), (refresh) async {
        final privacy =
            toolbarPrivacyMode(PrivacyModeState.find(_id), context, _id, _ffi);
        if (privacy.isEmpty) {
          return [ListTile(title: Text(translate('The remote device does not support privacy mode')))];
        }
        return [
          for (final menu in privacy) _toggleTile(menu, refresh),
        ];
      });

  Future<void> _showTools() => _openMenuSheet(translate('Tools'), (refresh) async {
        final menus = toolbarControls(context, _id, _ffi);
        return [
          if (widget.onChat != null) ...[
            _actionTile(Icons.chat_bubble_outline, translate('Send message'), () {
              Navigator.of(context).pop();
              _closePanelRoutes();
              widget.onChat!.call();
            }),
            const Divider(height: 1),
          ],
          for (final menu in menus)
            if (menu.divider)
              const Divider()
            else
              _textTile(menu),
        ];
      });

  Future<void> _showMore() => _openMenuSheet(translate('More'), (refresh) async {
        final virtualMouse = _ffi.ffiModel.virtualMouseMode;
        final keyboard = toolbarKeyboardToggles(_ffi);
        final cursor = await toolbarCursor(context, _id, _ffi);
        final display = await toolbarDisplayToggle(context, _id, _ffi);
        return [
          _SheetSection(translate('Mouse pointer mode')),
          SwitchListTile(
            title: Text(translate('Virtual mouse controls')),
            subtitle: Text(translate('Show scroll wheel and left/right buttons')),
            value: virtualMouse.showVirtualMouse,
            onChanged: (value) {
              virtualMouse.toggleVirtualMouse();
              scheduleMicrotask(refresh);
            },
          ),
          _SheetSection(translate('Gestures')),
          _actionTile(Icons.gesture, translate('Gesture guide'), () {
            Navigator.of(context).pop();
            scheduleMicrotask(_showGestureHelpSheet);
          }),
          _SheetSection(translate('Keyboard & mouse')),
          for (final menu in keyboard) _toggleTile(menu, refresh),
          for (final menu in cursor) _toggleTile(menu, refresh),
          _SheetSection(translate('Display & clipboard')),
          for (final menu in display) _toggleTile(menu, refresh),
        ];
      });

  void _showGestureHelpSheet() {
    final mode = uuInputModeNotifier.value;
    final rows = <(IconData, String, String)>[];
    var label = '';
    switch (mode) {
      case UuInputMode.trackpad:
        label = translate('Trackpad');
        rows.addAll([
          (Icons.swipe, translate('One-finger swipe'), translate('Move the pointer; swipe faster to move it faster')),
          (Icons.touch_app_outlined, translate('Tap'), translate('Left-click; tap twice quickly to double-click')),
          (Icons.swap_vert, translate('Two-finger swipe up/down'), translate('Scroll the page; pan the view when zoomed in')),
          (Icons.touch_app, translate('Two-Finger Tap'), translate('Right-click')),
          (Icons.mouse_outlined, translate('Long press and release'), translate('Right-click')),
          (Icons.pan_tool_alt_outlined, translate('Long press and drag'), translate('Hold the left button to drag windows or files')),
          (Icons.zoom_in, translate('Pinch'), translate('Zoom the screen')),
        ]);
      case UuInputMode.touch:
        label = translate('Screen touch');
        rows.addAll([
          (Icons.touch_app_outlined, translate('Tap'), translate('Tap the target position directly')),
          (Icons.pan_tool_alt_outlined, translate('One-finger drag'), translate('Hold the left button and drag')),
          (Icons.touch_app, translate('Long press'), translate('Right-click')),
          (Icons.zoom_in, translate('Pinch'), translate('Zoom the screen')),
          (Icons.swap_vert, translate('Three-finger swipe up/down'), translate('Scroll page')),
        ]);
      case UuInputMode.mouse:
        label = translate('Mouse pointer');
        rows.addAll([
          (Icons.swipe, translate('One-finger swipe'), translate('Move the mouse pointer')),
          (Icons.touch_app_outlined, translate('Tap'), translate('Left-click')),
          (Icons.touch_app, translate('Two-finger tap or long press'), translate('Right-click')),
          (Icons.zoom_in, translate('Pinch'), translate('Zoom the screen')),
          (Icons.swap_vert, translate('Three-finger swipe up/down'), translate('Scroll page')),
        ]);
    }
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: _kSheetBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(11, 18, 11, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 11),
                child: Text(
                  translate('Gesture guide'),
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(11, 4, 11, 8),
                child: Text(
                  translate('Current: {$label}'),
                  style:
                      const TextStyle(color: _kMutedText, fontSize: 12),
                ),
              ),
              for (final row in rows)
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                  child: Row(
                    children: [
                      Icon(row.$1, size: 18, color: _kBlue),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              row.$2,
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 13),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              row.$3,
                              style: const TextStyle(
                                  color: _kMutedText, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showSystemShortcuts() =>
      _openMenuSheet(translate('System shortcuts'), (refresh) async {
        final pi = _ffi.ffiModel.pi;
        final androidKeyControls = pi.platform == kPeerPlatformAndroid &&
            _ffi.ffiModel.keyboard &&
            versionCmp(pi.version, '1.2.7') >= 0;
        return [
          if (pi.platform == kPeerPlatformWindows)
            _actionTile(
                Icons.keyboard_alt_outlined, translate('Send Ctrl+Alt+Del'), () {
              Navigator.of(context).pop();
              bind.sessionCtrlAltDel(sessionId: _sessionId);
            }),
          if (androidKeyControls) ...[
            _actionTile(Icons.arrow_back_rounded, translate('Go back'),
                () => _ffi.inputModel.onMobileBack()),
            _actionTile(
                Icons.home_outlined, translate('Home'), () => _ffi.inputModel.onMobileHome()),
            _actionTile(Icons.apps_rounded, translate('App switcher'),
                () => _ffi.inputModel.onMobileApps()),
            _actionTile(Icons.volume_up_outlined, translate('Volume up'),
                () => _ffi.inputModel.onMobileVolumeUp()),
            _actionTile(Icons.volume_down_outlined, translate('Volume down'),
                () => _ffi.inputModel.onMobileVolumeDown()),
            _actionTile(Icons.power_settings_new_outlined, translate('Power button'),
                () => _ffi.inputModel.onMobilePower()),
          ],
          _actionTile(Icons.lock_outline, translate('Lock remote screen'), _lockDevice),
          _actionTile(Icons.restart_alt_rounded, translate('Restart remote device'), () {
            Navigator.of(context).pop();
            _restartDevice();
          }),
          _actionTile(Icons.power_settings_new_rounded, translate('Shut down remote device'), () {
            Navigator.of(context).pop();
            _shutdownDevice();
          }),
        ];
      });

  Future<void> _openMenuSheet(
      String title, Future<List<Widget>> Function(VoidCallback) builder) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: UuColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _UuMenuSheet(title: title, builder: builder),
    );
  }

  Widget _actionTile(IconData icon, String label, VoidCallback onTap) {
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      onTap: onTap,
    );
  }

  Widget _textTile(TTextMenu menu) {
    return ListTile(
      title: menu.getChild(),
      enabled: menu.onPressed != null,
      onTap: menu.onPressed == null
          ? null
          : () {
              Navigator.of(context).pop();
              menu.onPressed!.call();
            },
    );
  }

  Widget _toggleTile(TToggleMenu menu, VoidCallback refresh) {
    return SwitchListTile(
      title: menu.child,
      value: menu.value,
      onChanged: menu.onChanged == null
          ? null
          : (value) {
              menu.onChanged!.call(value);
              scheduleMicrotask(refresh);
            },
    );
  }

  Widget _radioTile<T>(TRadioMenu<T> menu) {
    return RadioListTile<T>(
      title: menu.child,
      value: menu.value,
      groupValue: menu.groupValue,
      onChanged: menu.onChanged == null
          ? null
          : (value) {
              menu.onChanged!.call(value);
              scheduleMicrotask(() {
                Navigator.of(context).pop();
              });
            },
    );
  }
}

class _SheetSection extends StatelessWidget {
  const _SheetSection(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
      child: Text(
        text,
        style: const TextStyle(
          color: Color(0xFF8A8F99),
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _UuMenuSheet extends StatefulWidget {
  const _UuMenuSheet({required this.title, required this.builder});

  final String title;
  final Future<List<Widget>> Function(VoidCallback) builder;

  @override
  State<_UuMenuSheet> createState() => _UuMenuSheetState();
}

class _UuMenuSheetState extends State<_UuMenuSheet> {
  late Future<List<Widget>> _future = widget.builder(_refresh);

  void _refresh() {
    if (!mounted) return;
    setState(() => _future = widget.builder(_refresh));
  }

  @override
  Widget build(BuildContext context) {
    UuColors.apply(context);
    final landscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    return SafeArea(
      top: false,
      child: FractionallySizedBox(
        heightFactor: landscape ? 0.92 : 0.72,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
              child: Row(
                children: [
                  Text(
                    widget.title,
                    style: TextStyle(
                      color: UuColors.textPrimary,
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(Icons.close, color: UuColors.textSecondary),
                  ),
                ],
              ),
            ),
            Expanded(
              child: FutureBuilder<List<Widget>>(
                future: _future,
                builder: (context, snapshot) {
                  final children = snapshot.data;
                  if (children == null) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  return ListView(children: children);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
