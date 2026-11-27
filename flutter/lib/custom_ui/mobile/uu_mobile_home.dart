import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/common/formatter/id_formatter.dart';
import 'package:flutter_hbb/mobile/pages/settings_page.dart';
import 'package:flutter_hbb/models/ab_model.dart';
import 'package:flutter_hbb/models/peer_model.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/models/user_model.dart';
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher_string.dart';

import '../design/uu_tokens.dart';
import '../theme.dart';
import '../uu_auth.dart';
import '../uu_peer.dart';
import '../uu_wallpaper.dart';
import '../widgets/uu_account.dart';
import '../widgets/uu_components.dart';
import '../widgets/uu_feedback.dart';
import '../widgets/uu_menu.dart';
import '../widgets/uu_platform_icon.dart';
import 'uu_device_detail_page.dart';
import 'uu_mobile_login_page.dart';
import 'uu_settings_page.dart';

/// UU 远程风格的 iOS 首页：我的设备 / 远程协助 / 我的。
class UuMobileHome extends StatefulWidget {
  const UuMobileHome({super.key});

  @override
  State<UuMobileHome> createState() => _UuMobileHomeState();
}

class _UuMobileHomeState extends State<UuMobileHome> {
  Color get _bg => UuColors.background;
  Color get _muted => UuColors.textSecondary;
  Color get _hairline => UuColors.divider;

