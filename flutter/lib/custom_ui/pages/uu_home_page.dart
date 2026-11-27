import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/common/widgets/peer_card.dart';
import 'package:flutter_hbb/desktop/pages/desktop_home_page.dart'
    show setPasswordDialog;
import 'package:flutter_hbb/desktop/widgets/tabbar_widget.dart';
import 'package:flutter_hbb/models/ab_model.dart';
import 'package:flutter_hbb/models/peer_model.dart';
import 'package:flutter_hbb/models/peer_tab_model.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/models/server_model.dart';
import 'package:flutter_hbb/models/state_model.dart';
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:window_manager/window_manager.dart';

import '../design/uu_tokens.dart';
import '../theme.dart';
import '../uu_auth.dart';
import '../uu_login_dialog.dart';
import '../uu_peer.dart';
import '../uu_settings_dialog.dart';
import '../uu_wallpaper.dart';
import '../widgets/uu_account.dart';
import '../widgets/uu_buttons.dart';
import '../widgets/uu_components.dart';
import '../widgets/uu_feedback.dart';
import '../widgets/uu_menu.dart';
import '../widgets/uu_platform_icon.dart';
import '../widgets/uu_rename_dialog.dart';
import '../widgets/uu_window_controls.dart';

class UuHomePage extends StatefulWidget {
  const UuHomePage({super.key});

  @override
  State<UuHomePage> createState() => _UuHomePageState();
}

enum _HomePage { home, allDevices, assist, favorites }

class _UuHomePageState extends State<UuHomePage> {
  static const _demoId = '000000000';

  String? _selectedId;
  _HomePage _page = _HomePage.home;
  String _heroImage = '';
  String? _hoveredRow;
  bool _demoVisible = false;
  Timer? _onlineTimer;
  Timer? _abRefreshTimer;
  final Map<Peers, VoidCallback> _peersListeners = {};
  final _assistIdController = TextEditingController();
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
  final _assistGearKey = GlobalKey();
  bool _allowAssist = true;
  bool _showAssistPassword = false;
  String _autoRefresh = 'after-session';
  Timer? _assistRefreshTimer;

  @override
  void initState() {
    super.initState();
    _heroImage = bind.mainGetLocalOption(key: 'custom-hero-image');
    bind.mainLoadRecentPeers();
    unawaited(uuSyncDeviceSecret());
    _searchController.addListener(_onSearchChanged);
    _initOnlineTracking();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await windowManager.setTitleBarStyle(TitleBarStyle.hidden);
        await windowManager.setMinimumSize(const Size(900, 600));
        await windowManager.setSize(const Size(1080, 720));
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    _assistRefreshTimer?.cancel();
    _onlineTimer?.cancel();
    _abRefreshTimer?.cancel();
    _peersListeners.forEach((peers, listener) {
      peers.removeListener(listener);
    });
    _peersListeners.clear();
    _assistIdController.dispose();
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    if (mounted) setState(() {});
  }

