import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/common/formatter/id_formatter.dart';
import 'package:flutter_hbb/mobile/pages/settings_page.dart';
import 'package:flutter_hbb/models/ab_model.dart';
import 'package:flutter_hbb/models/peer_model.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/models/user_model.dart';
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher_string.dart';

import '../theme.dart';
import '../uu_auth.dart';
import '../uu_peer.dart';
import '../uu_wallpaper.dart';
import 'uu_device_detail_page.dart';
import 'uu_mobile_login_page.dart';

/// UU 远程风格的 iOS 首页：我的设备 / 远程协助 / 我的。
class UuMobileHome extends StatefulWidget {
  const UuMobileHome({super.key});

  @override
  State<UuMobileHome> createState() => _UuMobileHomeState();
}

class _UuMobileHomeState extends State<UuMobileHome> {
  static const _bg = Color(0xFFF2F3F7);
  static const _muted = Color(0xFF8A8F99);
  static const _hairline = Color(0xFFEDEFF3);

  int _tab = 0;
  Timer? _onlineTimer;
  Timer? _abTimer;
  bool _onlineCollapsed = false;
  bool _offlineCollapsed = false;
  final Map<Peers, VoidCallback> _peersListeners = {};
  final _assistId = TextEditingController();

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
      await UserModel.updateOtherModels();
      _queryOnlineStatuses();
      if (mounted) setState(() {});
    }
  }

  Future<void> _connect(Peer peer) async {
    await connect(context, peer.id, password: uuPeerPassword(peer));
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

  IconData _brandIcon(String platform) {
    final p = platform.toLowerCase();
    if (p.contains('mac') ||
        p.contains('ios') ||
        p.contains('iphone') ||
        p.contains('ipad')) {
      return Icons.apple;
    }
    if (p.contains('win')) return Icons.desktop_windows;
    if (p.contains('android')) return Icons.android;
    if (p.contains('linux')) return Icons.computer;
    return Icons.devices;
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
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: _hairline, width: 0.5)),
        ),
        child: SafeArea(
          top: false,
          child: BottomNavigationBar(
            currentIndex: _tab,
            onTap: (index) => setState(() => _tab = index),
            type: BottomNavigationBarType.fixed,
            backgroundColor: Colors.white,
            elevation: 0,
            selectedItemColor: UuTheme.accent,
            unselectedItemColor: _muted,
            selectedFontSize: 12,
            unselectedFontSize: 12,
            items: const [
              BottomNavigationBarItem(
                icon: Icon(Icons.devices_outlined),
                activeIcon: Icon(Icons.devices),
                label: '我的设备',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.screen_share_outlined),
                activeIcon: Icon(Icons.screen_share),
                label: '远程协助',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.person_outline),
                activeIcon: Icon(Icons.person),
                label: '我的',
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
                const Text(
                  '可控设备',
                  style: TextStyle(
                    color: UuTheme.textPrimary,
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                _AllDevicesPill(onTap: _showAllDevices),
              ],
            ),
            const SizedBox(height: 22),
            Obx(() {
              if (!gFFI.userModel.isLogin) {
                return _loginPrompt();
              }
              final peers = _accountPeers();
              if (peers.isEmpty) {
                return _emptyDevices();
              }
              final online = peers.where((p) => p.online).toList();
              final offline = peers.where((p) => !p.online).toList();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (online.isNotEmpty) ...[
                    _SectionHeader(
                      title: '在线设备 ${online.length}',
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
                      title: '离线设备 ${offline.length}',
                      collapsed: _offlineCollapsed,
                      onTap: () => setState(
                          () => _offlineCollapsed = !_offlineCollapsed),
                    ),
                    const SizedBox(height: 10),
                    if (!_offlineCollapsed)
                      ...offline.map((peer) => _deviceCard(peer)),
                  ],
                ],
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _loginPrompt() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
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
              const Text(
                '登录后同步账号设备',
                style: TextStyle(
                  color: UuTheme.textPrimary,
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            '在手机和电脑上登录同一账号，即可在这里看到全部设备并一键远控。',
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
                  child: const Text('登录'),
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
                  child: const Text('注册'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _emptyDevices() {
    return Padding(
      padding: const EdgeInsets.only(top: 70, bottom: 40),
      child: Column(
        children: const [
          Icon(Icons.devices_other, size: 56, color: Color(0xFFC7CBD3)),
          SizedBox(height: 14),
          Text(
            '暂无其他设备',
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
              '在另一台设备登录同一账号后，就会出现在这里',
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
      height: 96,
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _openDetail(peer),
          onLongPress: () => unawaited(_connect(peer)),
          child: Row(
            children: [
              SizedBox(
                width: 112,
                height: 96,
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
                          _brandIcon(peer.platform),
                          size: 38,
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
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      uuPeerName(peer),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: UuTheme.textPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Icon(
                      _brandIcon(peer.platform),
                      size: 18,
                      color: UuTheme.accent,
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right,
                  color: Color(0xFFC7CBD3), size: 24),
              const SizedBox(width: 10),
            ],
          ),
        ),
      ),
    );
  }

  void _showAllDevices() {
    final peers = _accountPeers();
    _showSheet(
      title: '全部设备',
      child: peers.isEmpty
          ? const _SheetEmpty(
              icon: Icons.devices_other,
              message: '暂无账号设备',
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

  Widget _sheetDeviceRow(Peer peer) {
    return Material(
      color: Colors.white,
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
                  _brandIcon(peer.platform),
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
                      style: const TextStyle(
                        color: UuTheme.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      peer.online ? '在线 · ${peer.id}' : '离线 · ${peer.id}',
                      style: TextStyle(
                        color: peer.online
                            ? const Color(0xFF16A34A)
                            : _muted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right,
                  color: Color(0xFFC7CBD3), size: 22),
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
          decoration: const BoxDecoration(
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
                    color: const Color(0xFFD5D8DE),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 8, 8),
                  child: Row(
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: UuTheme.textPrimary,
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: () => Navigator.of(sheetContext).pop(),
                        icon: const Icon(Icons.close,
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
          const Text(
            '远程协助',
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
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  '远控伙伴设备',
                  style: TextStyle(
                    color: UuTheme.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  '通过其他设备的【设备 ID】及【设备验证码】启动远程控制',
                  style: TextStyle(
                    color: _muted,
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    const Text(
                      '伙伴的设备 ID',
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
                      label: const Text(
                        '最近连接',
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
                  style: const TextStyle(
                    color: UuTheme.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                  decoration: InputDecoration(
                    hintText: '请输入设备 ID',
                    hintStyle: const TextStyle(
                      color: Color(0xFF9AA0AA),
                      fontSize: 16,
                      fontWeight: FontWeight.normal,
                    ),
                    filled: true,
                    fillColor: const Color(0xFFF3F4F7),
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
                    child: const Text(
                      '开始远控',
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
      title: '最近连接',
      child: peers.isEmpty
          ? const _SheetEmpty(
              icon: Icons.history,
              message: '暂无最近连接',
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
                      : '登录 / 注册';
                  return InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: _openAccount,
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 33,
                          backgroundColor: const Color(0xFF3B82F6),
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
                                style: const TextStyle(
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
                                    loggedIn ? '我的账号' : '登录后同步账号设备',
                                    style: const TextStyle(
                                      color: _muted,
                                      fontSize: 15,
                                    ),
                                  ),
                                  const Icon(Icons.chevron_right,
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
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                _menuRow(Icons.download_outlined, '已接收文件',
                    () => _pushSimplePage('已接收文件', Icons.download_outlined,
                        '暂无已接收的文件')),
                _menuDivider(),
                _menuRow(Icons.mail_outline, '消息中心',
                    () => _pushSimplePage('消息中心', Icons.mail_outline, '暂无消息')),
                _menuDivider(),
                _menuRow(Icons.help_outline, '帮助与反馈', _openHelp),
                _menuDivider(),
                _menuRow(Icons.headset_mic_outlined, '在线客服', _openSupport),
                _menuDivider(),
                _menuRow(Icons.settings_outlined, '设置', _openSettings),
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
                  style: const TextStyle(
                    color: UuTheme.textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const Icon(Icons.chevron_right,
                  size: 22, color: Color(0xFFC7CBD3)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _menuDivider() {
    return const Divider(
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
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('在线客服'),
        content: const Text('在线客服暂未接入，可通过“帮助与反馈”查看文档。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: _bg,
          appBar: AppBar(
            backgroundColor: Colors.white,
            foregroundColor: UuTheme.textPrimary,
            elevation: 0,
            centerTitle: true,
            title: const Text('设置'),
          ),
          body: SettingsPage(),
        ),
      ),
    );
  }

  void _openAccount() {
    if (!gFFI.userModel.isLogin) {
      unawaited(_openLogin());
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
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
                  backgroundColor: Color(0xFF3B82F6),
                  child: Icon(Icons.person, color: Colors.white, size: 38),
                ),
                const SizedBox(height: 12),
                Text(
                  displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: UuTheme.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '@$userName',
                  style: const TextStyle(color: _muted, fontSize: 13),
                ),
                const SizedBox(height: 18),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.sync, color: UuTheme.accent),
                  title: const Text('刷新设备'),
                  onTap: () async {
                    Navigator.of(sheetContext).pop();
                    await UserModel.updateOtherModels();
                    _queryOnlineStatuses();
                    if (mounted) setState(() {});
                    showToast('设备已刷新');
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.logout, color: Color(0xFFE5484D)),
                  title: const Text(
                    '退出登录',
                    style: TextStyle(color: Color(0xFFE5484D)),
                  ),
                  onTap: () async {
                    Navigator.of(sheetContext).pop();
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
      color: const Color(0xFFEDEFF3),
      borderRadius: BorderRadius.circular(99),
      child: InkWell(
        borderRadius: BorderRadius.circular(99),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(Icons.monitor_outlined,
                  size: 17, color: UuTheme.textPrimary),
              SizedBox(width: 6),
              Text(
                '全部设备',
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
              style: const TextStyle(
                color: Color(0xFF6B7280),
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              collapsed ? Icons.expand_more : Icons.expand_less,
              size: 19,
              color: const Color(0xFF6B7280),
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
              color: online ? const Color(0xFF22C55E) : const Color(0xFF9CA3AF),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            online ? '在线' : '离线',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _SheetEmpty extends StatelessWidget {
  const _SheetEmpty({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: const Color(0xFFC7CBD3)),
          const SizedBox(height: 12),
          Text(
            message,
            style: const TextStyle(
              color: Color(0xFF8A8F99),
              fontSize: 14,
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
    return Scaffold(
      backgroundColor: const Color(0xFFF2F3F7),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: UuTheme.textPrimary,
        elevation: 0,
        centerTitle: true,
        title: Text(title),
      ),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 52, color: const Color(0xFFC7CBD3)),
            const SizedBox(height: 14),
            Text(
              message,
              style: const TextStyle(
                color: Color(0xFF8A8F99),
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
