import 'dart:async';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/common/shared_state.dart';
import 'package:flutter_hbb/common/widgets/toolbar.dart' show togglePrivacyModeTime;
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/desktop/pages/remote_page.dart';
import 'package:flutter_hbb/desktop/widgets/tabbar_widget.dart';
import 'package:flutter_hbb/main.dart';
import 'package:flutter_hbb/models/model.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/models/state_model.dart';
import 'package:flutter_hbb/utils/multi_window_manager.dart';
import 'package:get/get.dart';

import '../design/uu_tokens.dart';
import '../uu_defaults.dart';
import '../widgets/uu_exit_confirm.dart';
import '../widgets/uu_menu.dart';
import '../widgets/uu_platform_icon.dart';
import '../widgets/uu_quality_pill.dart';
import '../widgets/uu_window_controls.dart';

/// UU 远程风格的远控窗口顶栏：左侧会话标签，右侧“控制中”菜单与窗口按钮。
class UuRemoteTabBar extends StatefulWidget {
  const UuRemoteTabBar({
    super.key,
    required this.controller,
  });

  final DesktopTabController controller;

  @override
  State<UuRemoteTabBar> createState() => _UuRemoteTabBarState();
}

class _UuRemoteTabBarState extends State<UuRemoteTabBar> {
  DesktopTabController get controller => widget.controller;
  String? _hoveredTab;

  void _addSession() {
    rustDeskWinManager.call(WindowType.Main, kWindowMainWindowOnTop, "");
  }

  RemotePage? _pageOf(TabInfo tab) =>
      tab.page is RemotePage ? tab.page as RemotePage : null;

  String _tabLabel(TabInfo tab) {
    final alias = bind.mainGetPeerOptionSync(id: tab.key, key: 'alias');
    return getDesktopTabLabel(tab.key, alias);
  }