  void _initOnlineTracking() {
    for (final peers in [
      gFFI.abModel.peersModel,
      gFFI.favoritePeersModel,
      gFFI.recentPeersModel,
    ]) {
      void listener() {
        if (mounted) {
          setState(() {});
        }
      }

      _peersListeners[peers] = listener;
      peers.addListener(listener);
    }
    _onlineTimer = Timer.periodic(
      const Duration(seconds: 8),
      (_) => _queryOnlineStatuses(),
    );
    _abRefreshTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (gFFI.userModel.isLogin) {
        unawaited(gFFI.abModel
            .pullAb(force: ForcePullAb.current, quiet: true));
      }
    });
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _queryOnlineStatuses());
  }

  void _queryOnlineStatuses() {
    final ids = _allPeers()
        .map((peer) => peer.id)
        .where((id) => id.isNotEmpty && id != _demoId)
        .toSet()
        .toList();
    if (ids.isEmpty) {
      return;
    }
    unawaited(bind.queryOnlines(ids: ids));
  }

  String get _localId =>
      gFFI.serverModel.serverId.text.replaceAll(' ', '').trim();

  bool _isIosPeer(Peer peer) {
    final p = peer.platform.toLowerCase();
    return p.contains('ios') || p.contains('iphone') || p.contains('ipad');
  }

  List<Peer> _allPeers() {
    final seen = <String>{};
    final peers = <Peer>[];
    final localId = _localId;
    for (final peer in [
      ...gFFI.abModel.currentAbPeers,
      ...gFFI.favoritePeersModel.peers,
      ...gFFI.recentPeersModel.peers,
    ]) {
      if (peer.id.isEmpty) {
        continue;
      }
      if (localId.isNotEmpty && peer.id == localId) {
        continue;
      }
      if (_isIosPeer(peer)) {
        continue;
      }
      if (seen.add(peer.id)) {
        peers.add(peer);
      }
    }
    if (_demoVisible && seen.add(_demoId)) {
      peers.add(_demoPeer());
    }
    return peers;
  }

  Peer _demoPeer() {
    final peer = Peer.fromJson({
      'id': _demoId,
      'alias': translate('Demo devices'),
      'hostname': 'Demo PC',
      'platform': 'Windows',
      'username': 'demo',
    });
    peer.online = true;
    peer.sameServer = true;
    return peer;
  }

  bool _matchesQuery(Peer peer) {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) {
      return true;
    }
    return uuPeerName(peer).toLowerCase().contains(query) ||
        peer.id.toLowerCase().contains(query);
  }

  List<Peer> _recentPeers({int limit = 5}) {
    final localId = _localId;
    final result = <Peer>[];
    for (final peer in gFFI.recentPeersModel.peers) {
      if (peer.id.isEmpty) continue;
      if (localId.isNotEmpty && peer.id == localId) continue;
      if (_isIosPeer(peer)) continue;
      result.add(peer);
      if (result.length >= limit) break;
    }
    return result;
  }

  Peer? _selectedPeer(List<Peer> peers) {
    if (peers.isEmpty) {
      return null;
    }
    if (_selectedId != null) {
      for (final peer in peers) {
        if (peer.id == _selectedId) {
          return peer;
        }
      }
    }
    return peers.first;
  }

  bool _inAddressBook(Peer peer) =>
      gFFI.abModel.currentAbPeers.any((p) => p.id == peer.id);

  void _connectPeer(
    Peer peer, {
    bool isFileTransfer = false,
    bool isTerminal = false,
    bool isTcpTunneling = false,
    bool isViewCamera = false,
  }) {
    if (peer.id == _demoId) {
      uuToast(translate('Demo devices are for preview only. Please add a real device.'));
      return;
    }
    final secret = _inAddressBook(peer) ? uuAccountDevicePassword() : '';
    if (secret.isNotEmpty) {
      unawaited(connect(
        context,
        peer.id,
        password: secret,
        isFileTransfer: isFileTransfer,
        isTerminal: isTerminal,
        isTcpTunneling: isTcpTunneling,
        isViewCamera: isViewCamera,
      ));
      return;
    }
    connectInPeerTab(
      context,
      peer,
      _inAddressBook(peer) ? PeerTabIndex.ab : PeerTabIndex.recent,
      isFileTransfer: isFileTransfer,
      isTerminal: isTerminal,
      isTcpTunneling: isTcpTunneling,
      isViewCamera: isViewCamera,
    );
  }

  Future<void> _showQuickConnect({
    bool isFileTransfer = false,
    bool isTerminal = false,
    bool isTcpTunneling = false,
    bool isViewCamera = false,
  }) async {
    final idController = TextEditingController();
    final passwordController = TextEditingController();
    final ok = await showUuDialog<bool>(
      context,
      title: translate('Remote connection'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          UuTextField(
            controller: idController,
            autofocus: true,
            hint: translate('Device ID'),
          ),
          const SizedBox(height: 10),
          UuTextField(
            controller: passwordController,
            obscure: true,
            hint: translate('Password (optional)'),
            onSubmitted: (_) => Navigator.of(context).pop(true),
          ),
        ],
      ),
      actions: [
        uuDialogTextButton(translate('Cancel'), () => Navigator.of(context).pop(false)),
        uuDialogFilledButton(translate('Connect'), () => Navigator.of(context).pop(true)),
      ],
    );
    final id = idController.text.replaceAll(' ', '').trim();
    final password = passwordController.text;
    idController.dispose();
    passwordController.dispose();
    if (ok != true || id.isEmpty) {
      return;
    }
    if (gFFI.abModel.currentName.value.isNotEmpty) {
      try {
        await gFFI.abModel.addIdToCurrent(id, '', password, const [], '');
      } catch (_) {}
    }
    if (!mounted) {
      return;
    }
    await connect(
      context,
      id,
      password: password.isEmpty ? null : password,
      isFileTransfer: isFileTransfer,
      isTerminal: isTerminal,
      isTcpTunneling: isTcpTunneling,
      isViewCamera: isViewCamera,
    );
  }

  Future<void> _showLocalInfo() async {
    await showUuDialog<void>(
      context,
      title: bind.mainGetAppNameSync(),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            translate('ID'),
            style: TextStyle(
              color: UuColors.textSecondary,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 4),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: gFFI.serverModel.serverId,
            builder: (context, value, child) {
              return SelectableText(
                value.text,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          Text(
            translate('One-time Password'),
            style: TextStyle(
              color: UuColors.textSecondary,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 4),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: gFFI.serverModel.serverPasswd,
            builder: (context, value, child) {
              return SelectableText(
                value.text,
                style: const TextStyle(fontSize: 14),
              );
            },
          ),
        ],
      ),
      actions: [
        uuDialogTextButton(translate('Copy ID'), _copyId),
        uuDialogFilledButton(translate('Close'), () => Navigator.of(context).pop()),
      ],
    );
  }

  bool get _daemonProblem =>
      isMacOS &&
      !bind.isOutgoingOnly() &&
      bind.mainIsInstalled() &&
      (!bind.mainIsInstalledDaemon(prompt: false) ||
          bind.mainGetOptionSync(key: 'stop-service') == 'Y');

  Future<void> _showNotifications() async {
    final rows = <Widget>[];
    if (_needsPermissions) {
      rows.add(_notificationRow(
        icon: Icons.shield_outlined,
        title: translate('System permissions not fully granted'),
        message: translate('Screen Recording, Accessibility, or Input Monitoring is off. Remote control may not work.'),
        actionLabel: translate('Configure'),
        onTap: () {
          Navigator.of(context).pop();
          _requestPermissions();
        },
      ));
    }
    if (_daemonProblem) {
      final needInstall = !bind.mainIsInstalledDaemon(prompt: false);
      rows.add(_notificationRow(
        icon: Icons.dns_outlined,
        title: needInstall ? translate('Service not installed') : translate('Service stopped'),
        message: needInstall ? translate('Install it to let this Mac receive remote connections.') : translate('Start the service to receive remote connections.'),
        actionLabel: needInstall ? translate('Install') : translate('Start'),
        onTap: () async {
          Navigator.of(context).pop();
          if (needInstall) {
            bind.mainIsInstalledDaemon(prompt: true);
          } else {
            await start_service(true);
          }
          if (mounted) setState(() {});
        },
      ));
    }
    if (!gFFI.userModel.isLogin) {
      rows.add(_notificationRow(
        icon: Icons.person_outline,
        title: translate('Not signed in'),
        message: translate('Sign in to sync your account devices automatically; no manual ID entry needed.'),
        actionLabel: translate('Login'),
        onTap: () {
          Navigator.of(context).pop();
          unawaited(uuAccountDialog(context));
        },
      ));
    }
    await showUuDialog<void>(
      context,
      title: translate('Notifications'),
      content: rows.isEmpty
          ? UuEmptyState(
              icon: Icons.notifications_none_rounded,
              title: translate('No notifications'),
              message: translate('System permissions, the service, and your account are all in order.'),
            )
          : Column(mainAxisSize: MainAxisSize.min, children: rows),
      actions: [
        uuDialogFilledButton(translate('Close'), () => Navigator.of(context).pop()),
      ],
    );
  }

  Widget _notificationRow({
    required IconData icon,
    required String title,
    required String message,
    required String actionLabel,
    required void Function() onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(12, 12, 6, 12),
      decoration: BoxDecoration(
        color: UuColors.background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: UuColors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: UuColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  message,
                  style: TextStyle(
                    color: UuColors.textSecondary,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: onTap,
            style: TextButton.styleFrom(
              foregroundColor: UuColors.primary,
              minimumSize: const Size(48, 32),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(actionLabel, style: const TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }

  bool get _hasHeroImage =>
      _heroImage.isNotEmpty && File(_heroImage).existsSync();

  BoxDecoration _heroDecoration() {
    final ImageProvider<Object> image = _hasHeroImage
        ? FileImage(File(_heroImage)) as ImageProvider<Object>
        : const AssetImage('assets/hero.jpg') as ImageProvider<Object>;
    return BoxDecoration(
      borderRadius: BorderRadius.circular(16),
      image: DecorationImage(
        image: image,
        fit: BoxFit.cover,
      ),
    );
  }

  Future<void> _pickHeroImage() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image);
    final path = result?.files.single.path;
    if (path == null) {
      return;
    }
    await bind.mainSetOption(key: 'custom-hero-image', value: path);
    if (mounted) {
      setState(() => _heroImage = path);
    }
  }

  Future<void> _resetHeroImage() async {
    await bind.mainSetOption(key: 'custom-hero-image', value: '');
    if (mounted) {
      setState(() => _heroImage = '');
    }
  }

  void _copyId() {
    Clipboard.setData(ClipboardData(text: gFFI.serverModel.serverId.text));
    uuToast(translate('Copied'));
  }

  bool get _needsPermissions =>
      isMacOS &&
      (!bind.mainIsCanScreenRecording(prompt: false) ||
          !bind.mainIsProcessTrusted(prompt: false) ||
          !bind.mainIsCanInputMonitoring(prompt: false));

  void _requestPermissions() {
    bind.mainIsCanScreenRecording(prompt: true);
    bind.mainIsProcessTrusted(prompt: true);
    bind.mainIsCanInputMonitoring(prompt: true);
  }

  Future<void> _logout() async {
    if (!await uuConfirmLogout(context)) {
      return;
    }
    await gFFI.userModel.logOut();
  }

  @override
  Widget build(BuildContext context) {
    UuColors.apply(context);
    return Focus(
      autofocus: true,
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyK, control: true):
              _focusSearch,
          const SingleActivator(LogicalKeyboardKey.keyK, meta: true):
              _focusSearch,
        },
        child: LayoutBuilder(
          builder: (context, constraints) {
            final sidebarWidth =
                (constraints.maxWidth * 0.243).clamp(240.0, 400.0).toDouble();
            return Container(
              color: UuColors.background,
              child: Row(
                children: [
                  SizedBox(
                      width: sidebarWidth, child: _buildSidebar(context)),
                  VerticalDivider(width: 1, color: UuTheme.divider),
                  Expanded(child: _buildMain(context)),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  void _focusSearch() {
    _searchFocus.requestFocus();
  }

  Widget _buildSidebar(BuildContext context) {
    return Container(
      color: UuColors.surface,
      child: AnimatedBuilder(
        animation: Listenable.merge([
          gFFI.recentPeersModel,
          gFFI.favoritePeersModel,
        ]),
        builder: (context, child) {
          return Obx(() {
            final all = _allPeers();
            final visible = all.where(_matchesQuery).toList();
            final selected = _selectedPeer(all);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanStart: (_) => windowManager.startDragging(),
                  child: const SizedBox(
                      height: 52, width: double.infinity),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                  child: UuSearchField(
                    controller: _searchController,
                    focusNode: _searchFocus,
                    hint: isMacOS ? translate('Search devices (⌘K)') : translate('Search devices (Ctrl+K)'),
                  ),
                ),
                _sectionHeader(translate('My devices'), Icons.devices_other,
                    count: all.isEmpty ? null : all.length),
                if (all.isEmpty)
                  _sideHint(translate('No devices yet. Click + in the top-right to add one.'))
                else if (visible.isEmpty)
                  _sideHint(translate('No matching devices'))
                else
                  for (final peer in visible) _deviceRow(peer, selected),
                _allDevicesRow(),
                const SizedBox(height: 12),
                _sectionHeader(translate('Remote assistance'), Icons.support_agent),
                _assistRow(
                  Icons.add_to_queue,
                  translate('Start assisting'),
                  () => setState(() => _page = _HomePage.assist),
                  selected: _page == _HomePage.assist,
                ),
                _assistRow(
                  Icons.star,
                  translate('Favorite devices'),
                  () => setState(() => _page = _HomePage.favorites),
                  selected: _page == _HomePage.favorites,
                ),
                const Spacer(),
              ],
            );
          });
        },
      ),
    );
  }

  Widget _sectionHeader(String title, IconData icon, {int? count}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 14, 6),
      child: Row(
        children: [
          Icon(icon, size: 20, color: UuTheme.textSecondary),
          const SizedBox(width: 6),
          Text(
            title,
            style: TextStyle(
              color: UuTheme.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (count != null) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: UuColors.hover,
                borderRadius: BorderRadius.circular(UuRadius.pill),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  color: UuColors.textSecondary,
                  fontSize: 12,
                ),
              ),
            ),
          ],
          const Spacer(),
          Icon(
            Icons.keyboard_arrow_up,
            size: 18,
            color: UuTheme.textSecondary,
          ),
        ],
      ),
    );
  }

  Widget _sideHint(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 2, 16, 8),
      child: Text(
        text,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: UuTheme.textSecondary, fontSize: 12),
      ),
    );
  }

  Widget _deviceRow(Peer peer, Peer? selected) {
    final isSelected =
        _page == _HomePage.home && selected?.id == peer.id;
    final isHovered = _hoveredRow == peer.id;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hoveredRow = peer.id),
      onExit: (_) {
        if (_hoveredRow == peer.id) {
          setState(() => _hoveredRow = null);
        }
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() {
          _page = _HomePage.home;
          _selectedId = peer.id;
        }),
        child: Container(
          margin: const EdgeInsets.only(left: 4, right: 4, bottom: 2),
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(
            color: isSelected
                ? UuColors.primarySoft
                : isHovered
                    ? UuColors.hoverTint
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: peer.online ? UuTheme.online : UuTheme.offline,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: peer.online
                      ? UuColors.primarySoft
                      : UuColors.hover,
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Icon(
                  UuPeerPlatformIcon.iconFor(peer.platform),
                  size: 15,
                  color: peer.online
                      ? UuColors.primary
                      : UuColors.textTertiary,
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  uuPeerName(peer),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isSelected ? UuTheme.accent : UuTheme.textPrimary,
                    fontSize: 13,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ),
              if (isHovered && !isSelected)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _connectPeer(peer),
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: UuColors.primarySoft,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Icon(
                      Icons.play_arrow_rounded,
                      size: 16,
                      color: UuColors.primary,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _allDevicesRow() {
    const key = '__all_devices__';
    final isHovered = _hoveredRow == key;
    final isSelected = _page == _HomePage.allDevices;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hoveredRow = key),
      onExit: (_) {
        if (_hoveredRow == key) {
          setState(() => _hoveredRow = null);
        }
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() {
          _page = _HomePage.allDevices;
        }),
        child: Container(
          margin: const EdgeInsets.only(left: 4, right: 4, bottom: 2),
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(
            color: isSelected
                ? UuColors.primarySoft
                : isHovered
                    ? UuColors.hoverTint
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              const SizedBox(width: 16),
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: UuColors.primarySoft,
                  borderRadius: BorderRadius.circular(7),
                ),
                child: const Icon(
                  Icons.grid_view,
                  size: 15,
                  color: UuTheme.accent,
                ),
              ),
              const SizedBox(width: 9),
              Text(
                translate('All devices'),
                style: TextStyle(
                  color: isSelected ? UuTheme.accent : UuTheme.textPrimary,
                  fontSize: 13,
                  fontWeight:
                      isSelected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _assistRow(
    IconData icon,
    String label,
    VoidCallback onTap, {
    bool selected = false,
  }) {
    final isHovered = _hoveredRow == label;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hoveredRow = label),
      onExit: (_) {
        if (_hoveredRow == label) {
          setState(() => _hoveredRow = null);
        }
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(left: 4, right: 4, bottom: 2),
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(
            color: selected
                ? UuColors.primarySoft
                : isHovered
                    ? UuColors.hoverTint
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              const SizedBox(width: 21),
              Icon(icon, size: 22, color: UuTheme.accent),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: selected ? UuTheme.accent : UuTheme.textPrimary,
                  fontSize: 13,
                  fontWeight:
                      selected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMain(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        gFFI.recentPeersModel,
        gFFI.favoritePeersModel,
      ]),
      builder: (context, child) {
        return Obx(() {
          final peers = _allPeers();
          final selected = _selectedPeer(peers);
          final pageTitle = switch (_page) {
            _HomePage.allDevices => translate('All devices'),
            _HomePage.assist => translate('Remote assistance'),
            _HomePage.favorites => translate('Favorite devices'),
            _HomePage.home => null,
          };
          return Column(
            children: [
              _buildTopBar(context, selected, pageTitle: pageTitle),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(38, 28, 38, 28),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 960),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildDaemonBanner(),
                          _buildPageContent(context, selected),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        });
      },
    );
  }

  Widget _buildDaemonBanner() {
    if (!isMacOS || bind.isOutgoingOnly() || !bind.mainIsInstalled()) {
      return const SizedBox.shrink();
    }
    final installed = bind.mainIsInstalledDaemon(prompt: false);
    final stopped =
        bind.mainGetOptionSync(key: 'stop-service') == 'Y';
    if (installed && !stopped) {
      return const SizedBox.shrink();
    }
    final needInstall = !installed;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: UuColors.warningSoft,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: UuColors.warningBorder),
      ),
      child: Row(
        children: [
          const Icon(Icons.dns_outlined, color: UuColors.warningInk, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  needInstall ? translate('Install service') : translate('Service stopped'),
                  style: TextStyle(
                    color: UuTheme.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  needInstall
                      ? translate('Install it to let this Mac receive remote connections from phones and other devices')
                      : translate('Start the service to receive remote connections.'),
                  style: TextStyle(
                    color: UuTheme.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          FilledButton(
            onPressed: () async {
              if (needInstall) {
                bind.mainIsInstalledDaemon(prompt: true);
              } else {
                await start_service(true);
              }
              if (mounted) setState(() {});
            },
            style: FilledButton.styleFrom(
              backgroundColor: UuColors.warningInk,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: Text(needInstall ? translate('Install') : translate('Start')),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context, Peer? selected) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        selected == null
            ? _buildEmptyHero(context)
            : _buildHero(context, selected),
        const SizedBox(height: 14),
        _buildActionBar(context, peer: selected),
        const SizedBox(height: 28),
        _buildRecentConnections(context),
        const SizedBox(height: 26),
        _buildTools(context),
      ],
    );
  }

  Widget _buildRecentConnections(BuildContext context) {
    final peers = _recentPeers();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        UuSectionTitle(
          translate('Recent connections'),
          trailing: TextButton(
            onPressed: () => setState(() => _page = _HomePage.allDevices),
            style: TextButton.styleFrom(
              foregroundColor: UuColors.textSecondary,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(0, 32),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(translate('All devices'), style: TextStyle(fontSize: 12)),
          ),
        ),
        if (peers.isEmpty)
          UuCard(
            bordered: true,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
            child: Row(
              children: [
                Icon(Icons.history_rounded,
                    size: 20, color: UuColors.textTertiary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    translate('No recent connections. Enter a device ID or pick a device on the left to start.'),
                    style: TextStyle(
                      color: UuColors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => _showQuickConnect(),
                  child: Text(translate('Enter ID'), style: TextStyle(fontSize: 13)),
                ),
              ],
            ),
          )
        else
          for (final peer in peers) _recentRow(peer),
      ],
    );
  }

  Widget _recentRow(Peer peer) {
    final hovered = _hoveredRow == 'recent:${peer.id}';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hoveredRow = 'recent:${peer.id}'),
        onExit: (_) {
          if (_hoveredRow == 'recent:${peer.id}') {
            setState(() => _hoveredRow = null);
          }
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() {
            _page = _HomePage.home;
            _selectedId = peer.id;
          }),
          child: UuCard(
            bordered: true,
            color: hovered ? UuColors.hoverTint : null,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                _allDeviceIcon(UuPeerPlatformIcon.iconFor(peer.platform),
                    online: peer.online),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        uuPeerName(peer),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: UuColors.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${translate(peer.online ? 'Online' : 'Offline')} · ${peer.platform.isEmpty ? peer.id : peer.platform}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: peer.online
                              ? UuColors.success
                              : UuColors.textTertiary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                UuPillButton(
                  label: translate('Connect'),
                  height: 32,
                  onPressed: () => _connectPeer(peer),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTools(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        UuSectionTitle(translate('Quick tools')),
        UuCard(
          bordered: true,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(UuRadius.lg),
            child: Row(
              children: [
                _toolTile(Icons.add_rounded, translate('Add device'),
                    () => _showQuickConnect()),
                _actionDivider(),
                _toolTile(
                  Icons.swap_horiz,
                  translate('File transfer'),
                  () => _showQuickConnect(isFileTransfer: true),
                ),
                _actionDivider(),
                _toolTile(
                  Icons.support_agent,
                  translate('Remote assistance'),
                  () => setState(() => _page = _HomePage.assist),
                ),
                _actionDivider(),
                _toolTile(
                  Icons.help_outline_rounded,
                  translate('Help and feedback'),
                  () =>
                      unawaited(launchUrlString('https://rustdesk.com/docs/')),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _toolTile(IconData icon, String label, VoidCallback onTap) {
    final hovered = _hoveredRow == 'tool:$label';
    return Expanded(
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hoveredRow = 'tool:$label'),
        onExit: (_) {
          if (_hoveredRow == 'tool:$label') {
            setState(() => _hoveredRow = null);
          }
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Container(
            color: hovered ? UuColors.hoverTint : Colors.transparent,
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Column(
              children: [
                Icon(icon, size: 22, color: UuColors.primary),
                const SizedBox(height: 7),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: UuColors.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPageContent(BuildContext context, Peer? selected) {
    switch (_page) {
      case _HomePage.home:
        return _buildContent(context, selected);
      case _HomePage.allDevices:
        return _buildAllDevices(context);
      case _HomePage.assist:
        return _buildAssist(context);
      case _HomePage.favorites:
        return _buildFavorites(context);
    }
  }

  bool _isMobilePeer(Peer peer) {
    final platform = peer.platform.toLowerCase();
    return platform.contains('android') ||
        platform.contains('ios') ||
        platform.contains('iphone') ||
        platform.contains('ipad');
  }

  Widget _buildAllDevices(BuildContext context) {
    final peers = _allPeers();
    final desktops = peers.where((p) => !_isMobilePeer(p)).toList();
    final mobiles = peers.where(_isMobilePeer).toList();
    final syncHint = peers.isEmpty ? _accountSyncHint() : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (syncHint != null) ...[
          syncHint,
          const SizedBox(height: 18),
        ],
        _groupHeader(translate('Computers: {${desktops.length + 1}}')),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _deviceCard(
              name: Platform.localHostname,
              id: _localId,
              online: true,
              icon: UuPeerPlatformIcon.localIcon(),
              local: true,
              onTap: _showLocalInfo,
              onInfo: _showLocalInfo,
            ),
            for (final peer in desktops)
              _deviceCard(
                name: uuPeerName(peer),
                id: peer.id,
                online: peer.online,
                icon: UuPeerPlatformIcon.iconFor(peer.platform),
                onTap: () => setState(() {
                  _page = _HomePage.home;
                  _selectedId = peer.id;
                }),
                onInfo: () => _showPeerInfo(peer),
              ),
          ],
        ),
        const SizedBox(height: 22),
        _groupHeader(translate('Phones/tablets: {${mobiles.length}}')),
        if (mobiles.isEmpty)
          _groupHint(translate('No phones or tablets yet. Sign in and sync your account to see them here.'))
        else
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final peer in mobiles)
                _deviceCard(
                  name: uuPeerName(peer),
                  id: peer.id,
                  online: peer.online,
                  icon: UuPeerPlatformIcon.iconFor(peer.platform),
                  onTap: () => setState(() {
                    _page = _HomePage.home;
                    _selectedId = peer.id;
                  }),
                  onInfo: () => _showPeerInfo(peer),
                ),
            ],
          ),
      ],
    );
  }

  Widget _groupHint(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
      decoration: BoxDecoration(
        color: UuColors.surfaceAlt,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: UuColors.divider),
      ),
      child: Text(
        text,
        style: TextStyle(color: UuColors.textSecondary, fontSize: 13),
      ),
    );
  }

  Widget? _accountSyncHint() {
    if (!gFFI.userModel.isLogin) {
      return null;
    }
    final error = gFFI.abModel.abPullError.value;
    if (error.isNotEmpty) {
      return Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        decoration: BoxDecoration(
          color: UuColors.warningSoft,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: UuColors.warningBorder),
        ),
        child: Row(
          children: [
            const Icon(Icons.cloud_off_outlined,
                size: 20, color: UuColors.warningInk),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    translate('Failed to sync account devices'),
                    style: TextStyle(
                      color: UuColors.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    error,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: UuColors.textSecondary, fontSize: 12),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: () => unawaited(
                  gFFI.abModel.pullAb(force: ForcePullAb.current, quiet: true)),
              child: Text(translate('Try again'), style: TextStyle(fontSize: 13)),
            ),
          ],
        ),
      );
    }
    if (gFFI.abModel.currentAbLoading.value) {
      return Row(
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: UuColors.primary,
            ),
          ),
          SizedBox(width: 10),
          Text(
            translate('Syncing account devices...'),
            style: TextStyle(color: UuColors.textSecondary, fontSize: 13),
          ),
        ],
      );
    }
    return null;
  }

  Widget _groupHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(
            Icons.keyboard_arrow_down,
            size: 22,
            color: UuTheme.textSecondary,
          ),
          const SizedBox(width: 8),
          Text(
            title,
            style: TextStyle(
              color: UuTheme.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _deviceCard({
    required String name,
    required String id,
    required bool online,
    required IconData icon,
    required VoidCallback onTap,
    VoidCallback? onInfo,
    bool local = false,
  }) {
    return Container(
      width: 268,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: UuTheme.divider),
      ),
      child: Material(
        color: UuColors.surface,
        child: InkWell(
          hoverColor: UuColors.hoverTint,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 10, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _allDeviceIcon(icon, online: local || online),
                    const Spacer(),
                    if (local)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: UuColors.primarySoft,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          translate('This device'),
                          style:
                              TextStyle(color: UuColors.primary, fontSize: 12),
                        ),
                      )
                    else
                      _statusText(online),
                    if (onInfo != null)
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: onInfo,
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(6, 2, 2, 2),
                          child: Icon(
                            Icons.info_outline,
                            size: 18,
                            color: UuColors.textTertiary,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: UuTheme.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  local ? translate('This device · ID {$id}') : 'ID $id',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: UuColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _statusText(bool online) {
    final color = online ? UuColors.success : UuColors.textTertiary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(online ? translate('Online') : translate('Offline'),
            style: TextStyle(color: color, fontSize: 12)),
      ],
    );
  }

  Widget _allDeviceIcon(IconData icon, {bool online = true}) {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: online ? UuColors.primary : UuColors.border,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon,
          color: online ? Colors.white : UuColors.textTertiary, size: 24),
    );
  }

  void _showPeerInfo(Peer peer) {
    showUuDialog<void>(
      context,
      title: uuPeerName(peer),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('ID: ${peer.id}',
              style: TextStyle(
                  color: UuColors.textSecondary, fontSize: 13)),
          const SizedBox(height: 6),
          Text(translate('Platform: {${peer.platform}}'),
              style: TextStyle(
                  color: UuColors.textSecondary, fontSize: 13)),
          const SizedBox(height: 6),
          Text(translate('Status: {${translate(peer.online ? 'Online' : 'Offline')}}'),
              style: TextStyle(
                  color: UuColors.textSecondary, fontSize: 13)),
        ],
      ),
      actions: [
        uuDialogTextButton(translate('Rename'), () async {
          Navigator.of(context).pop();
          final renamed = await showUuRenameDevice(
            context,
            id: peer.id,
            currentAlias: peer.alias,
          );
          if (renamed != null && mounted) {
            setState(() {});
          }
        }),
        uuDialogFilledButton(
            translate('Close'), () => Navigator.of(context).pop()),
      ],
    );
  }

  Future<void> _renamePeer(Peer peer) async {
    final renamed = await showUuRenameDevice(
      context,
      id: peer.id,
      currentAlias: peer.alias,
    );
    if (renamed != null && mounted) {
      setState(() {});
    }
  }

  Future<void> _deletePeer(Peer peer) async {
    final id = peer.id;
    final name = uuPeerName(peer);
    final inAddressBook =
        gFFI.abModel.currentAbPeers.any((item) => item.id == id);
    final ok = await showUuConfirm(
      context,
      title: translate('Delete device'),
      message: inAddressBook
          ? translate(
              'This will remove {$name} from your account devices; you will need to add it again.')
          : translate('This will remove {$name} from recent connections.'),
      confirmText: translate('Delete'),
      danger: true,
    );
    if (!ok || !mounted) {
      return;
    }
    var deleted = false;
    if (inAddressBook) {
      deleted = await gFFI.abModel.deletePeers([id]);
    } else {
      await bind.mainRemovePeer(id: id);
      bind.mainLoadRecentPeers();
      deleted = true;
    }
    if (!mounted) {
      return;
    }
    if (deleted) {
      setState(() {
        if (_selectedId == id) {
          _selectedId = null;
          _page = _HomePage.home;
        }
      });
      uuToast(translate('Deleted'));
    } else {
      uuToast(translate('Delete failed. Please try again later.'));
    }
  }

  Widget _buildAssist(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _assistCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    translate('This device'),
                    style: TextStyle(
                      color: UuTheme.textPrimary,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    translate('Allow remote assistance'),
                    style: TextStyle(
                      color: UuTheme.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                  Switch(
                    value: _allowAssist,
                    activeColor: UuTheme.accent,
                    onChanged: (value) =>
                        setState(() => _allowAssist = value),
                  ),
                ],
              ),
              Divider(height: 30, color: UuColors.border),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          translate('This device ID'),
                          style: TextStyle(
                            color: UuTheme.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 6),
                        ValueListenableBuilder<TextEditingValue>(
                          valueListenable: gFFI.serverModel.serverId,
                          builder: (context, value, child) {
                            return SelectableText(
                              value.text,
                              style: TextStyle(
                                color: UuTheme.textPrimary,
                                fontSize: 26,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1,
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        UuMenuButton<String>(
                          width: 220,
                          entriesBuilder: (context) => [
                            for (final option in _verificationOptions)
                              UuMenuItem(
                                value: option.$1,
                                label: option.$2,
                                selected:
                                    gFFI.serverModel.verificationMethod ==
                                        option.$1,
                              ),
                          ],
                          onSelected: _setVerificationMethod,
                          child: _AssistMethodTrigger(label: _verificationLabel),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            ValueListenableBuilder<TextEditingValue>(
                              valueListenable:
                                  gFFI.serverModel.serverPasswd,
                              builder: (context, value, child) {
                                return Text(
                                  _showAssistPassword
                                      ? value.text
                                      : '••••••••',
                                  style: TextStyle(
                                    color: UuTheme.textPrimary,
                                    fontSize: 22,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 1.5,
                                  ),
                                );
                              },
                            ),
                            const SizedBox(width: 8),
                            UuHoverIconButton(
                              icon: Icons.visibility_outlined,
                              iconSize: 20,
                              size: 34,
                              onTap: () => setState(() => _showAssistPassword =
                                  !_showAssistPassword),
                            ),
                            UuHoverIconButton(
                              key: _assistGearKey,
                              icon: Icons.settings_outlined,
                              iconSize: 20,
                              size: 34,
                              onTap: _showAssistGearMenu,
                            ),
                            const SizedBox(width: 6),
                            UuSoftButton(
                              label: translate('Copy and share'),
                              onTap: _copyAssist,
                              height: 36,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _assistRefreshLabel,
                          style: TextStyle(
                            color: UuTheme.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        _assistCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                translate('Remote partner device'),
                style: TextStyle(
                  color: UuTheme.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                translate("Start remote control with another device's ID and verification code"),
                style: TextStyle(
                  color: UuTheme.textSecondary,
                  fontSize: 13,
                ),
              ),
              Divider(height: 30, color: UuColors.border),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _assistIdController,
                      decoration: InputDecoration(
                        hintText: translate('Please enter a device ID'),
                        filled: true,
                        fillColor: UuColors.background,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: UuColors.border),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: UuColors.border),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 18),
                  SizedBox(
                    width: 104,
                    child: UuPrimaryButton(
                      label: translate('Connect'),
                      onTap: _connectAssist,
                      height: 44,
                      radius: UuRadius.pill,
                      fontSize: 15,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _assistCard({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: UuColors.surface,
        borderRadius: BorderRadius.circular(UuRadius.lg),
        border: Border.all(color: UuColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(UuColors.isDark ? 0.28 : 0.04),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: child,
    );
  }

  List<(String, String)> get _verificationOptions => [
        (kUseTemporaryPassword, translate('Use one-time password')),
        (kUsePermanentPassword, translate('Use permanent password')),
        (kUseBothPasswords, translate('Use both passwords')),
      ];

  String get _verificationLabel {
    final current = gFFI.serverModel.verificationMethod;
    for (final option in _verificationOptions) {
      if (option.$1 == current) {
        return option.$2;
      }
    }
    return translate('Use both passwords');
  }

  String get _assistRefreshLabel {
    switch (_autoRefresh) {
      case '1h':
        return translate('Every hour');
      case '12h':
        return translate('Every 12 hours');
      case '24h':
        return translate('Every 24 hours');
      case 'off':
        return translate('Never');
      default:
        return translate('After each session');
    }
  }

  Future<void> _setVerificationMethod(String value) async {
    final model = gFFI.serverModel;
    Future<void> apply() async {
      await model.setVerificationMethod(value);
      await model.updatePasswordModel();
      if (mounted) {
        setState(() {});
      }
    }

    if (value == kUsePermanentPassword &&
        await bind.mainGetCommon(key: 'permanent-password-set') != 'true') {
      if (isChangePermanentPasswordDisabled()) {
        await apply();
        return;
      }
      setPasswordDialog(notEmptyCallback: apply);
    } else {
      await apply();
    }
  }

  Future<void> _showSettingsDialog() async {
    await showUuSettingsDialog(context);
  }

  Future<void> _showAboutDialog() async {
    final version = await bind.mainGetVersion();
    if (!mounted) {
      return;
    }
    await showUuDialog<void>(
      context,
      title: bind.mainGetAppNameSync(),
      message: translate('Version {$version}'),
      actions: [
        uuDialogFilledButton(translate('Close'), () => Navigator.of(context).pop()),
      ],
    );
  }

  Future<void> _showAssistGearMenu() async {
    final box =
        _assistGearKey.currentContext?.findRenderObject() as RenderBox?;
    final offset =
        box?.localToGlobal(Offset.zero) ?? const Offset(200, 200);
    final anchor = box == null
        ? const Rect.fromLTWH(200, 200, 0, 0)
        : Rect.fromLTWH(offset.dx, offset.dy, box.size.width, box.size.height);
    final value = await showUuMenu<String>(
      context,
      anchorRect: anchor,
      width: 220,
      entries: [
        UuMenuItem(
          value: 'now',
          label: translate('Refresh now'),
          icon: Icons.refresh,
        ),
        UuMenuItem(
          value: 'auto',
          label: translate('Auto refresh'),
          icon: Icons.autorenew,
          trailing: Icon(
            Icons.chevron_right,
            size: 16,
            color: UuColors.textTertiary,
          ),
        ),
      ],
    );
    if (!mounted) {
      return;
    }
    if (value == 'now') {
      unawaited(bind.mainUpdateTemporaryPassword());
    } else if (value == 'auto') {
      final interval = await showUuMenu<String>(
        context,
        anchorRect: Rect.fromLTWH(offset.dx + 150, offset.dy + 74, 0, 0),
        width: 200,
        entries: [
          for (final option in [
            ('after-session', translate('After each session')),
            ('1h', translate('Every hour')),
            ('12h', translate('Every 12 hours')),
            ('24h', translate('Every 24 hours')),
            ('off', translate('Never')),
          ])
            UuMenuItem(
              value: option.$1,
              label: option.$2,
              selected: _autoRefresh == option.$1,
            ),
        ],
      );
      if (interval != null) {
        setState(() => _autoRefresh = interval);
        _applyAssistRefresh(interval);
      }
    }
  }

  void _applyAssistRefresh(String interval) {
    _assistRefreshTimer?.cancel();
    _assistRefreshTimer = null;
    Duration? duration;
    switch (interval) {
      case '1h':
        duration = const Duration(hours: 1);
        break;
      case '12h':
        duration = const Duration(hours: 12);
        break;
      case '24h':
        duration = const Duration(hours: 24);
        break;
    }
    if (duration != null) {
      _assistRefreshTimer = Timer.periodic(
        duration,
        (_) => unawaited(bind.mainUpdateTemporaryPassword()),
      );
    }
  }

  void _copyAssist() {
    final id = gFFI.serverModel.serverId.text;
    final password = gFFI.serverModel.serverPasswd.text;
    Clipboard.setData(ClipboardData(text: '$id $password'));
    uuToast(translate('Copied'));
  }

  Future<void> _connectAssist() async {
    final id = _assistIdController.text.replaceAll(' ', '').trim();
    if (id.isEmpty) {
      uuToast(translate('Please enter a device ID'));
      return;
    }
    await connect(context, id);
  }

  Widget _buildFavorites(BuildContext context) {
    final localId = _localId;
    final favorites = gFFI.favoritePeersModel.peers
        .where((p) =>
            p.id.isNotEmpty &&
            (localId.isEmpty || p.id != localId) &&
            !_isIosPeer(p))
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: () =>
                setState(() => _page = _HomePage.allDevices),
            style: TextButton.styleFrom(
              backgroundColor: UuColors.hover,
              foregroundColor: UuTheme.textSecondary,
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 10),
            ),
            child: Text(translate('Add favorite device')),
          ),
        ),
        const SizedBox(height: 10),
        if (favorites.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 140),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                      color: UuColors.primarySoft,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(
                      Icons.inventory_2_outlined,
                      size: 48,
                      color: UuColors.primary,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    translate('No favorites'),
                    style: TextStyle(
                      color: UuTheme.textSecondary,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final peer in favorites)
                _deviceCard(
                  name: uuPeerName(peer),
                  id: peer.id,
                  online: peer.online,
                  icon: UuPeerPlatformIcon.iconFor(peer.platform),
                  onTap: () => setState(() {
                    _page = _HomePage.home;
                    _selectedId = peer.id;
                  }),
                  onInfo: () => _showPeerInfo(peer),
                ),
            ],
          ),
      ],
    );
  }

  Widget _buildTopBar(
    BuildContext context,
    Peer? selected, {
    String? pageTitle,
  }) {
    final online = selected?.online ??
        gFFI.serverModel.serverId.text.isNotEmpty;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onPanStart: (_) => windowManager.startDragging(),
      onDoubleTap: isMacOS || kUseCompatibleUiMode
          ? null
          : () => toggleMaximize(true)
              .then((value) => stateGlobal.setMaximized(value)),
      child: Container(
      height: 52,
      padding: EdgeInsets.only(left: 24, right: isMacOS ? 24 : 8),
      decoration: BoxDecoration(
        color: UuColors.surface,
        border: Border(bottom: BorderSide(color: UuTheme.divider)),
      ),
      child: Row(
        children: [
          if (pageTitle == null) ...[
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF111827),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color:
                          online ? UuTheme.online : UuTheme.offline,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    online ? translate('Online') : translate('Offline'),
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 14),
          ],
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    pageTitle ??
                        (selected == null
                            ? translate('My devices')
                            : uuPeerName(selected)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: UuTheme.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (pageTitle == null)
                  UuMenuButton<String>(
                    width: 180,
                    icon: Icons.more_vert,
                    onSelected: (value) {
                      if (selected == null) {
                        return;
                      }
                      switch (value) {
                        case 'refresh':
                          bind.mainLoadRecentPeers();
                          if (gFFI.abModel.currentAbPeers
                              .any((peer) => peer.id == selected.id)) {
                            unawaited(gFFI.abModel.pullAb(
                                force: ForcePullAb.current, quiet: true));
                          }
                          break;
                        case 'rename':
                          unawaited(_renamePeer(selected));
                          break;
                        case 'delete':
                          unawaited(_deletePeer(selected));
                          break;
                      }
                    },
                    entriesBuilder: (context) => [
                      UuMenuItem(
                        value: 'refresh',
                        label: translate('Refresh devices'),
                        icon: Icons.refresh,
                      ),
                      UuMenuItem(
                        value: 'rename',
                        label: translate('Rename'),
                        icon: Icons.drive_file_rename_outline,
                      ),
                      UuMenuItem(
                        value: 'delete',
                        label: translate('Delete device'),
                        icon: Icons.delete_outline,
                        danger: true,
                      ),
                    ],
                  ),
              ],
            ),
          ),
          Stack(
            clipBehavior: Clip.none,
            children: [
              _HoverCircle(
                icon: Icons.notifications_none,
                onTap: _showNotifications,
              ),
              if (_needsPermissions || _daemonProblem)
                Positioned(
                  right: 2,
                  top: 2,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: UuColors.warning,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 8),
          Obx(() {
            final loggedIn = gFFI.userModel.isLogin;
            final label =
                loggedIn ? gFFI.userModel.displayNameOrUserName : translate('Login / Register');
            return Material(
              color: Colors.transparent,
              child: InkWell(
                hoverColor: UuColors.hoverTint,
                borderRadius: BorderRadius.circular(999),
                onTap: () => uuAccountDialog(context),
                child: Container(
                  height: 36,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: loggedIn ? UuTheme.accentSoft : UuColors.surface,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: UuTheme.divider),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        loggedIn ? Icons.person : Icons.person_outline,
                        size: 17,
                        color: UuTheme.accent,
                      ),
                      const SizedBox(width: 6),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 110),
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: UuTheme.textPrimary,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
          const SizedBox(width: 4),
          UuMenuButton<String>(
            tooltip: translate('Settings'),
            width: 224,
            child: const _CircleSurface(icon: Icons.settings_outlined),
            onSelected: (value) {
              switch (value) {
                case 'settings':
                  _showSettingsDialog();
                  break;
                case 'help':
                  unawaited(launchUrlString('https://rustdesk.com/docs/'));
                  break;
                case 'about':
                  _showAboutDialog();
                  break;
                case 'logout':
                  unawaited(_logout());
                  break;
                case 'check-update':
                  checkUpdate();
                  break;
                case 'local':
                  _showLocalInfo();
                  break;
                case 'hero':
                  _pickHeroImage();
                  break;
                case 'hero-reset':
                  _resetHeroImage();
                  break;
                case 'demo':
                  setState(() => _demoVisible = !_demoVisible);
                  break;
              }
            },
            entriesBuilder: (context) => [
              _menuItem('settings', Icons.settings_outlined, translate('Settings')),
              _menuItem('help', Icons.help_outline, translate('Help and feedback')),
              _menuItem('about', Icons.info_outline, translate('About')),
              if (gFFI.userModel.isLogin)
                _menuItem('logout', Icons.logout, translate('Sign out')),
              _menuItem(
                'check-update',
                Icons.system_update_alt,
                translate('Check for updates'),
              ),
              const UuMenuDivider<String>(),
              _menuItem(
                'demo',
                _demoVisible
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                _demoVisible ? translate('Hide demo devices') : translate('Show demo devices'),
              ),
              _menuItem('local', Icons.computer_outlined, translate('Local device info')),
              _menuItem('hero', Icons.image_outlined, translate('Change background image')),
              if (_heroImage.isNotEmpty)
                _menuItem(
                  'hero-reset',
                  Icons.hide_image_outlined,
                  translate('Reset background'),
                ),
            ],
          ),
          if (!isMacOS && !kUseCompatibleUiMode) ...[
            const SizedBox(width: 10),
            UuWindowControls(
              isMainWindow: true,
              iconColor: UuTheme.textSecondary,
            ),
          ],
        ],
      ),
      ),
    );
  }

  UuMenuItem<String> _menuItem(
    String value,
    IconData icon,
    String label,
  ) {
    return UuMenuItem<String>(
      value: value,
      label: label,
      icon: icon,
      height: 34,
    );
  }

  Widget _buildHero(BuildContext context, Peer peer) {
    return Container(
      height: 240,
      width: double.infinity,
      decoration: _heroDecoration(),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          children: [
            Positioned(
              right: -24,
              bottom: -34,
              child: Icon(
                UuPeerPlatformIcon.iconFor(peer.platform),
                size: 310,
                color: Colors.white.withOpacity(0.10),
              ),
            ),
            Positioned.fill(
              child: UuWallpaperLayer(
                peerId: peer.id,
                fallback: const SizedBox.shrink(),
              ),
            ),
            const Positioned.fill(
              child: ColoredBox(color: Colors.black26),
            ),
            Padding(
              padding: const EdgeInsets.all(26),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Spacer(),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              uuPeerName(peer),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.w700,
                                shadows: [
                                  Shadow(blurRadius: 8, color: Colors.black45)
                                ],
                              ),
                            ),
                            const SizedBox(height: 7),
                            Row(
                              children: [
                                Container(
                                  width: 7,
                                  height: 7,
                                  decoration: BoxDecoration(
                                    color: peer.online
                                        ? UuColors.success
                                        : Colors.white54,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    peer.platform.isEmpty
                                        ? (peer.online ? translate('Online') : translate('Offline'))
                                        : '${translate(peer.online ? 'Online' : 'Offline')} · ${peer.platform}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      _enterDesktopButton(() => _connectPeer(peer)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyHero(BuildContext context) {
    final loggedIn = gFFI.userModel.isLogin;
    return UuCard(
      bordered: true,
      padding: const EdgeInsets.fromLTRB(28, 26, 24, 24),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: UuColors.primarySoft,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.devices_rounded,
                      size: 26, color: UuColors.primary),
                ),
                const SizedBox(height: 16),
                Text(
                  translate('Start remote control'),
                  style: TextStyle(
                    color: UuColors.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  loggedIn
                      ? translate('Pick a device on the left, or enter its ID to start connecting.')
                      : translate("Sign in to sync devices automatically, or enter the other device's ID to connect."),
                  style: TextStyle(
                    color: UuColors.textSecondary,
                    fontSize: 13,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 18),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    if (!loggedIn)
                      UuPillButton(
                        label: translate('Sign in to sync devices'),
                        icon: Icons.person_outline,
                        filled: false,
                        onPressed: () => uuAccountDialog(context),
                      ),
                    UuPillButton(
                      label: translate('Connect with ID'),
                      icon: Icons.dialpad_rounded,
                      filled: loggedIn,
                      onPressed: () => _showQuickConnect(),
                    ),
                    UuPillButton(
                      label: translate('Local device info'),
                      icon: Icons.computer_outlined,
                      filled: false,
                      onPressed: _showLocalInfo,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 20),
          SizedBox(
            width: 150,
            height: 150,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 118,
                  height: 118,
                  decoration: BoxDecoration(
                    color: UuColors.primarySoft,
                    shape: BoxShape.circle,
                  ),
                ),
                const Icon(Icons.desktop_windows,
                    size: 52, color: UuColors.primary),
                Positioned(
                  right: 8,
                  bottom: 18,
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: UuColors.surface,
                      shape: BoxShape.circle,
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x1A161A22),
                          blurRadius: 12,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Icon(Icons.phone_iphone,
                        size: 22, color: UuColors.success),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _enterDesktopButton(VoidCallback onTap) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        backgroundColor: UuColors.surface,
        foregroundColor: UuColors.textPrimary,
        overlayColor: UuColors.primarySoft,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(UuRadius.pill),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            translate('Enter desktop'),
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          SizedBox(width: 6),
          Icon(Icons.arrow_forward_rounded, size: 18),
        ],
      ),
    );
  }

  Widget _buildActionBar(BuildContext context, {Peer? peer}) {
    void run({
      bool isFileTransfer = false,
      bool isTerminal = false,
      bool isTcpTunneling = false,
      bool isViewCamera = false,
    }) {
      if (peer != null) {
        _connectPeer(
          peer,
          isFileTransfer: isFileTransfer,
          isTerminal: isTerminal,
          isTcpTunneling: isTcpTunneling,
          isViewCamera: isViewCamera,
        );
      } else {
        _showQuickConnect(
          isFileTransfer: isFileTransfer,
          isTerminal: isTerminal,
          isTcpTunneling: isTcpTunneling,
          isViewCamera: isViewCamera,
        );
      }
    }

    return Container(
      decoration: BoxDecoration(
        color: UuColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: UuTheme.divider),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: [
          _action(
            Icons.swap_horiz,
            translate('File transfer'),
            () => run(isFileTransfer: true),
          ),
          _actionDivider(),
          _action(
            Icons.play_circle_outline,
            translate('View only'),
            () => run(),
          ),
          _actionDivider(),
          _action(
            Icons.terminal,
            translate('Terminal'),
            () => run(isTerminal: true),
          ),
          _actionDivider(),
          Expanded(
            child: Center(
              child: UuMenuButton<String>(
                tooltip: translate('More'),
                width: 184,
                icon: Icons.grid_view,
                onSelected: (value) {
                  if (value == 'camera') {
                    run(isViewCamera: true);
                  } else if (value == 'copy' && peer != null) {
                    Clipboard.setData(ClipboardData(text: peer.id));
                    uuToast(translate('Copied'));
                  }
                },
                entriesBuilder: (context) => [
                  UuMenuItem(
                    value: 'camera',
                    label: translate('Camera'),
                    icon: Icons.photo_camera_outlined,
                  ),
                  if (peer != null)
                    UuMenuItem(
                      value: 'copy',
                      label: translate('Copy ID'),
                      icon: Icons.copy_outlined,
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _action(IconData icon, String label, VoidCallback onTap) {
    final isHovered = _hoveredRow == label;
    return Expanded(
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hoveredRow = label),
        onExit: (_) {
          if (_hoveredRow == label) {
            setState(() => _hoveredRow = null);
          }
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Container(
            color: isHovered ? UuColors.hoverTint : Colors.transparent,
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 20, color: UuTheme.textSecondary),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: UuTheme.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
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

  Widget _actionDivider() {
    return Container(width: 1, height: 22, color: UuTheme.divider);
  }

  Widget _buildPermissionBanner(BuildContext context) {
    if (!isMacOS) {
      return const SizedBox.shrink();
    }
    final needsScreen = !bind.mainIsCanScreenRecording(prompt: false);
    final needsAccess = !bind.mainIsProcessTrusted(prompt: false);
    final needsInput = !bind.mainIsCanInputMonitoring(prompt: false);
    if (!needsScreen && !needsAccess && !needsInput) {
      return const SizedBox.shrink();
    }
    final text = needsScreen
        ? translate('config_screen')
        : needsAccess
            ? translate('config_acc')
            : translate('config_input');
    return Container(
      margin: const EdgeInsets.fromLTRB(38, 12, 38, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: UuColors.warningSoft,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: UuColors.warningBorder),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            size: 16,
            color: UuColors.warning,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: UuTheme.textSecondary,
                fontSize: 12,
              ),
            ),
          ),
          TextButton(
            onPressed: _requestPermissions,
            child: Text(translate('Configure')),
          ),
        ],
      ),
    );
  }
}

class _HoverCircle extends StatefulWidget {
  const _HoverCircle({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  State<_HoverCircle> createState() => _HoverCircleState();
}

class _HoverCircleState extends State<_HoverCircle> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: _circleDecoration(_hovered, widget.icon),
      ),
    );
  }
}

class _CircleSurface extends StatefulWidget {
  const _CircleSurface({required this.icon});

  final IconData icon;

  @override
  State<_CircleSurface> createState() => _CircleSurfaceState();
}

class _CircleSurfaceState extends State<_CircleSurface> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    UuColors.apply(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: _circleDecoration(_hovered, widget.icon),
    );
  }
}

class _AssistMethodTrigger extends StatefulWidget {
  const _AssistMethodTrigger({required this.label});

  final String label;

  @override
  State<_AssistMethodTrigger> createState() => _AssistMethodTriggerState();
}

class _AssistMethodTriggerState extends State<_AssistMethodTrigger> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: _hovered
              ? UuColors.primarySoft
              : UuColors.primarySoft.withOpacity(0),
          borderRadius: BorderRadius.circular(UuRadius.sm),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              translate('Verification method:'),
              style: TextStyle(
                color: UuColors.textSecondary,
                fontSize: 12,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              widget.label,
              style: TextStyle(
                color: UuColors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.unfold_more,
              size: 16,
              color: _hovered ? UuColors.primary : UuColors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}

Widget _circleDecoration(bool hovered, IconData icon) {
  return Container(
    width: 36,
    height: 36,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: hovered ? UuColors.hoverTint : UuColors.surface,
      border: Border.all(color: UuColors.border),
    ),
    child: Icon(icon,
        size: 18, color: hovered ? UuTheme.accent : UuTheme.textSecondary),
  );
}

