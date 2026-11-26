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

import '../uu_defaults.dart';
import '../uu_keymap.dart';
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
  VoidCallback? onShowGestureHelp,
  VoidCallback? onSmallWindow,
  VoidCallback? onKeymapChanged,
  VoidCallback? onEditKeymap,
}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withOpacity(0.35),
    builder: (sheetContext) => SizedBox(
      height: math.min(MediaQuery.of(sheetContext).size.height * 0.62, 720),
      child: _UuSessionPanel(
        id: id,
        ffi: ffi,
        onChat: onChat,
        onShowGestureHelp: onShowGestureHelp,
        onSmallWindow: onSmallWindow,
        onKeymapChanged: onKeymapChanged,
        onEditKeymap: onEditKeymap,
      ),
    ),
  );
}

class _UuSessionPanel extends StatefulWidget {
  const _UuSessionPanel({
    required this.id,
    required this.ffi,
    this.onChat,
    this.onShowGestureHelp,
    this.onSmallWindow,
    this.onKeymapChanged,
    this.onEditKeymap,
  });

  final String id;
  final FFI ffi;
  final VoidCallback? onChat;
  final VoidCallback? onShowGestureHelp;
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

  bool get _touchMode => _ffi.ffiModel.touchMode;

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

  void _toggleTouchMode(bool touchMode) {
    if (touchMode == _touchMode) return;
    _ffi.ffiModel.toggleTouchMode();
    bind.mainSetLocalOption(
        key: kOptionTouchMode, value: touchMode ? 'Y' : 'N');
    setState(() {});
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

  void _exitSession() {
    _closePanelRoutes();
    clientClose(_sessionId, _ffi);
  }

  void _restartDevice() {
    _closePanelRoutes();
    showRestartRemoteDevice(
        _ffi.ffiModel.pi, _id, _sessionId, _ffi.dialogManager);
  }

  Future<void> _shutdownDevice() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('关闭远程设备'),
        content: Text(
            '确定要关机 ${_ffi.ffiModel.pi.hostname}($_id) 吗？关机后将无法再唤醒设备。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFE5484D)),
            child: const Text('关机'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (ok == true) {
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
    showToast('$feature暂不支持，敬请期待');
  }

  void _smallWindow() {
    _closePanelRoutes();
    final callback = widget.onSmallWindow;
    if (callback == null) {
      _notSupported('小窗模式');
      return;
    }
    callback();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      child: Container(
        color: _kSheetBg,
        child: SafeArea(
          top: false,
          child: ListView(
            padding: const EdgeInsets.only(top: 18, bottom: 28),
            children: [
              Obx(() => _needsSecurityAttention
                  ? Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: _securityWarning(),
                    )
                  : const SizedBox.shrink()),
              _quickTiles(),
              const SizedBox(height: 26),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  '操作',
                  style: TextStyle(color: _kMutedText, fontSize: 17),
                ),
              ),
              const SizedBox(height: 14),
              _keyMappingCard(),
              const SizedBox(height: 14),
              _pointerCard(),
              const SizedBox(height: 14),
              _menuCard([
                _menuRow(Icons.high_quality_outlined, '画质', _showQuality),
                _menuRow(Icons.monitor_outlined, '屏幕', _showScreen),
              ]),
              const SizedBox(height: 14),
              _menuCard([
                _menuRow(Icons.usb, '外设', _showPeripherals),
                _menuRow(Icons.gpp_maybe_outlined, '安全', _showSecurity,
                    color: _kOrange),
                _menuRow(Icons.inventory_2_outlined, '工具', _showTools),
                _menuRow(Icons.grid_view_rounded, '更多', _showMore),
              ]),
              const SizedBox(height: 14),
              _menuCard([
                _menuRow(Icons.apple, '系统快捷操作', _showSystemShortcuts),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  Widget _securityWarning() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: _showSecurity,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: const [
              Icon(Icons.bolt, size: 22, color: _kOrange),
              SizedBox(width: 8),
              Text(
                '隐私安全状态需关注',
                style: TextStyle(
                  color: _kOrange,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _quickTiles() {
    final tiles = <Widget>[
      _tile(Icons.logout_rounded, '退出远控', _exitSession),
      _tile(Icons.screen_rotation_outlined, '旋转屏幕', _toggleOrientation),
      _tile(_muted ? Icons.volume_off_outlined : Icons.volume_up_outlined,
          '声音', _toggleMute),
      _tile(Icons.visibility_outlined, '仅观看', _toggleViewOnly,
          active: _viewOnly),
      _tile(Icons.picture_in_picture_alt_outlined, '小窗', _smallWindow),
    ];
    return SizedBox(
      height: 86,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: tiles.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (_, index) => tiles[index],
      ),
    );
  }

  Widget _tile(IconData icon, String label, VoidCallback onTap,
      {bool active = false}) {
    return Material(
      color: active ? _kBlue : _kTileBg,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: SizedBox(
          width: 88,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 26, color: Colors.white),
              const SizedBox(height: 9),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 14),
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
        ? '当前方案：${profile.name}'
        : '把常用按键固定在屏幕上发送给电脑';
    return _card(
      Column(
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => _toggleKeyMapping(!mappingOn),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    Container(
                      width: 30,
                      height: 30,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.white, width: 1.6),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'A',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '按键映射',
                            style: TextStyle(color: Colors.white, fontSize: 16),
                          ),
                          const SizedBox(height: 3),
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
                    Switch(
                      value: mappingOn,
                      onChanged: _toggleKeyMapping,
                      activeColor: _kBlue,
                      inactiveThumbColor: Colors.white,
                      inactiveTrackColor: const Color(0xFF5C5C60),
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
                      Icons.checklist_rounded, '选择方案', _chooseKeymap),
                ),
                Container(width: 1, height: 44, color: _kDivider),
                Expanded(
                  child: _keymapAction(
                      Icons.edit_outlined, '编辑方案', _editKeymap),
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
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: Colors.white),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(color: Colors.white, fontSize: 15),
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
    return _card(
      Column(
        children: [
          Container(
            height: 50,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: _kInnerBg,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Row(
              children: [
                _segment('屏幕触控', _touchMode, () => _toggleTouchMode(true)),
                _segment('鼠标指针', !_touchMode, () => _toggleTouchMode(false)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(11, 2, 2, 2),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    '显示鼠标按键',
                    style: TextStyle(color: Colors.white, fontSize: 16),
                  ),
                ),
                Switch(
                  value: _showRemoteCursor,
                  onChanged: _toggleShowRemoteCursor,
                  activeColor: _kBlue,
                  inactiveThumbColor: Colors.white,
                  inactiveTrackColor: const Color(0xFF5C5C60),
                ),
              ],
            ),
          ),
        ],
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
            color: selected ? _kBlue : Colors.transparent,
            borderRadius: BorderRadius.circular(7),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }

  Widget _card(Widget child) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(4),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: _kCardBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: child,
    );
  }

  Widget _menuCard(List<Widget> rows) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: _kCardBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0)
              const Divider(
                height: 1,
                thickness: 1,
                indent: 16,
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
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 17),
          child: Row(
            children: [
              Icon(icon, size: 22, color: color),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(color: color, fontSize: 16),
                ),
              ),
              const Icon(Icons.chevron_right, size: 20, color: _kMutedText),
            ],
          ),
        ),
      ),
    );
  }

  // ------------------------------- 子菜单 -------------------------------

  Future<void> _showQuality() => _openMenuSheet('画质', (refresh) async {
        final quality = await toolbarImageQuality(context, _id, _ffi);
        final codec = await toolbarCodec(context, _id, _ffi);
        return [
          const _SheetSection('图像质量'),
          for (final menu in quality) _radioTile(menu),
          const _SheetSection('编解码'),
          for (final menu in codec) _radioTile(menu),
        ];
      });

  Future<void> _showScreen() => _openMenuSheet('屏幕', (refresh) async {
        final pi = _ffi.ffiModel.pi;
        final style = await toolbarViewStyle(context, _id, _ffi);
        return [
          const _SheetSection('显示器'),
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
              title: Text('显示器 ${i + 1}'),
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
              title: const Text('全部显示器'),
            ),
          const _SheetSection('显示模式'),
          for (final menu in style) _radioTile(menu),
        ];
      });