  int _tab = 0;
  Timer? _onlineTimer;
  Timer? _abTimer;
  bool _onlineCollapsed = false;
  bool _offlineCollapsed = false;
  final Map<Peers, VoidCallback> _peersListeners = {};
  final _assistId = TextEditingController();
  final _searchController = TextEditingController();
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    unawaited(bind.mainLoadRecentPeers());
    unawaited(uuSyncDeviceSecret());
    _assistId.addListener(_onAssistIdChanged);
    _initTracking();
  }

  @override
  void dispose() {
    _onlineTimer?.cancel();
    _abTimer?.cancel();
    _peersListeners.forEach((peers, listener) {
      peers.removeListener(listener);
    });
    _peersListeners.clear();
    _assistId.removeListener(_onAssistIdChanged);
    _assistId.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onAssistIdChanged() {
    if (mounted) setState(() {});
  }

  void _initTracking() {
    for (final peers in [
      gFFI.abModel.peersModel,
      gFFI.favoritePeersModel,
      gFFI.recentPeersModel,
    ]) {
      void listener() {
        if (mounted) setState(() {});
      }

      _peersListeners[peers] = listener;
      peers.addListener(listener);
    }
    _onlineTimer = Timer.periodic(
      const Duration(seconds: 8),
      (_) => _queryOnlineStatuses(),
    );
    _abTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (gFFI.userModel.isLogin) {
        unawaited(
            gFFI.abModel.pullAb(force: ForcePullAb.current, quiet: true));
      }
    });
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _queryOnlineStatuses());
  }

  String get _localId =>
      gFFI.serverModel.serverId.text.replaceAll(' ', '').trim();

  bool _isIosPeer(Peer peer) {
    final p = peer.platform.toLowerCase();
    return p.contains('ios') || p.contains('iphone') || p.contains('ipad');
  }

  List<Peer> _connectable(Iterable<Peer> peers) {
    final local = _localId;
    return peers
        .where((peer) =>
            peer.id.isNotEmpty &&
            (local.isEmpty || peer.id != local) &&
            !_isIosPeer(peer))
        .toList();
  }

  List<Peer> _accountPeers() => _connectable(gFFI.abModel.currentAbPeers);

  List<Peer> _allPeers() {
    final result = <Peer>[];
    final seen = <String>{};
    for (final peer in [
      ..._accountPeers(),
      ..._connectable(gFFI.favoritePeersModel.peers),
      ..._connectable(gFFI.recentPeersModel.peers),
    ]) {
      if (seen.add(peer.id)) {
        result.add(peer);
      }
    }
    return result;
  }

  void _queryOnlineStatuses() {
    final ids = _allPeers().map((peer) => peer.id).toSet().toList();
    if (ids.isEmpty) return;
    unawaited(bind.queryOnlines(ids: ids));
  }

  Future<void> _refresh() async {
    if (gFFI.userModel.isLogin) {
      await UserModel.updateOtherModels();
    }
    _queryOnlineStatuses();
    if (mounted) setState(() {});
  }

  Future<void> _openLogin({bool register = false}) async {
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => UuMobileLoginPage(initialRegister: register),
      ),
    );
    if (ok == true) {
      uuToast(translate('Signed in'));
      await UserModel.updateOtherModels();
      _queryOnlineStatuses();
      if (mounted) setState(() {});
    }
  }

  Future<void> _connect(Peer peer) async {
    if (!peer.online) {
      uuToast(translate('Device is offline and cannot be connected'));
      return;
    }
    await connect(context, peer.id, password: uuPeerPassword(peer));
  }

  Future<void> _connectFileTransfer(Peer peer) async {
    if (!peer.online) {
      uuToast(translate('Device is offline and cannot be connected'));
      return;
    }
    await connect(
      context,
      peer.id,
      password: uuPeerPassword(peer),
      isFileTransfer: true,
    );
  }

  void _openDetail(Peer peer) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => UuDeviceDetailPage(peer: peer)),
    );
  }

  String _maskName(String name) {
    if (RegExp(r'^\d{11}$').hasMatch(name)) {
      return '${name.substring(0, 3)}•••••${name.substring(9)}';
    }
    return name;
  }

  List<Color> _thumbnailColors(String platform) {
    final p = platform.toLowerCase();
    if (p.contains('mac') || p.contains('ios')) {
      return const [Color(0xFF5B7CFA), Color(0xFFB18CFF)];
    }
    if (p.contains('win')) {
      return const [Color(0xFF22C1C3), Color(0xFF2563EB)];
    }
    if (p.contains('android')) {
      return const [Color(0xFF34D399), Color(0xFF0EA5E9)];
    }
    if (p.contains('linux')) {
      return const [Color(0xFFF59E0B), Color(0xFFEF4444)];
    }
    return const [Color(0xFF94A3B8), Color(0xFF475569)];
  }

  @override
  Widget build(BuildContext context) {
    UuColors.apply(context);
    return Scaffold(
      backgroundColor: _bg,
      body: IndexedStack(
        index: _tab,
        children: [
          _buildDevicesTab(),
          _buildAssistTab(),
          _buildMeTab(),
        ],
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          color: UuColors.surface,
          border: Border(top: BorderSide(color: _hairline, width: 0.5)),
        ),
        child: SafeArea(
          top: false,
          child: BottomNavigationBar(
            currentIndex: _tab,
            onTap: (index) => setState(() => _tab = index),
            type: BottomNavigationBarType.fixed,
            backgroundColor: UuColors.surface,
            elevation: 0,
            selectedItemColor: UuTheme.accent,
            unselectedItemColor: _muted,
            selectedFontSize: 12,
            unselectedFontSize: 12,
            items: [
              BottomNavigationBarItem(
                icon: Icon(Icons.devices_outlined),
                activeIcon: Icon(Icons.devices),
                label: translate('My devices'),
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.screen_share_outlined),
                activeIcon: Icon(Icons.screen_share),
                label: translate('Remote assistance'),
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.person_outline),
                activeIcon: Icon(Icons.person),
                label: translate('Me'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------- 设备 ----------------------------------

  Widget _buildDevicesTab() {
    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            Row(
              children: [
                Text(
                  translate('Controllable devices'),
                  style: TextStyle(
                    color: UuTheme.textPrimary,
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                _AllDevicesPill(onTap: _showAllDevices),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: _searching ? translate('Close search') : translate('Search devices'),
                  onPressed: () => setState(() {
                    _searching = !_searching;
                    if (!_searching) _searchController.clear();
                  }),
                  icon: Icon(
                    _searching ? Icons.close_rounded : Icons.search,
                    size: 21,
                    color: UuTheme.textPrimary,
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: translate('Add device'),
                  onPressed: () => unawaited(_showAddDevice()),
                  icon: Icon(
                    Icons.add_rounded,
                    size: 23,
                    color: UuTheme.textPrimary,
                  ),
                ),
              ],
            ),
            if (_searching)
              Padding(
                padding: const EdgeInsets.only(top: 14),
                child: UuSearchField(
                  controller: _searchController,
                  hint: translate('Search name or ID'),
                  height: 40,
                  onChanged: (_) => setState(() {}),
                ),
              ),
            const SizedBox(height: 18),
            Obx(() {
              final query = _searchController.text.trim().toLowerCase();
              final account = _accountPeers();
              final recent = _recentOnly(account);
              bool matches(Peer peer) =>
                  query.isEmpty ||
                  uuPeerName(peer).toLowerCase().contains(query) ||
                  peer.id.toLowerCase().contains(query);
              if (query.isNotEmpty) {
                final results = <Peer>[...account, ...recent]
                    .where(matches)
                    .toList();
                if (results.isEmpty) {
                  return UuEmptyState(
                    icon: Icons.search_off_rounded,
                    title: translate('No matching devices'),
                    message: translate('Try another name or ID'),
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _searchHeader(translate('Search results: {${results.length}}')),
                    const SizedBox(height: 10),
                    ...results.map((peer) => _deviceCard(peer)),
                  ],
                );
              }
              final online = account.where((p) => p.online).toList();
              final offline = account.where((p) => !p.online).toList();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!gFFI.userModel.isLogin) _loginPrompt(),
                  if (gFFI.userModel.isLogin && account.isEmpty)
                    _accountEmptyOrStatus(),
                  if (online.isNotEmpty) ...[
                    _SectionHeader(
                      title: translate('Online devices: {${online.length}}'),
                      collapsed: _onlineCollapsed,
                      onTap: () => setState(
                          () => _onlineCollapsed = !_onlineCollapsed),
                    ),
                    const SizedBox(height: 10),
                    if (!_onlineCollapsed)
                      ...online.map((peer) => _deviceCard(peer)),
                    const SizedBox(height: 10),
                  ],
                  if (offline.isNotEmpty) ...[
                    _SectionHeader(
                      title: translate('Offline devices: {${offline.length}}'),
                      collapsed: _offlineCollapsed,
                      onTap: () => setState(
                          () => _offlineCollapsed = !_offlineCollapsed),
                    ),
                    const SizedBox(height: 10),
                    if (!_offlineCollapsed)
                      ...offline.map((peer) => _deviceCard(peer)),
                  ],
                  if (recent.isNotEmpty) ...[
                    const SizedBox(height: 18),
                    _searchHeader(translate('Recent connections: {${recent.length}}')),
                    const SizedBox(height: 10),
                    ...recent.map((peer) => _recentRow(peer)),
                  ],
                ],
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _searchHeader(String title) {
    return Text(
      title,
      style: TextStyle(
        color: UuColors.textSecondary,
        fontSize: 15,
        fontWeight: FontWeight.w500,
      ),
    );
  }

  List<Peer> _recentOnly(List<Peer> account) {
    final accountIds = account.map((p) => p.id).toSet();
    final localId = _localId;
    return _connectable(gFFI.recentPeersModel.peers)
        .where((p) =>
            !accountIds.contains(p.id) &&
            (localId.isEmpty || p.id != localId))
        .take(5)
        .toList();
  }

  Widget _recentRow(Peer peer) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      child: UuCard(
        radius: UuRadius.md,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: peer.online ? UuColors.primarySoft : UuColors.hover,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                UuPeerPlatformIcon.iconFor(peer.platform),
                size: 19,
                color: peer.online ? UuColors.primary : UuColors.textTertiary,
              ),
            ),
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
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    peer.platform.isEmpty
                        ? (peer.online ? translate('Online') : translate('Offline'))
                        : '${translate(peer.online ? 'Online' : 'Offline')} · ${peer.platform}',
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
              onPressed: () => unawaited(_connect(peer)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showAddDevice() async {
    final controller = TextEditingController();
    final ok = await showUuDialog<bool>(
      context,
      title: translate('Add device'),
      message: translate("Enter the other device's ID. It will appear in recent connections after connecting."),
      content: UuTextField(
        controller: controller,
        hint: translate('Device ID'),
        autofocus: true,
        keyboardType: TextInputType.number,
      ),
      actions: [
        uuDialogTextButton(translate('Cancel'), () => Navigator.of(context).pop(false)),
        uuDialogFilledButton(
            translate('Connect'), () => Navigator.of(context).pop(true)),
      ],
    );
    final id = controller.text.trim();
    controller.dispose();
    if (ok != true || !mounted) return;
    if (id.isEmpty) {
      uuToast(translate('Please enter a device ID'));
      return;
    }
    await connect(context, id);
  }

  Widget _loginPrompt() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: UuColors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.cloud_outlined,
                  color: UuTheme.accent, size: 22),
              const SizedBox(width: 8),
              Text(
                translate('Sign in to sync account devices'),
                style: TextStyle(
                  color: UuTheme.textPrimary,
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            translate('Sign in to the same account on your phone and computer to see all devices here and connect with one tap.'),
            style: TextStyle(
              color: _muted,
              fontSize: 13,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _openLogin(),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: UuTheme.accent,
                    side: const BorderSide(color: UuTheme.accent),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(translate('Login')),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: () => _openLogin(register: true),
                  style: FilledButton.styleFrom(
                    backgroundColor: UuTheme.accent,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(translate('Register')),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _accountEmptyOrStatus() {
    final error = gFFI.abModel.abPullError.value;
    if (error.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 70, bottom: 40),
        child: Column(
          children: [
            Icon(Icons.cloud_off_outlined,
                size: 56, color: UuColors.textTertiary),
            const SizedBox(height: 14),
            Text(
              translate('Failed to sync account devices'),
              style: TextStyle(
                color: UuTheme.textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                error,
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: _muted, fontSize: 13, height: 1.5),
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: _refresh,
              style: OutlinedButton.styleFrom(
                foregroundColor: UuColors.primary,
                side: const BorderSide(color: UuColors.primary),
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(translate('Try again')),
            ),
          ],
        ),
      );
    }
    if (gFFI.abModel.currentAbLoading.value) {
      return Padding(
        padding: EdgeInsets.only(top: 70, bottom: 40),
        child: Center(
          child: Column(
            children: [
              SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: UuColors.primary,
                ),
              ),
              SizedBox(height: 14),
              Text(
                translate('Syncing account devices...'),
                style: TextStyle(color: UuColors.textSecondary, fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }
    return _emptyDevices();
  }

  Widget _emptyDevices() {
    return Padding(
      padding: const EdgeInsets.only(top: 70, bottom: 40),
      child: Column(
        children: [
          Icon(Icons.devices_other, size: 56, color: UuColors.textTertiary),
          SizedBox(height: 14),
          Text(
            translate('No other devices'),
            style: TextStyle(
              color: UuTheme.textPrimary,
              fontSize: 17,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: 8),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              translate('Sign in on another device with the same account to see it here'),
              textAlign: TextAlign.center,
              style: TextStyle(color: _muted, fontSize: 13, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _deviceCard(Peer peer) {
    return Container(
      height: 88,
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: UuColors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _openDetail(peer),
          child: Row(
            children: [
              SizedBox(
                width: 96,
                height: 88,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: _thumbnailColors(peer.platform),
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                      child: Center(
                        child: Icon(
                          UuPeerPlatformIcon.iconFor(peer.platform),
                          size: 34,
                          color: Colors.white.withOpacity(0.9),
                        ),
                      ),
                    ),
                    UuWallpaperLayer(
                      peerId: peer.id,
                      fallback: const SizedBox.shrink(),
                    ),
                    Positioned(
                      left: 8,
                      top: 8,
                      child: _OnlineBadge(online: peer.online),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      uuPeerName(peer),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: UuColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '${translate(peer.online ? 'Online' : 'Offline')} · ID ${peer.id}',
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
              TextButton(
                onPressed: () => unawaited(_connect(peer)),
                style: TextButton.styleFrom(
                  backgroundColor:
                      peer.online ? UuColors.primary : UuColors.hover,
                  foregroundColor:
                      peer.online ? Colors.white : UuColors.textSecondary,
                  minimumSize: const Size(58, 34),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(UuRadius.pill),
                  ),
                ),
                child: Text(translate('Connect'), style: TextStyle(fontSize: 13)),
              ),
              SizedBox(
                width: 40,
                height: 44,
                child: Center(
                  child: UuMenuButton<String>(
                    width: 184,
                    icon: Icons.more_horiz,
                    iconSize: 20,
                    iconButtonSize: 40,
                    onSelected: (value) {
                      switch (value) {
                        case 'detail':
                          _openDetail(peer);
                          break;
                        case 'file-transfer':
                          unawaited(_connectFileTransfer(peer));
                          break;
                        case 'copy-id':
                          Clipboard.setData(ClipboardData(text: peer.id));
                          uuToast(translate('ID copied'));
                          break;
                      }
                    },
                    entriesBuilder: (context) => [
                      UuMenuItem(
                        value: 'detail',
                        label: translate('Details'),
                        icon: Icons.info_outline,
                      ),
                      UuMenuItem(
                        value: 'file-transfer',
                        label: translate('File transfer'),
                        icon: Icons.swap_horiz,
                      ),
                      UuMenuItem(
                        value: 'copy-id',
                        label: translate('Copy ID'),
                        icon: Icons.copy_outlined,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 4),
            ],
          ),
        ),
      ),
    );
  }

  void _showAllDevices() {
    final peers = _accountPeers();
    _showSheet(
      title: translate('All devices'),
      child: peers.isEmpty
          ? UuEmptyState(
              icon: Icons.devices_other,
              title: translate('No account devices'),
              message: translate('Sign in and sync your account to see them here'),
            )
          : LayoutBuilder(
              builder: (context, constraints) {
                const spacing = 12.0;
                final cardWidth =
                    (constraints.maxWidth - 32 - spacing) / 2;
                final online = peers.where((p) => p.online).toList();
                final offline = peers.where((p) => !p.online).toList();
                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  children: [
                    if (online.isNotEmpty) ...[
                      _sheetGroupTitle(translate('Online devices: {${online.length}}')),
                      Wrap(
                        spacing: spacing,
                        runSpacing: spacing,
                        children: [
                          for (final peer in online)
                            SizedBox(
                              width: cardWidth,
                              child: _sheetDeviceCard(peer),
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),
                    ],
                    if (offline.isNotEmpty) ...[
                      _sheetGroupTitle(translate('Offline devices: {${offline.length}}')),
                      Wrap(
                        spacing: spacing,
                        runSpacing: spacing,
                        children: [
                          for (final peer in offline)
                            SizedBox(
                              width: cardWidth,
                              child: _sheetDeviceCard(peer),
                            ),
                        ],
                      ),
                    ],
                  ],
                );
              },
            ),
    );
  }

  Widget _sheetGroupTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        title,
        style: TextStyle(
          color: UuColors.textSecondary,
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _sheetDeviceCard(Peer peer) {
    return Material(
      color: UuColors.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          Navigator.of(context).pop();
          _openDetail(peer);
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: peer.online
                          ? UuColors.primarySoft
                          : UuColors.hover,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      UuPeerPlatformIcon.iconFor(peer.platform),
                      color: peer.online
                          ? UuColors.primary
                          : UuColors.textTertiary,
                      size: 20,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: peer.online
                          ? UuColors.success
                          : UuColors.textTertiary,
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
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
                peer.online ? translate('Online · {${peer.id}}') : translate('Offline · {${peer.id}}'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: peer.online ? UuColors.success : _muted,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sheetDeviceRow(Peer peer) {
    return Material(
      color: UuColors.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          Navigator.of(context).pop();
          _openDetail(peer);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: UuTheme.accentSoft,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  UuPeerPlatformIcon.iconFor(peer.platform),
                  color: UuTheme.accent,
                  size: 22,
                ),
              ),
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
                        color: UuTheme.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      peer.online ? translate('Online · {${peer.id}}') : translate('Offline · {${peer.id}}'),
                      style: TextStyle(
                        color: peer.online ? UuColors.success : _muted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right,
                  color: UuColors.textTertiary, size: 22),
            ],
          ),
        ),
      ),
    );
  }

  void _showSheet({required String title, required Widget child}) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return Container(
          height: MediaQuery.of(sheetContext).size.height * 0.72,
          decoration: BoxDecoration(
            color: _bg,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              children: [
                Container(
                  margin: const EdgeInsets.only(top: 10),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: UuColors.divider,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 8, 8),
                  child: Row(
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: UuTheme.textPrimary,
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: () => Navigator.of(sheetContext).pop(),
                        icon: Icon(Icons.close,
                            color: UuTheme.textSecondary),
                      ),
                    ],
                  ),
                ),
                Expanded(child: child),
              ],
            ),
          ),
        );
      },
    );
  }

  // ---------------------------------- 协助 ----------------------------------

  Widget _buildAssistTab() {
    final canConnect = _assistId.text.replaceAll(' ', '').isNotEmpty;
    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          Text(
            translate('Remote assistance'),
            style: TextStyle(
              color: UuTheme.textPrimary,
              fontSize: 28,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 22),
          Container(
            padding: const EdgeInsets.fromLTRB(18, 20, 18, 20),
            decoration: BoxDecoration(
              color: UuColors.surface,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  translate('Remote partner device'),
                  style: TextStyle(
                    color: UuTheme.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  translate("Start remote control with another device's ID and verification code"),
                  style: TextStyle(
                    color: _muted,
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Text(
                      translate('Partner device ID'),
                      style: TextStyle(
                        color: UuTheme.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: _showRecent,
                      style: TextButton.styleFrom(
                        foregroundColor: UuTheme.accent,
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      icon: const Icon(Icons.history, size: 18),
                      label: Text(
                        translate('Recent connections'),
                        style: TextStyle(fontSize: 15),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _assistId,
                  keyboardType: TextInputType.visiblePassword,
                  autocorrect: false,
                  enableSuggestions: false,
                  inputFormatters: [IDTextInputFormatter()],
                  onSubmitted: (_) => _startAssist(),
                  style: TextStyle(
                    color: UuTheme.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                  decoration: InputDecoration(
                    hintText: translate('Please enter a device ID'),
                    hintStyle: const TextStyle(
                      color: Color(0xFF9AA0AA),
                      fontSize: 16,
                      fontWeight: FontWeight.normal,
                    ),
                    filled: true,
                    fillColor: UuColors.background,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 16),
                  ),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  height: 52,
                  child: FilledButton(
                    onPressed: canConnect ? _startAssist : null,
                    style: FilledButton.styleFrom(
                      backgroundColor: UuTheme.accent,
                      disabledBackgroundColor:
                          UuTheme.accent.withOpacity(0.38),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      translate('Start remote control'),
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _startAssist() async {
    final id = _assistId.text.replaceAll(' ', '').trim();
    if (id.isEmpty) return;
    FocusScope.of(context).unfocus();
    await connect(context, id);
  }

  void _showRecent() {
    final peers = _connectable(gFFI.recentPeersModel.peers);
    _showSheet(
      title: translate('Recent connections'),
      child: peers.isEmpty
          ? UuEmptyState(
              icon: Icons.history_rounded,
              title: translate('No recent connections'),
              message: translate('Devices you have connected to will appear here'),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              itemCount: peers.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final peer = peers[index];
                return _sheetDeviceRow(peer);
              },
            ),
    );
  }

  // ---------------------------------- 我的 ----------------------------------

  Widget _buildMeTab() {
    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          Row(
            children: [
              Expanded(
                child: Obx(() {
                  final loggedIn = gFFI.userModel.isLogin;
                  final name = loggedIn
                      ? _maskName(gFFI.userModel.displayNameOrUserName)
                      : translate('Login / Register');
                  return InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: _openAccount,
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 33,
                          backgroundColor: UuColors.primary,
                          child: const Icon(Icons.person,
                              color: Colors.white, size: 42),
                        ),
                        const SizedBox(width: 14),
                        Flexible(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: UuTheme.textPrimary,
                                  fontSize: 26,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    loggedIn ? translate('My account') : translate('Sign in to sync account devices'),
                                    style: TextStyle(
                                      color: _muted,
                                      fontSize: 15,
                                    ),
                                  ),
                                  Icon(Icons.chevron_right,
                                      size: 17, color: _muted),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ),
              ScanButton(),
            ],
          ),
          const SizedBox(height: 26),
          Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: UuColors.surface,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                _menuRow(Icons.download_outlined, translate('Received files'),
                    () => _pushSimplePage(translate('Received files'), Icons.download_outlined,
                        translate('No received files'))),
                _menuDivider(),
                _menuRow(Icons.mail_outline, translate('Messages'),
                    () => _pushSimplePage(translate('Messages'), Icons.mail_outline, translate('No messages'))),
                _menuDivider(),
                _menuRow(Icons.help_outline, translate('Help and feedback'), _openHelp),
                _menuDivider(),
                _menuRow(Icons.headset_mic_outlined, translate('Online support'), _openSupport),
                _menuDivider(),
                _menuRow(Icons.settings_outlined, translate('Settings'), _openSettings),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _menuRow(IconData icon, String label, VoidCallback onTap) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
          child: Row(
            children: [
              Icon(icon, size: 23, color: UuTheme.textPrimary),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: UuTheme.textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Icon(Icons.chevron_right,
                  size: 22, color: UuColors.textTertiary),
            ],
          ),
        ),
      ),
    );
  }

  Widget _menuDivider() {
    return Divider(
      height: 0.5,
      thickness: 0.5,
      indent: 55,
      endIndent: 16,
      color: _hairline,
    );
  }

  void _pushSimplePage(String title, IconData icon, String message) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _UuSimplePage(
          title: title,
          icon: icon,
          message: message,
        ),
      ),
    );
  }

  void _openHelp() {
    unawaited(launchUrlString('https://rustdesk.com/docs/'));
  }

  void _openSupport() {
    showUuDialog<void>(
      context,
      title: translate('Online support'),
      message: translate('Online support is not available yet. See Help and feedback for documentation.'),
      actions: [
        uuDialogFilledButton(translate('Got it'), () => Navigator.of(context).pop()),
      ],
    );
  }

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const UuSettingsPage()),
    );
  }

  void _openAccount() {
    if (!gFFI.userModel.isLogin) {
      unawaited(_openLogin());
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: UuColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        UuColors.apply(sheetContext);
        final displayName = gFFI.userModel.displayNameOrUserName;
        final userName = gFFI.userModel.userName.value;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircleAvatar(
                  radius: 30,
                  backgroundColor: UuColors.primary,
                  child: Icon(Icons.person, color: Colors.white, size: 38),
                ),
                const SizedBox(height: 12),
                Text(
                  displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: UuTheme.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '@$userName',
                  style: TextStyle(color: _muted, fontSize: 13),
                ),
                const SizedBox(height: 18),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.sync, color: UuTheme.accent),
                  title: Text(translate('Refresh devices')),
                  onTap: () async {
                    Navigator.of(sheetContext).pop();
                    await uuRefreshDevices();
                    _queryOnlineStatuses();
                    if (mounted) setState(() {});
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.logout, color: UuColors.danger),
                  title: Text(
                    translate('Sign out'),
                    style: TextStyle(color: UuColors.danger),
                  ),
                  onTap: () async {
                    Navigator.of(sheetContext).pop();
                    if (!await uuConfirmLogout(context)) {
                      return;
                    }
                    await gFFI.userModel.logOut();
                    if (mounted) setState(() {});
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ------------------------------- 小组件 -------------------------------

class _AllDevicesPill extends StatelessWidget {
  const _AllDevicesPill({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: UuColors.hover,
      borderRadius: BorderRadius.circular(99),
      child: InkWell(
        borderRadius: BorderRadius.circular(99),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.grid_view,
                  size: 17, color: UuTheme.textPrimary),
              SizedBox(width: 6),
              Text(
                translate('All devices'),
                style: TextStyle(
                  color: UuTheme.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.collapsed,
    required this.onTap,
  });

  final String title;
  final bool collapsed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: TextStyle(
                color: UuColors.textSecondary,
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              collapsed ? Icons.expand_more : Icons.expand_less,
              size: 19,
              color: UuColors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}

class _OnlineBadge extends StatelessWidget {
  const _OnlineBadge({required this.online});

  final bool online;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.55),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: online ? UuColors.success : UuColors.textTertiary,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            online ? translate('Online') : translate('Offline'),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}


class _UuSimplePage extends StatelessWidget {
  const _UuSimplePage({
    required this.title,
    required this.icon,
    required this.message,
  });

  final String title;
  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    UuColors.apply(context);
    return Scaffold(
      backgroundColor: UuColors.background,
      appBar: AppBar(
        backgroundColor: UuColors.surface,
        foregroundColor: UuTheme.textPrimary,
        elevation: 0,
        centerTitle: true,
        title: Text(title),
      ),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 52, color: UuColors.textTertiary),
            const SizedBox(height: 14),
            Text(
              message,
              style: TextStyle(
                color: UuColors.textSecondary,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