  @override
  Widget build(BuildContext context) {
    UuColors.apply(context);
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onPanStart: (_) =>
          WindowController.fromWindowId(kWindowId!).startDragging(),
      onDoubleTap: isMacOS || kUseCompatibleUiMode
          ? null
          : () => toggleMaximize(false)
              .then((value) => stateGlobal.setMaximized(value)),
      child: Container(
        color: UuColors.sessionBar,
        child: Obx(() {
          final state = controller.state.value;
          if (state.tabs.isEmpty) {
            return const SizedBox.shrink();
          }
          final selected = state.selected < state.tabs.length
              ? state.tabs[state.selected]
              : state.tabs.first;
          final selectedPage = _pageOf(selected);
          return Row(
            children: [
              if (isMacOS) const SizedBox(width: 78) else const SizedBox(width: 4),
              Expanded(
                child: Row(
                  children: [
                    for (final tab in state.tabs)
                      Flexible(child: _tabChip(tab, tab.key == selected.key)),
                    _iconButton(
                      Icons.add,
                      translate('New Connection'),
                      _addSession,
                    ),
                  ],
                ),
              ),
              if (selectedPage != null) ...[
                UuQualityPill(ffi: selectedPage.ffi),
                UuControlMenu(
                  key: ValueKey(selectedPage.ffi.sessionId),
                  page: selectedPage,
                  onExit: () =>
                      WindowController.fromWindowId(kWindowId!).close(),
                ),
              ],
              if (!isMacOS && !kUseCompatibleUiMode)
                UuWindowControls(
                  isMainWindow: false,
                  iconColor: Colors.white70,
                ),
            ],
          );
        }),
      ),
    );
  }

  Widget _tabChip(TabInfo tab, bool selected) {
    final page = _pageOf(tab);
    final label = _tabLabel(tab);
    final hovered = _hoveredTab == tab.key;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hoveredTab = tab.key),
        onExit: (_) {
          if (_hoveredTab == tab.key) {
            setState(() => _hoveredTab = null);
          }
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => controller.jumpToByKey(tab.key),
          child: Container(
            height: 32,
            padding: const EdgeInsets.only(left: 10, right: 6),
            decoration: BoxDecoration(
              color: selected
                  ? UuColors.sessionSheet
                  : hovered
                      ? UuColors.sessionHoverTint
                      : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  UuPeerPlatformIcon.iconFor(
                      page?.ffi.ffiModel.pi.platform ?? ''),
                  size: 14,
                  color:
                      selected ? UuColors.sessionText : UuColors.sessionMuted,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: selected
                          ? UuColors.sessionText
                          : UuColors.sessionMuted,
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                if (tab.closable)
                  Material(
                    type: MaterialType.transparency,
                    child: InkWell(
                      onTap: () async {
                        if (!await uuConfirmDisconnect(context,
                            peerName: label)) {
                          return;
                        }
                        if (tab.onTabCloseButton != null) {
                          tab.onTabCloseButton!();
                        } else {
                          controller.closeBy(tab.key);
                        }
                      },
                      hoverColor: UuColors.sessionHoverTint,
                      borderRadius: BorderRadius.circular(4),
                      child: Padding(
                        padding: const EdgeInsets.all(3),
                        child: Icon(
                          Icons.close,
                          size: 12,
                          color: selected ? UuColors.sessionMuted : const Color(0xFF6E6E76),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _iconButton(IconData icon, String tooltip, VoidCallback onTap) {
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 600),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          hoverColor: UuColors.sessionHoverTint,
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            width: 30,
            height: 30,
            child: Icon(icon, size: 16, color: UuColors.sessionMuted),
          ),
        ),
      ),
    );
  }
}

/// The "控制中" pill and its menu; also reused by the fullscreen top bar.
class UuControlMenu extends StatefulWidget {
  const UuControlMenu({
    super.key,
    required this.page,
    required this.onExit,
  });

  final RemotePage page;
  final VoidCallback onExit;

  @override
  State<UuControlMenu> createState() => _UuControlMenuState();
}

class _UuControlMenuState extends State<UuControlMenu> {
  String _quality = '';
  String _viewStyle = '';

  SessionID get _sessionId => widget.page.ffi.sessionId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final quality = await bind.sessionGetImageQuality(sessionId: _sessionId);
    final viewStyle = await bind.sessionGetViewStyle(sessionId: _sessionId);
    if (!mounted) return;
    setState(() {
      _quality = quality ?? '';
      _viewStyle = viewStyle ?? '';
    });
  }

  Future<void> _setQuality(String value) async {
    await bind.sessionSetImageQuality(sessionId: _sessionId, value: value);
    if (mounted) setState(() => _quality = value);
  }

  Future<void> _setViewStyle(String value) async {
    await bind.sessionSetViewStyle(sessionId: _sessionId, value: value);
    await widget.page.ffi.canvasModel.updateViewStyle();
    if (mounted) setState(() => _viewStyle = value);
  }

  void _switchNextDisplay() {
    final ffi = widget.page.ffi;
    final pi = ffi.ffiModel.pi;
    if (pi.displays.length < 2 || pi.currentDisplay < 0) {
      return;
    }
    final next = (pi.currentDisplay + 1) % pi.displays.length;
    openMonitorInTheSameTab(next, ffi, pi);
  }

  void _toggleOption(String option) {
    bind.sessionToggleOption(sessionId: _sessionId, value: option);
    if (mounted) setState(() {});
  }

  List<dynamic>? get _privacyImpls => widget.page.ffi.ffiModel.pi
      .platformAdditions[kPlatformAdditionsSupportedPrivacyModeImpl] as List?;

  bool get _privacyToggleAvailable {
    final ffi = widget.page.ffi;
    final ffiModel = ffi.ffiModel;
    final state = PrivacyModeState.find(widget.page.id);
    if (ffi.connType != ConnType.defaultConn) return false;
    if (ffiModel.permissions['privacy_mode'] == false && state.isEmpty) {
      return false;
    }
    // Multiple implementations need a submenu; keep them in the stock toolbar.
    return !ffiModel.viewOnly && (_privacyImpls?.length ?? 1) <= 1;
  }

  void _togglePrivacy() {
    final state = PrivacyModeState.find(widget.page.id);
    final impls = _privacyImpls;
    if (impls == null) {
      bind.sessionToggleOption(sessionId: _sessionId, value: 'privacy-mode');
    } else if (impls.length == 1) {
      final implKey = (impls[0] as List)[0] as String;
      bind.sessionTogglePrivacyMode(
          sessionId: _sessionId, implKey: implKey, on: state.isEmpty);
    }
    togglePrivacyModeTime = DateTime.now();
    if (mounted) setState(() {});
  }

  void _openFileTransfer() {
    final ffi = widget.page.ffi;
    unawaited(connect(
      context,
      widget.page.id,
      loginMethod: bind.sessionGetCommonSync(
              sessionId: ffi.sessionId, key: 'login_method', param: '') ??
          '',
      isFileTransfer: true,
      connToken: bind.sessionGetConnToken(sessionId: ffi.sessionId),
    ));
  }

  void _toggleFullscreen() {
    stateGlobal.setFullscreen(!stateGlobal.fullscreen.isTrue);
    if (mounted) setState(() {});
  }

  Future<void> _confirmExit() async {
    final alias =
        bind.mainGetPeerOptionSync(id: widget.page.id, key: 'alias');
    final ok = await uuConfirmDisconnect(
      context,
      peerName: alias.isNotEmpty ? alias : widget.page.id,
      tabCount: widget.page.tabController?.length ?? 1,
    );
    if (!ok || !mounted) {
      return;
    }
    uuWindowExitConfirmed = true;
    widget.onExit();
  }

  String _displayText(PeerInfo pi) {
    if (pi.currentDisplay == kAllDisplayValue) {
      return translate('All screens');
    }
    final index = pi.currentDisplay >= 0 ? pi.currentDisplay : 0;
    return translate('Display {${index + 1}}');
  }

  String _displayDetail(PeerInfo pi) {
    if (pi.currentDisplay == kAllDisplayValue) {
      return translate('All screens · {${pi.displays.length}} displays');
    }
    final index = pi.currentDisplay >= 0 ? pi.currentDisplay : 0;
    final display =
        index < pi.displays.length ? pi.displays[index] : null;
    final resolution = display == null || display.width <= 0
        ? ''
        : ' · ${display.width}×${display.height}';
    return '${translate('Monitor {${index + 1}}')}$resolution';
  }

  @override
  Widget build(BuildContext context) {
    final pi = widget.page.ffi.ffiModel.pi;
    final perms = widget.page.ffi.ffiModel.permissions;
    return UuMenuButton<String>(
      width: 250,
      style: UuMenuStyle.session,
      onSelected: (value) {
        switch (value) {
          case 'next-display':
            _switchNextDisplay();
            break;
          case 'quality-low':
            _setQuality(kRemoteImageQualityLow);
            break;
          case 'quality-balanced':
            _setQuality(kRemoteImageQualityBalanced);
            break;
          case 'quality-best':
            _setQuality(kRemoteImageQualityBest);
            break;
          case 'view-adaptive':
            _setViewStyle(kRemoteViewStyleAdaptive);
            break;
          case 'view-original':
            _setViewStyle(kRemoteViewStyleOriginal);
            break;
          case 'toggle-audio':
            _toggleOption('disable-audio');
            break;
          case 'toggle-clipboard':
            _toggleOption('disable-clipboard');
            break;
          case 'toggle-privacy':
            _togglePrivacy();
            break;
          case 'file-transfer':
            _openFileTransfer();
            break;
          case 'chat':
            widget.page.ffi.chatModel.toggleChatOverlay();
            break;
          case 'fullscreen':
            _toggleFullscreen();
            break;
          case 'toggle-toolbar':
            setUuRemoteToolbarVisible(!uuRemoteToolbarVisible.value);
            break;
          case 'exit':
            unawaited(_confirmExit());
            break;
        }
      },
      entriesBuilder: (context) {
        final audioOff = bind.sessionGetToggleOptionSync(
            sessionId: _sessionId, arg: 'disable-audio');
        final clipboardOff = bind.sessionGetToggleOptionSync(
            sessionId: _sessionId, arg: 'disable-clipboard');
        final privacyOn =
            PrivacyModeState.find(widget.page.id).isNotEmpty;
        final fullscreen = stateGlobal.fullscreen.isTrue;
        final toggles = <UuMenuEntry<String>>[
          if (perms['audio'] != false)
            _item(
              'toggle-audio',
              audioOff ? translate('Unmute') : translate('Mute'),
              audioOff ? Icons.volume_off_outlined : Icons.volume_up_outlined,
            ),
          if (perms['clipboard'] != false &&
              widget.page.ffi.ffiModel.keyboard &&
              !widget.page.ffi.ffiModel.viewOnly)
            _item(
              'toggle-clipboard',
              clipboardOff ? translate('Enable clipboard sync') : translate('Disable clipboard sync'),
              clipboardOff
                  ? Icons.content_paste_go
                  : Icons.content_paste_off_outlined,
            ),
          if (_privacyToggleAvailable)
            _item('toggle-privacy', privacyOn ? translate('Turn off privacy screen') : translate('Turn on privacy screen'),
                Icons.shield_outlined,
                selected: privacyOn),
        ];
        return [
          _header(pi),
          if (pi.displays.length > 1)
            _item('next-display', translate('Switch to next display'), Icons.switch_video),
          _divider(),
          _item('quality-low', translate('Smooth'), Icons.speed,
              selected: _quality == kRemoteImageQualityLow),
          _item('quality-balanced', translate('Balanced'), Icons.balance,
              selected: _quality == kRemoteImageQualityBalanced),
          _item('quality-best', translate('HD'), Icons.hd_outlined,
              selected: _quality == kRemoteImageQualityBest),
          _divider(),
          _item('view-adaptive', translate('Fit to window'), Icons.fit_screen,
              selected: _viewStyle == kRemoteViewStyleAdaptive),
          _item('view-original', translate('Original size'), Icons.crop_original,
              selected: _viewStyle == kRemoteViewStyleOriginal),
          if (toggles.isNotEmpty) ...[
            _divider(),
            ...toggles,
          ],
          _divider(),
          if (widget.page.ffi.connType == ConnType.defaultConn)
            _item('file-transfer', translate('File transfer'), Icons.swap_horiz),
          _item('chat', translate('Chat window'), Icons.chat_bubble_outline),
          _divider(),
          _item('fullscreen', fullscreen ? translate('Exit Fullscreen') : translate('Fullscreen'),
              fullscreen ? Icons.fullscreen_exit : Icons.fullscreen),
          _item(
            'toggle-toolbar',
            uuRemoteToolbarVisible.value ? translate('Hide remote toolbar') : translate('Show remote toolbar'),
            Icons.tune,
          ),
          _divider(),
          _item('exit', translate('Exit session'), Icons.power_settings_new, danger: true),
        ];
      },
      child: Container(
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: UuColors.sessionHover,
          borderRadius: BorderRadius.circular(15),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: const BoxDecoration(
                color: UuColors.success,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              translate('Controlling · {${_displayText(pi)}}'),
              style: const TextStyle(color: UuColors.sessionText, fontSize: 12),
            ),
            const Icon(Icons.keyboard_arrow_down,
                size: 15, color: UuColors.sessionMuted),
          ],
        ),
      ),
    );
  }

  UuMenuCaption<String> _header(PeerInfo pi) {
    return UuMenuCaption<String>(
      icon: Icons.monitor,
      label: _displayDetail(pi),
    );
  }

  UuMenuDivider<String> _divider() => const UuMenuDivider<String>();

  UuMenuItem<String> _item(
    String value,
    String label,
    IconData icon, {
    bool selected = false,
    bool danger = false,
  }) {
    return UuMenuItem<String>(
      value: value,
      label: label,
      icon: icon,
      selected: selected,
      danger: danger,
      height: 38,
    );
  }
}