  Future<void> _showPeripherals() =>
      _openMenuSheet('外设', (refresh) async {
        final ffiModel = _ffi.ffiModel;
        final perms = ffiModel.permissions;
        final isDefaultConn = _ffi.connType == ConnType.defaultConn;
        final rows = <Widget>[];
        if (isDefaultConn && perms['audio'] != false) {
          rows.add(SwitchListTile(
            title: const Text('声音输出'),
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
            title: const Text('剪贴板同步'),
            value: !disabled,
            onChanged: (value) {
              bind.sessionToggleOption(
                  sessionId: _sessionId, value: 'disable-clipboard');
              scheduleMicrotask(refresh);
            },
          ));
        }
        if (rows.isEmpty) {
          rows.add(const ListTile(title: Text('对端未开放外设权限')));
        }
        return rows;
      });

  Future<void> _showSecurity() =>
      _openMenuSheet('安全', (refresh) async {
        final privacy =
            toolbarPrivacyMode(PrivacyModeState.find(_id), context, _id, _ffi);
        if (privacy.isEmpty) {
          return [const ListTile(title: Text('对端不支持隐私模式'))];
        }
        return [
          for (final menu in privacy) _toggleTile(menu, refresh),
        ];
      });

  Future<void> _showTools() => _openMenuSheet('工具', (refresh) async {
        final menus = toolbarControls(context, _id, _ffi);
        return [
          if (widget.onChat != null) ...[
            _actionTile(Icons.chat_bubble_outline, '发送消息', () {
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

  Future<void> _showMore() => _openMenuSheet('更多', (refresh) async {
        final virtualMouse = _ffi.ffiModel.virtualMouseMode;
        final keyboard = toolbarKeyboardToggles(_ffi);
        final cursor = await toolbarCursor(context, _id, _ffi);
        final display = await toolbarDisplayToggle(context, _id, _ffi);
        return [
          const _SheetSection('鼠标指针模式'),
          SwitchListTile(
            title: const Text('虚拟鼠标控件'),
            subtitle: const Text('显示滚轮和左右键'),
            value: virtualMouse.showVirtualMouse,
            onChanged: (value) {
              virtualMouse.toggleVirtualMouse();
              scheduleMicrotask(refresh);
            },
          ),
          if (widget.onShowGestureHelp != null) ...[
            const _SheetSection('手势'),
            _actionTile(Icons.gesture, '手势说明', () {
              Navigator.of(context).pop();
              _closePanelRoutes();
              widget.onShowGestureHelp!.call();
            }),
          ],
          const _SheetSection('键盘与鼠标'),
          for (final menu in keyboard) _toggleTile(menu, refresh),
          for (final menu in cursor) _toggleTile(menu, refresh),
          const _SheetSection('显示与剪贴板'),
          for (final menu in display) _toggleTile(menu, refresh),
        ];
      });

  Future<void> _showSystemShortcuts() =>
      _openMenuSheet('系统快捷操作', (refresh) async {
        return [
          _actionTile(Icons.lock_outline, '锁定远程屏幕', _lockDevice),
          _actionTile(Icons.restart_alt_rounded, '重启远程设备', () {
            Navigator.of(context).pop();
            _restartDevice();
          }),
          _actionTile(Icons.power_settings_new_rounded, '关闭远程设备', () {
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
      backgroundColor: Colors.white,
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
    return SafeArea(
      top: false,
      child: FractionallySizedBox(
        heightFactor: 0.72,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
              child: Row(
                children: [
                  Text(
                    widget.title,
                    style: const TextStyle(
                      color: Color(0xFF161A22),
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, color: Color(0xFF7B8291)),
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
