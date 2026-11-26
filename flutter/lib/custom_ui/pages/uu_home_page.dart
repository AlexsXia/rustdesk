// Chinese-first strings for the private UU-style build; move them into
// src/lang once the layout is settled.
import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/common/widgets/peer_card.dart';
import 'package:flutter_hbb/desktop/pages/desktop_setting_page.dart';
import 'package:flutter_hbb/models/ab_model.dart';
import 'package:flutter_hbb/models/peer_model.dart';
import 'package:flutter_hbb/models/peer_tab_model.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:window_manager/window_manager.dart';

import '../theme.dart';
import '../uu_auth.dart';
import '../uu_login_dialog.dart';
import '../uu_peer.dart';
import '../uu_settings_dialog.dart';
import '../uu_wallpaper.dart';

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
  final _assistGearKey = GlobalKey();
  bool _allowAssist = true;
  bool _showAssistPassword = false;
  String _autoRefresh = '每次远控结束';
  Timer? _assistRefreshTimer;

  @override
  void initState() {
    super.initState();
    _heroImage = bind.mainGetLocalOption(key: 'custom-hero-image');
    bind.mainLoadRecentPeers();
    unawaited(uuSyncDeviceSecret());
    _initOnlineTracking();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await windowManager.setTitleBarStyle(TitleBarStyle.hidden);
        await windowManager.setMinimumSize(const Size(760, 560));
        await windowManager.setSize(const Size(920, 680));
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
    super.dispose();
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
      'alias': '演示设备',
      'hostname': 'Demo PC',
      'platform': 'Windows',
      'username': 'demo',
    });
    peer.online = true;
    peer.sameServer = true;
    return peer;
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
      showToast('演示设备仅用于界面预览，请添加真实设备');
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
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(translate('Connect')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: idController,
                autofocus: true,
                decoration: InputDecoration(labelText: translate('ID')),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: passwordController,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: translate('Password'),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(translate('Cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(translate('Connect')),
            ),
          ],
        );
      },
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
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(bind.mainGetAppNameSync()),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                translate('ID'),
                style: const TextStyle(
                  color: UuTheme.textSecondary,
                  fontSize: 11,
                ),
              ),
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
                style: const TextStyle(
                  color: UuTheme.textSecondary,
                  fontSize: 11,
                ),
              ),
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: gFFI.serverModel.serverPasswd,
                builder: (context, value, child) {
                  return SelectableText(
                    value.text,
                    style: const TextStyle(fontSize: 13),
                  );
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: _copyId,
              child: Text(translate('Copied')),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(translate('Cancel')),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showNotifications() async {
    final needs = _needsPermissions;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('通知'),
          content: Text(
            needs ? '有权限未授予，远程访问可能无法操作。' : '暂无通知。',
          ),
          actions: [
            if (needs)
              TextButton(
                onPressed: () {
                  Navigator.pop(dialogContext);
                  _requestPermissions();
                },
                child: const Text('配置'),
              ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('关闭'),
            ),
          ],
        );
      },
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
    showToast('已复制');
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

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final sidebarWidth =
            (constraints.maxWidth * 0.243).clamp(240.0, 400.0).toDouble();
        return Container(
          color: Colors.white,
          child: Row(
            children: [
              SizedBox(width: sidebarWidth, child: _buildSidebar(context)),
              const VerticalDivider(width: 1, color: UuTheme.divider),
              Expanded(child: _buildMain(context)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSidebar(BuildContext context) {
    return Container(
      color: const Color(0xFFF8F8F8),
      child: AnimatedBuilder(
        animation: Listenable.merge([
          gFFI.recentPeersModel,
          gFFI.favoritePeersModel,
        ]),
        builder: (context, child) {
          return Obx(() {
            final all = _allPeers();
            final selected = _selectedPeer(all);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 52),
                _sectionHeader('我的设备', Icons.devices_other),
                if (all.isEmpty)
                  _sideHint('暂无设备，点击右上角 + 添加')
                else
                  for (final peer in all) _deviceRow(peer, selected),
                _allDevicesRow(),
                const SizedBox(height: 12),
                _sectionHeader('远程协助', Icons.support_agent),
                _assistRow(
                  Icons.add_to_queue,
                  '开始协助',
                  () => setState(() => _page = _HomePage.assist),
                  selected: _page == _HomePage.assist,
                ),
                _assistRow(
                  Icons.star,
                  '收藏设备',
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

  Widget _sectionHeader(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 14, 6),
      child: Row(
        children: [
          Icon(icon, size: 20, color: UuTheme.textSecondary),
          const SizedBox(width: 6),
          Text(
            title,
            style: const TextStyle(
              color: UuTheme.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          const Icon(
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
        style: const TextStyle(color: UuTheme.textSecondary, fontSize: 11),
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
                ? const Color(0xFFDFDFDF)
                : isHovered
                    ? const Color(0xFFECECEC)
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
                  color: const Color(0xFFE8F0FF),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: const Icon(
                  Icons.grid_view,
                  size: 15,
                  color: UuTheme.accent,
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  uuPeerName(peer),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: UuTheme.textPrimary,
                    fontSize: 13,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
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
                ? const Color(0xFFDFDFDF)
                : isHovered
                    ? const Color(0xFFECECEC)
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
                  color: const Color(0xFFE8F0FF),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: const Icon(
                  Icons.grid_view,
                  size: 15,
                  color: UuTheme.accent,
                ),
              ),
              const SizedBox(width: 9),
              const Text(
                '全部设备',
                style: TextStyle(
                  color: UuTheme.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
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
                ? const Color(0xFFDFDFDF)
                : isHovered
                    ? const Color(0xFFECECEC)
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
                style: const TextStyle(
                  color: UuTheme.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
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
            _HomePage.allDevices => '全部设备',
            _HomePage.assist => '远程协助',
            _HomePage.favorites => '收藏设备',
            _HomePage.home => null,
          };
          return Column(
            children: [
              _buildTopBar(context, selected, pageTitle: pageTitle),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(38, 28, 38, 28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildDaemonBanner(),
                      _buildPageContent(context, selected),
                    ],
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
        color: const Color(0xFFFFF7E6),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFFE0A3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.dns_outlined, color: Color(0xFFD97706), size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  needInstall ? '安装被控服务' : '被控服务已停止',
                  style: const TextStyle(
                    color: UuTheme.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  needInstall
                      ? '安装后这台 Mac 才能接收手机等设备的远程连接'
                      : '启动服务后才能接收远程连接',
                  style: const TextStyle(
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
              backgroundColor: const Color(0xFFD97706),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: Text(needInstall ? '安装' : '启动'),
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
        const Padding(
          padding: EdgeInsets.only(left: 2, bottom: 8),
          child: Text(
            '快速启动',
            style: TextStyle(
              color: UuTheme.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        _buildAddCard(context),
      ],
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _groupHeader('电脑 ${desktops.length + 1}'),
        _localDeviceRow(),
        for (final peer in desktops) _allDeviceRow(peer),
        const SizedBox(height: 22),
        _groupHeader('手机/平板 ${mobiles.length}'),
        for (final peer in mobiles) _allDeviceRow(peer),
      ],
    );
  }

  Widget _groupHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          const Icon(
            Icons.keyboard_arrow_down,
            size: 22,
            color: UuTheme.textSecondary,
          ),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(
              color: UuTheme.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _localDeviceRow() {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: UuTheme.divider),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: _showLocalInfo,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              _allDeviceIcon(Icons.laptop_mac),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  Platform.localHostname,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: UuTheme.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF0FF),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  '本机',
                  style: TextStyle(color: UuTheme.accent, fontSize: 11),
                ),
              ),
              const SizedBox(width: 8),
              const Icon(
                Icons.info_outline,
                size: 20,
                color: UuTheme.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _allDeviceRow(Peer peer) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: UuTheme.divider),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => setState(() {
          _page = _HomePage.home;
          _selectedId = peer.id;
        }),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              _allDeviceIcon(Icons.grid_view),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  uuPeerName(peer),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: UuTheme.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _showPeerInfo(peer),
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(
                    Icons.info_outline,
                    size: 20,
                    color: UuTheme.textSecondary,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              const Icon(
                Icons.keyboard_arrow_right,
                size: 22,
                color: UuTheme.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _allDeviceIcon(IconData icon) {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: const Color(0xFF2F6BFF),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, color: Colors.white, size: 24),
    );
  }

  void _showPeerInfo(Peer peer) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(uuPeerName(peer)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('ID: ${peer.id}'),
              Text('平台: ${peer.platform}'),
              Text('在线: ${peer.online ? "是" : "否"}'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('关闭'),
            ),
          ],
        );
      },
    );
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
                  const Text(
                    '本设备',
                    style: TextStyle(
                      color: UuTheme.textPrimary,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  const Text(
                    '允许他人远程协助',
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
              const Divider(height: 30, color: Color(0xFFE5E7EB)),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '本设备 ID',
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
                              style: const TextStyle(
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
                        Row(
                          children: [
                            const Text(
                              '验证方式：',
                              style: TextStyle(
                                color: UuTheme.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                            const Text(
                              '同时使用两种验证码',
                              style: TextStyle(
                                color: UuTheme.textPrimary,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const Icon(
                              Icons.unfold_more,
                              size: 16,
                              color: UuTheme.textSecondary,
                            ),
                          ],
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
                                  style: const TextStyle(
                                    color: UuTheme.textPrimary,
                                    fontSize: 22,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 1.5,
                                  ),
                                );
                              },
                            ),
                            const SizedBox(width: 8),
                            _assistIcon(
                              Icons.visibility_outlined,
                              () => setState(() => _showAssistPassword =
                                  !_showAssistPassword),
                            ),
                            GestureDetector(
                              key: _assistGearKey,
                              onTap: _showAssistGearMenu,
                              child: const Padding(
                                padding: EdgeInsets.all(8),
                                child: Icon(
                                  Icons.settings_outlined,
                                  size: 20,
                                  color: UuTheme.textSecondary,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            FilledButton(
                              onPressed: _copyAssist,
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFFF2F3F5),
                                foregroundColor: UuTheme.textPrimary,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 10),
                              ),
                              child: const Text('复制并分享'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          '每次远控结束刷新',
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
              const Text(
                '远控伙伴设备',
                style: TextStyle(
                  color: UuTheme.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                '通过其他设备的【设备 ID】及【设备验证码】启动远程控制',
                style: TextStyle(
                  color: UuTheme.textSecondary,
                  fontSize: 13,
                ),
              ),
              const Divider(height: 30, color: Color(0xFFE5E7EB)),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _assistIdController,
                      decoration: InputDecoration(
                        hintText: '请输入设备 ID',
                        filled: true,
                        fillColor: Colors.white,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(
                              color: Color(0xFFE5E7EB)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(
                              color: Color(0xFFE5E7EB)),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 18),
                  SizedBox(
                    width: 100,
                    height: 44,
                    child: FilledButton(
                      onPressed: _connectAssist,
                      child: const Text('连接'),
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
        color: const Color(0xFFF7F7F7),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: child,
    );
  }

  Widget _assistIcon(IconData icon, VoidCallback onTap) {
    return IconButton(
      onPressed: onTap,
      icon: Icon(icon, size: 20, color: UuTheme.textSecondary),
      visualDensity: VisualDensity.compact,
    );
  }

  Future<void> _showSettingsDialog() async {
    await showUuSettingsDialog(context);
  }

  Future<void> _showAboutDialog() async {
    final version = await bind.mainGetVersion();
    if (!mounted) {
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(bind.mainGetAppNameSync()),
          content: Text('版本 $version'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('关闭'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showAssistGearMenu() async {
    final box =
        _assistGearKey.currentContext?.findRenderObject() as RenderBox?;
    final offset =
        box?.localToGlobal(Offset.zero) ?? const Offset(200, 200);
    final value = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(offset.dx, offset.dy + 36, 0, 0),
      items: const [
        PopupMenuItem(
          value: 'now',
          child: Row(
            children: [
              Icon(Icons.refresh, size: 18),
              SizedBox(width: 10),
              Text('立即刷新'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'auto',
          child: Row(
            children: [
              Icon(Icons.autorenew, size: 18),
              SizedBox(width: 10),
              Text('自动刷新'),
              Spacer(),
              Icon(Icons.chevron_right, size: 18),
            ],
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
      final interval = await showMenu<String>(
        context: context,
        position: RelativeRect.fromLTRB(
          offset.dx + 150,
          offset.dy + 74,
          0,
          0,
        ),
        items: [
          for (final option in const [
            '每次远控结束',
            '每小时',
            '每 12 小时',
            '每 24 小时',
            '关闭',
          ])
            PopupMenuItem(
              value: option,
              child: Row(
                children: [
                  SizedBox(
                    width: 24,
                    child: _autoRefresh == option
                        ? const Icon(Icons.check, size: 18)
                        : null,
                  ),
                  Text(option),
                ],
              ),
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
      case '每小时':
        duration = const Duration(hours: 1);
        break;
      case '每 12 小时':
        duration = const Duration(hours: 12);
        break;
      case '每 24 小时':
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
    showToast('已复制');
  }

  Future<void> _connectAssist() async {
    final id = _assistIdController.text.replaceAll(' ', '').trim();
    if (id.isEmpty) {
      showToast('请输入设备 ID');
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
              backgroundColor: const Color(0xFFF1F2F4),
              foregroundColor: UuTheme.textSecondary,
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 10),
            ),
            child: const Text('添加收藏设备'),
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
                      color: const Color(0xFFE8F4FF),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(
                      Icons.inventory_2_outlined,
                      size: 48,
                      color: Color(0xFF69B7FF),
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    '暂无收藏',
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
          for (final peer in favorites) _allDeviceRow(peer),
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
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: const BoxDecoration(
        color: Colors.white,
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
                    online ? '在线' : '离线',
                    style: const TextStyle(color: Colors.white, fontSize: 11),
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
                            ? '我的设备'
                            : uuPeerName(selected)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: UuTheme.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (pageTitle == null)
                  PopupMenuButton<String>(
                    icon: const Icon(
                      Icons.more_vert,
                      size: 18,
                      color: UuTheme.textSecondary,
                    ),
                    onSelected: (value) {
                      if (value == 'copy') {
                        final text =
                            selected?.id ?? gFFI.serverModel.serverId.text;
                        Clipboard.setData(ClipboardData(text: text));
                        showToast('已复制');
                      } else if (value == 'refresh') {
                        bind.mainLoadRecentPeers();
                      }
                    },
                    itemBuilder: (context) => const [
                      PopupMenuItem(value: 'copy', child: Text('复制 ID')),
                      PopupMenuItem(value: 'refresh', child: Text('刷新设备')),
                    ],
                  ),
              ],
            ),
          ),
          _HoverCircle(
            icon: Icons.monitor_outlined,
            onTap: () => showUuSettingsDialog(
                context, initialTab: SettingsTabKey.display),
          ),
          const SizedBox(width: 8),
          Stack(
            clipBehavior: Clip.none,
            children: [
              _HoverCircle(
                icon: Icons.notifications_none,
                onTap: _showNotifications,
              ),
              if (_needsPermissions)
                Positioned(
                  right: 2,
                  top: 2,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Color(0xFFF59E0B),
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
                loggedIn ? gFFI.userModel.displayNameOrUserName : '登录 / 注册';
            return Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: () => uuAccountDialog(context),
                child: Container(
                  height: 36,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: loggedIn ? UuTheme.accentSoft : Colors.white,
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
                          style: const TextStyle(
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
          PopupMenuButton<String>(
            tooltip: '更多',
            padding: EdgeInsets.zero,
            child: const _CircleSurface(icon: Icons.menu),
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
                  unawaited(gFFI.userModel.logOut());
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
            itemBuilder: (context) => [
              _menuItem('settings', Icons.settings_outlined, '设置'),
              _menuItem('help', Icons.help_outline, '帮助与反馈'),
              _menuItem('about', Icons.info_outline, '关于'),
              if (gFFI.userModel.isLogin)
                _menuItem('logout', Icons.logout, '退出登录'),
              _menuItem(
                'check-update',
                Icons.system_update_alt,
                '检查更新',
              ),
              const PopupMenuDivider(),
              _menuItem(
                'demo',
                _demoVisible
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                _demoVisible ? '隐藏演示设备' : '显示演示设备',
              ),
              _menuItem('local', Icons.computer_outlined, '本机信息'),
              _menuItem('hero', Icons.image_outlined, '更换背景图'),
              if (_heroImage.isNotEmpty)
                _menuItem(
                  'hero-reset',
                  Icons.hide_image_outlined,
                  '恢复默认背景',
                ),
            ],
          ),
        ],
      ),
    );
  }

  PopupMenuItem<String> _menuItem(
    String value,
    IconData icon,
    String label,
  ) {
    return PopupMenuItem<String>(
      value: value,
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Icon(icon, size: 16, color: UuTheme.textSecondary),
          const SizedBox(width: 10),
          Text(label, style: const TextStyle(fontSize: 13)),
        ],
      ),
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
                Icons.desktop_windows,
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
                  _enterDesktopButton(() => _connectPeer(peer)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyHero(BuildContext context) {
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
                Icons.devices_other,
                size: 320,
                color: Colors.white.withOpacity(0.10),
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
                  _enterDesktopButton(() => _showQuickConnect()),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _enterDesktopButton(VoidCallback onTap) {
    return Center(
      child: TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '进入桌面',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w600,
                shadows: [Shadow(blurRadius: 8, color: Colors.black45)],
              ),
            ),
            SizedBox(width: 8),
            Icon(Icons.arrow_forward, color: Colors.white, size: 20),
          ],
        ),
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: UuTheme.divider),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: [
          _action(
            Icons.swap_horiz,
            '文件传输',
            () => run(isFileTransfer: true),
          ),
          _actionDivider(),
          _action(
            Icons.play_circle_outline,
            '观看模式',
            () => run(),
          ),
          _actionDivider(),
          _action(
            Icons.terminal,
            '终端',
            () => run(isTerminal: true),
          ),
          _actionDivider(),
          _action(
            Icons.settings_ethernet,
            '端口映射',
            () => run(isTcpTunneling: true),
          ),
          _actionDivider(),
          Expanded(
            child: Center(
              child: PopupMenuButton<String>(
                tooltip: '更多',
                icon: const Icon(
                  Icons.grid_view,
                  size: 18,
                  color: UuTheme.textSecondary,
                ),
                onSelected: (value) {
                  if (value == 'camera') {
                    run(isViewCamera: true);
                  } else if (value == 'copy' && peer != null) {
                    Clipboard.setData(ClipboardData(text: peer.id));
                    showToast('已复制');
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(value: 'camera', child: Text('摄像头')),
                  if (peer != null)
                    const PopupMenuItem(value: 'copy', child: Text('复制 ID')),
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
            color: isHovered ? const Color(0xFFF6F6F6) : Colors.transparent,
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
                    style: const TextStyle(
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

  Widget _buildAddCard(BuildContext context) {
    return _AddCard(onTap: () => _showQuickConnect());
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
        color: const Color(0xFFFFF8EC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFFE2B8)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            size: 16,
            color: Color(0xFFF59E0B),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: UuTheme.textSecondary,
                fontSize: 11,
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

class _DashedBorderPainter extends CustomPainter {
  _DashedBorderPainter({required this.color, this.radius = 12});

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    final path = Path()..addRRect(rrect);
    const dash = 6.0;
    const gap = 5.0;
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = (distance + dash).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(distance, next), paint);
        distance = next + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.radius != radius;
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
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: _circleDecoration(_hovered, widget.icon),
    );
  }
}

Widget _circleDecoration(bool hovered, IconData icon) {
  return Container(
    width: 36,
    height: 36,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: hovered ? const Color(0xFFECECEC) : Colors.white,
      border: Border.all(color: const Color(0xFFE5E7EB)),
    ),
    child: Icon(icon, size: 18, color: UuTheme.textSecondary),
  );
}

class _AddCard extends StatefulWidget {
  const _AddCard({required this.onTap});

  final VoidCallback onTap;

  @override
  State<_AddCard> createState() => _AddCardState();
}

class _AddCardState extends State<_AddCard> {
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
        child: TweenAnimationBuilder<Color?>(
          tween: ColorTween(
            begin: const Color(0xFFD9DEE7),
            end: _hovered
                ? const Color(0xFFC8CDD6)
                : const Color(0xFFD9DEE7),
          ),
          duration: const Duration(milliseconds: 200),
          builder: (context, color, child) {
            return CustomPaint(
              foregroundPainter: _DashedBorderPainter(
                color: color ?? const Color(0xFFD9DEE7),
                radius: 12,
              ),
              child: Container(
                height: 160,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 50,
                      height: 50,
                      decoration: const BoxDecoration(
                        color: Color(0xFFF0F0F0),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.add,
                        color: UuTheme.textSecondary,
                        size: 24,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      translate('Add'),
                      style: const TextStyle(
                        color: UuTheme.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
